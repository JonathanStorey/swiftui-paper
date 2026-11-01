# SwiftUI Paper: API Specification and Build Plan

**Status:** v2.1 · **Date:** 2026-11-01 · Decision history is in [REVIEW.md](REVIEW.md) and the git log. SDK evidence is in `docs/SDK-FINDINGS.md` (branch `phase1/sdk-findings`).

SwiftUI Paper wraps Apple's PaperKit, and the iOS 27 PencilKit features it builds on, in an API that reads like native SwiftUI. The scope is **one sheet of paper**: an editor, a read-only view, and one value type, `Paper`. Files, multi-page documents, and app metadata belong to the app.

**Platforms:** iOS, iPadOS, macOS, and visionOS 27+. Swift 6.4 tools, Swift 6 language mode, strict concurrency. Backward compatibility is out of scope: no older OS versions, no older PaperKit feature sets, and no `PKDrawing` import.

**Design rules**

- `Paper` is a value the app owns, bound like `TextEditor(text:)`.
- Value types are nested under `Paper` (`Paper.Tool`, `Paper.Size`), the way `Font.Weight` and `Image.ResizingMode` are nested. Views and editor settings are top-level `Paper…` names (`PaperEditor`, `PaperContentMode`).
- Initializers say what a view *is*. Modifiers say how it *behaves*.
- Where SwiftUI already has a modifier or environment value, use it instead of a new `paper…` modifier.
- Two-way interaction state is a binding to a small value, like `@FocusState`.
- There is no public coordinator, context object, proxy, or custom property wrapper.
- Every public type is `Sendable`. Values are `Hashable`, and `Codable` where storing them makes sense.

> **(UI check)** marks behavior that the SDK headers can't settle and a running app must confirm. Each one has a fallback.

---

## 1. Overview

```
Views                                   Value
─────                                   ─────
PaperEditor   edit, zoom      ◀────▶   Paper
PaperView     read-only render          ├─ elements: ink, shapes, text boxes, images
PDFPageView   sharp PDF page            │    (each one editable or locked)
                                        └─ background: PDF page or image (optional)
```

```swift
import PaperUI

struct WorksheetView: View {
    @State private var paper = Paper(pdfPage: worksheetPage)
    @State private var tool: Paper.Tool = .pen(.black, width: 3)
    @State private var position = PaperScrollPosition()
    @State private var showPicker = true

    var body: some View {
        PaperEditor(paper: $paper)
            .paperTool($tool)
            .paperToolPicker(isPresented: $showPicker)
            .paperContentMode(.fitWidth, anchor: .top)
            .paperScrollPosition($position)
            .toolbar {
                Button("Submit") { paper.lockAll() }
                ShareLink(item: paper, preview: SharePreview("Worksheet"))
            }
    }
}
```

---

## 2. Views

### 2.1 `PaperEditor`

```swift
public struct PaperEditor<Background: View>: View {
    public init(paper: Binding<Paper>, @ViewBuilder on background: () -> Background)
}
extension PaperEditor where Background == PaperBackgroundView {
    public init(paper: Binding<Paper>)                       // uses paper.background, if any
}
extension PaperEditor where Background == Image {
    public init(paper: Binding<Paper>, on image: Image)
}
extension PaperEditor where Background == PDFPageView {
    public init(paper: Binding<Paper>, on page: PDFPage)
}
```

**Behavior**

- **Backgrounds.** `init(paper:)` shows the background stored in the `Paper`. The `on:` forms supply a background the app manages itself, such as pages from a large shared PDF, and they take precedence over a stored one.
- **Editing.** Editable elements can be drawn on, selected, and changed. Locked elements are visible but can't be selected, moved, resized, restyled, or deleted.
- **Sizing.** Greedy: fills the space offered. Its ideal size is the paper size, so `.aspectRatio(contentMode:)` works if applied.
- **Page placement.** Set by `.paperContentMode(_:anchor:)` (Section 5.1). The page keeps its own size, so rotating the device never moves strokes.
- **No binding writes in `init`.** A `Paper` matched to a PDF page's size is created with `Paper(pdfPage:)` or `Paper.Size(page)`.

**Internals**

- `UIViewControllerRepresentable` (`NSViewControllerRepresentable` on macOS) wrapping `PaperMarkupViewController(markup:supportedFeatureSet:)`.
- The background becomes `contentView`, framed to the page rect:
  - View builder and `Image`: placed in a `UIHostingController`, whose view is assigned.
  - `PDFPage` and stored `.pdfPage` backgrounds: a native `CATiledLayer` view drawing with PDFKit, sharp at every zoom.
- **(UI check)** Does `contentView` follow zoom and scroll on its own? Fallback: the coordinator applies the scroll transform to it.

### 2.2 `PaperView` (read-only, also the thumbnail)

```swift
public struct PaperView<Background: View>: View {
    public init(_ paper: Paper, @ViewBuilder on background: () -> Background)
}
extension PaperView where Background == PaperBackgroundView { public init(_ paper: Paper) }
extension PaperView where Background == Image              { public init(_ paper: Paper, on image: Image) }
extension PaperView where Background == PDFPageView        { public init(_ paper: Paper, on page: PDFPage) }
```

- Renders a bitmap at its laid-out size times `\.displayScale`, so a 120 pt thumbnail costs a 120 pt render.
- Ideal size is the paper size, and it keeps the page's aspect ratio, so `.frame(width: 120)` gives a correctly shaped thumbnail.
- Async like `AsyncImage`. The paper color shows until rendering finishes.
- Not zoomable. For a zoomable read-only page, use `PaperEditor(...).disabled(true)`.
- The default `accessibilityLabel` is the paper's indexable text.
- Not usable with `ImageRenderer`. Use `paper.image(scale:)` instead.
- **Internals:** `.task(id:)` keyed on the paper's token and the view size, calling `image(fitting:)`. Results are cached in a process-wide `NSCache`.

### 2.3 `PDFPageView`

```swift
public struct PDFPageView: View {
    public init(_ page: PDFPage)
}
```

The same tiled PDF view the editor uses, usable on its own.

---

## 3. Modifiers

### 3.1 Two-way bindings

```swift
extension View {
    public func paperTool(_ tool: Binding<Paper.Tool>) -> some View
    public func paperSelection(_ selection: Binding<Paper.Selection>) -> some View
    public func paperScrollPosition(_ position: Binding<PaperScrollPosition>) -> some View
    public func paperToolPicker(isPresented: Binding<Bool>, items: [PaperToolPickerItem] = PaperToolPickerItem.standard) -> some View
    public func paperInsertionMenu(isPresented: Binding<Bool>) -> some View
    public func paperAdornments(_ adornments: Binding<[PaperAdornment]>, onTap action: @escaping (_ id: PaperAdornment.ID) -> Void = { _ in }) -> some View
}
```

| Modifier | Behavior | PaperKit underneath |
|---|---|---|
| `paperTool(_:)` | Picking a tool in the system picker writes back. A custom picker item sets `.custom(id:)` | `drawingTool`, `PKToolPickerObserver` |
| `paperSelection(_:)` | Fully two-way. Locked elements are never selected | `selection: Set<MarkupOrderedSet.ElementID> { get set }` |
| `paperScrollPosition(_:)` | The app calls methods on the value. The editor scrolls and reports `visibleRect` back | `setContentVisibleFrame(_:animated:)`, `contentVisibleFrame` |
| `paperToolPicker(isPresented:items:)` | System tool picker on iOS and visionOS. Markup toolbar on macOS | `PKToolPicker` / `MarkupToolbarViewController` |
| `paperInsertionMenu(isPresented:)` | Apple's menu for inserting shapes, text, images, and signatures | `MarkupEditViewController` |
| `paperAdornments(_:onTap:)` | App badges placed on the page. Dragging writes back positions | `adornments`, delegate tap and update callbacks |

### 3.2 Configuration

```swift
extension View {
    public func paperFeatures(_ features: Paper.Features) -> some View
    public func paperContentMode(_ mode: PaperContentMode, anchor: UnitPoint = .center) -> some View
    public func paperZoomRange(_ range: ClosedRange<CGFloat>) -> some View
    public func paperInput(direct: PaperTouchMode = .automatic, pointer: PaperTouchMode = .select) -> some View
    public func paperRulerActive(_ isActive: Bool) -> some View                     // iOS and visionOS
    public func paperToolPickerAccessory(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View
}
```

These are environment values, so they apply to every editor below them.

| Modifier | Default | PaperKit underneath |
|---|---|---|
| `paperFeatures(_:)` | `.latest` | `supportedFeatureSet: FeatureSet` |
| `paperContentMode(_:anchor:)` | `.fit`, `.center` | `setContentVisibleFrame`, `zoomRange` |
| `paperZoomRange(_:)` | `1...4`, where `1` is the content mode's resting scale | `zoomRange` |
| `paperInput(direct:pointer:)` | finger follows the system setting; trackpad or mouse selects | `directTouchMode`, `directTouchAutomaticallyDraws`, `indirectPointerTouchMode` |
| `paperRulerActive(_:)` | `false` | `isRulerActive` (not on macOS) |
| `paperToolPickerAccessory(...)` | none | `PKToolPicker.accessoryItem` |

### 3.3 Events

```swift
extension View {
    public func onPaperGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (PaperGeometry) -> T, action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View
    public func onPaperSelectionChange(perform action: @escaping (_ selection: Paper.Selection, _ selectedContent: Paper) -> Void) -> some View
    public func onPaperDrawingBegan(perform action: @escaping () -> Void) -> some View
}
```

- `onPaperGeometryChange` fires only when the transformed value changes.
- `onPaperSelectionChange` passes the selection as its own `Paper` (from `selectedMarkup`), ready to copy or share.
- Content changes need no event: use `.onChange(of: paper)`.

### 3.4 Borrowed SwiftUI modifiers and environment

| SwiftUI API | Editor behavior |
|---|---|
| `.disabled` / `\.isEnabled` | Read-only canvas (`isEditable`) |
| `.scrollDisabled` / `\.isScrollEnabled` | Locks pan and zoom at rest |
| `.scrollIndicators` | Indicator visibility via `scrollConfiguration` |
| `.focused($isFocused)` | First responder: keyboard shortcuts, Edit menu, hardware undo |
| `\.undoManager` | The controller's `undoManager` (iOS and visionOS) |
| `.onPencilDoubleTap`, `.onPencilSqueeze` | Not reimplemented. Apps change the `tool` binding from them when the picker is hidden |
| `\.layoutDirection` | `.leading` and `.trailing` anchors flip in right-to-left languages |
| `\.accessibilityReduceMotion` | Programmatic scrolling is not animated |
| `\.displayScale` | `PaperView` render resolution |
| `.accessibilityLabel` | Overrides the default label |

**Undo rule:** drawing and editing in the canvas are undoable through `\.undoManager`. Changes the app writes to the binding (inserting, locking, loading) are undoable only if the app registers them.

---

## 4. `Paper` and its nested types

### 4.1 `Paper`

```swift
public struct Paper: Codable, Hashable, Sendable, Transferable {
    // Creating
    public init(size: Paper.Size = .letter, background: Paper.Background? = nil)
    public init(pdfPage: PDFPage)                            // size from the page's media box
    public init(image: CGImage, size: Paper.Size)            // image stretched to the page
    public init(dataRepresentation data: Data) throws

    // Page
    public var size: Paper.Size { get set }                  // extends or crops; content stays put
    public var color: Paper.Color? { get set }               // paper color
    public var background: Paper.Background?
    public var isEmpty: Bool { get }
    public var contentBounds: CGRect { get }
    public mutating func rotate(_ turn: Paper.Rotation)
    public mutating func resize(to size: Paper.Size, scalingContent: Bool)

    // Reading content
    public var elements: [Paper.Element] { get }             // bottom to top
    public var strokes: [Paper.Stroke] { get }

    // Editing content
    public mutating func insertShape(_ shape: Paper.Shape, style: Paper.ShapeStyle, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertLine(from start: CGPoint, to end: CGPoint, style: Paper.ShapeStyle, startArrow: Bool = false, endArrow: Bool = false)
    public mutating func insertText(_ text: AttributedString, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertImage(_ image: CGImage, in frame: CGRect, rotation: Angle = .zero)
    public mutating func remove(_ ids: some Collection<Paper.Element.ID>)
    public mutating func append(_ other: Paper)              // other's elements land on top

    // Locking
    public mutating func lock(_ ids: some Collection<Paper.Element.ID>)
    public mutating func unlock(_ ids: some Collection<Paper.Element.ID>)
    public mutating func lockAll()
    public mutating func unlockAll()

    // Archiving
    public mutating func archive() async throws              // everything baked into a searchable PDF background
    public func archived() async throws -> Paper

    // Saving and output
    public func dataRepresentation() async throws -> Data
    public func pdfData() async throws -> Data               // searchable; same bytes archive() stores
    public func image(scale: Double) async throws -> CGImage
    public func image(fitting box: CGSize) async throws -> CGImage

    // Text
    public func indexableText() async -> String?
    public func recognizedText(_ sources: Paper.TextSource.Set = .all) async throws -> String
    public func search(_ query: String, in sources: Paper.TextSource.Set = .all) async throws -> [Paper.TextMatch]
}
```

All coordinates are page coordinates in points, with the origin at the top left. `Transferable` representations: `.swiftPaper` (a custom `UTType` conforming to `public.data`), PDF (from `pdfData()`), and PNG (from `image(scale: 2)`).

### 4.2 Page types

```swift
extension Paper {
    public struct Size: Codable, Hashable, Sendable {
        public var size: CGSize                                  // points, 72 per inch
        public init(_ size: CGSize)
        public init(width: Measurement<UnitLength>, height: Measurement<UnitLength>)
        public init(_ page: PDFPage)                             // media box
        public static let letter, legal, a4, a5, square: Size
        public static func inches(_ width: Double, _ height: Double) -> Size
        public static func millimeters(_ width: Double, _ height: Double) -> Size
        public var landscape: Size { get }
    }

    public enum Background: Codable, Hashable, Sendable {
        case image(Data)          // encoded PNG / JPEG / HEIC, stretched to the page
        case pdfPage(Data)        // single-page PDF extracted from the source document
    }

    public enum Rotation: Hashable, Sendable, CaseIterable { case clockwise, counterclockwise, halfTurn }

    public struct Color: Codable, Hashable, Sendable {
        public var red, green, blue, opacity: Float             // linear; may exceed 1.0 for HDR
        public static let black, white, red, blue, green, yellow: Color
    }
}
// SwiftUI bridge: Paper.Color.init(_ resolved: SwiftUI.Color.Resolved),
//                init(_ color: SwiftUI.Color, in environment: EnvironmentValues), var color: SwiftUI.Color
```

### 4.3 Content types

```swift
extension Paper {
    public struct Element: Identifiable, Hashable, Sendable {
        public struct ID: Hashable, Codable, Sendable { }       // wraps MarkupOrderedSet.ElementID
        public enum Kind: Hashable, Sendable {
            case stroke(Paper.Stroke.ID)
            case shape(Paper.Shape)
            case text                                            // a rectangle shape holding attributed text
            case image
            case link
            case loupe
        }
        public let id: ID
        public let kind: Kind
        public let frame: CGRect
        public let isLocked: Bool                                // allowedInteractions == .readOnly
    }

    public struct Stroke: Identifiable, Codable, Hashable, Sendable {
        public struct ID: Hashable, Codable, Sendable { }       // wraps PKStroke.id (UUID)
        public struct Point: Codable, Hashable, Sendable {
            public let location: CGPoint
            public let timeOffset: TimeInterval
            public let size: CGSize
            public let opacity: CGFloat
            public let force: CGFloat
            public let azimuth: CGFloat
            public let altitude: CGFloat
        }
        public let id: ID
        public let ink: Paper.Ink
        public let points: [Point]
        public let transform: CGAffineTransform
        public let mask: CGPath?
        public let randomSeed: UInt32
        public var path: CGPath { get }                          // PKStrokePath to Bézier
    }

    public struct Selection: Hashable, Sendable {
        public init()
        public init(_ ids: some Collection<Paper.Element.ID>)
        public var ids: Set<Paper.Element.ID>
        public var isEmpty: Bool { get }
        public mutating func clear()
    }
}
// SwiftUI bridge: extension Path { public init(_ stroke: Paper.Stroke) }
```

Elements and strokes are snapshots. Their fields are `let`, and all edits go through `Paper`. `Stroke` hashes by `id` only, while equality compares every field.

### 4.4 Tools

```swift
extension Paper {
    public enum Tool: Codable, Hashable, Sendable {
        case ink(Paper.Ink, width: CGFloat)
        case eraser(Paper.Eraser)
        case lasso
        case custom(id: String)

        public static func pen(_ color: Paper.Color, width: CGFloat = 3) -> Tool
        public static func pencil(_ color: Paper.Color, width: CGFloat = 2) -> Tool
        public static func marker(_ color: Paper.Color, width: CGFloat = 12) -> Tool
        public static func monoline(_ color: Paper.Color, width: CGFloat = 3) -> Tool
        public static func fountainPen(_ color: Paper.Color, width: CGFloat = 4) -> Tool
        public static func watercolor(_ color: Paper.Color, width: CGFloat = 20) -> Tool
        public static func crayon(_ color: Paper.Color, width: CGFloat = 12) -> Tool
        public static func reed(_ color: Paper.Color, width: CGFloat = 6) -> Tool
        public static let eraser: Tool                            // .eraser(.vector)
    }

    public struct Ink: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case pen, pencil, marker, monoline, fountainPen, watercolor, crayon, reed
        }
        public var kind: Kind
        public var color: Paper.Color
    }

    public enum Eraser: Codable, Hashable, Sendable {
        case vector
        case bitmap(width: CGFloat?)
    }
}
```

Decoding an unknown `Ink.Kind` from a newer file falls back to `.pen` rather than failing.

### 4.5 Shapes

```swift
extension Paper {
    public enum Shape: Codable, Hashable, Sendable {
        case rectangle
        case roundedRectangle(cornerRadius: CGFloat)
        case ellipse
        case regularPolygon(sides: Int)                          // 3 for a triangle
        case star
        case chatBubble
        case arrow
        case line                                                // reported for lines; create with insertLine(from:to:)
    }

    public struct ShapeStyle: Codable, Hashable, Sendable {
        public init(stroke: Paper.Color? = .black, fill: Paper.Color? = nil, lineWidth: CGFloat = 2, opacity: Double = 1)
        public var stroke: Paper.Color?
        public var fill: Paper.Color?
        public var lineWidth: CGFloat
        public var opacity: Double
        public static let outline: ShapeStyle
        public static func filled(_ color: Paper.Color) -> ShapeStyle
    }
}
```

`ShapeStyle` always sets fill, stroke, and width explicitly. PaperKit's own default is a black fill, no stroke, and width 0, which is rarely what an app wants.

### 4.6 Text and features

```swift
extension Paper {
    public enum TextSource: Hashable, Sendable {
        case handwriting          // editable ink
        case typed                // editable text boxes
        case locked               // any locked element
        case background           // PDF text layer or OCR of the background

        public struct Set: OptionSet, Hashable, Sendable {
            public static let handwriting, typed, locked, background: Set
            public static let editable: Set                      // [.handwriting, .typed]
            public static let all: Set
        }
    }

    public struct TextMatch: Hashable, Sendable {
        public let text: String
        public let bounds: CGRect                                // page coordinates
        public let source: TextSource
        public let elementIDs: [Paper.Element.ID]                // empty for background matches
    }

    public struct Features: Hashable, Sendable {
        public enum Feature: Hashable, Sendable, CaseIterable {
            case drawing, text, images, stickers, shapeFills, shapeStrokes, shapeOpacity, links, loupes
        }
        public static let latest: Features
        public func removing(_ feature: Feature) -> Features
        public func inserting(_ feature: Feature) -> Features
        public var inks: Swift.Set<Paper.Ink.Kind>
        public var maximumHDRExposure: CGFloat                   // FeatureSet.colorMaximumLinearExposure, default 1.0
    }
}
```

### 4.7 Editor setting types (top level)

```swift
public enum PaperContentMode: Hashable, Sendable { case fit, fill, fitWidth, fitHeight }

public struct PaperGeometry: Equatable, Sendable {
    public var zoomScale: CGFloat           // 1 == the content mode's resting scale
    public var visibleRect: CGRect          // page coordinates
    public var contentSize: CGSize
}

public struct PaperScrollPosition: Hashable, Sendable {
    public init()
    public var visibleRect: CGRect? { get }
    public mutating func scrollTo(rect: CGRect, anchor: UnitPoint? = nil, zoom: Bool = true)
    public mutating func scrollTo(match: Paper.TextMatch)
    public mutating func scrollTo(selection: Paper.Selection)
    public mutating func zoomToFit()
}

public enum PaperTouchMode: Hashable, Sendable {
    case automatic     // finger: follow the system "Only Draw with Apple Pencil" setting
    case draw          // TouchMode.drawing
    case select        // TouchMode.selection; only Pencil draws
}                      // direct touch settings do not exist on macOS and are ignored there

public enum PaperToolPickerItem: Hashable, Sendable {
    case ink(Paper.Ink.Kind)
    case eraser(Paper.Eraser)
    case lasso
    case ruler
    case custom(id: String, name: String, systemImage: String)
    public static let standard: [PaperToolPickerItem]
}

public struct PaperAdornment: Identifiable, Hashable, Sendable {
    public enum Image: Hashable, Sendable { case `default`, systemImage(String), image(CGImage) }
    public enum DragRegion: Hashable, Sendable { case fixed, canvas }
    public let id: UUID
    public var location: CGPoint             // page coordinates (MarkupAdornment anchor .canvas(location:))
    public var image: Image
    public var dragRegion: DragRegion
    public var scalesWithZoom: Bool
    public init(id: UUID = UUID(), location: CGPoint, image: Image = .default, dragRegion: DragRegion = .fixed, scalesWithZoom: Bool = false)
}
```

---

## 5. Behavior specifications

### 5.1 Content modes

| Mode | Resting scale | Overflow |
|---|---|---|
| `.fit` | min(viewW / pageW, viewH / pageH) | None, letterboxed |
| `.fill` | max(viewW / pageW, viewH / pageH) | The axis where the page is relatively longer |
| `.fitWidth` | viewW / pageW | Vertical |
| `.fitHeight` | viewH / pageH | Horizontal |

- The anchor sets the initial scroll position in overflowing modes, and where the letterbox space goes in `.fit`.
- On rotation or resize, the resting scale is recomputed and the anchor re-applied, unless the user has scrolled or zoomed. In that case the same page point stays in view and the relative zoom is kept.
- `zoomScale` and `paperZoomRange` are relative to the resting scale.

### 5.2 Locking

- A locked element has `allowedInteractions = .readOnly`, the empty set, so it can't be selected, moved, resized, restyled, or deleted. The setting survives `dataRepresentation()`.
- `lockAll()` locks every element. Use it to "submit" or "sign off" a page. New drawing then goes on top as editable elements.
- `unlockAll()` restores `.all` interactions. Locking is lossless: strokes keep their vector form and IDs.
- **(UI check)** Do the eraser and lasso respect read-only on ink strokes? Fallback: the coordinator restores any locked stroke the eraser changed, and filters locked IDs out of lasso selections.

### 5.3 Archive and PDF output

`pdfData()`, `archive()`, `archived()`, and the PDF `Transferable` representation all produce the same PDF:

1. Recognize text in every element, with positions (Section 5.6).
2. Render the background, then all elements bottom to top, into a PDF context sized to the paper.
3. Write the recognized text as an invisible text layer at the matching positions.

`archive()` stores that PDF as the background and removes all elements. The page looks identical and stays searchable through PDFKit as `.background`, but element IDs and editing are gone. **(UI check)** Is PaperKit's PDF output vector? Fallback: render ink at 300 dpi into the PDF.

### 5.4 Saving

```swift
let data  = try await paper.dataRepresentation()
let paper = try Paper(dataRepresentation: data)
```

- **Format:** a versioned binary property list holding a format version, the `PaperMarkup` blob exactly as Apple produced it, and the background bytes.
- **Async save, sync load,** mirroring `PaperMarkup`.
- **`Codable`** writes the latest background-refreshed snapshot, which can trail the newest stroke briefly. Use `dataRepresentation()` when freshness matters.
- **SwiftData:** store as `Data` with `@Attribute(.externalStorage)`.

| Format | Use | Editable afterward |
|---|---|---|
| `dataRepresentation()` | Saving work | Yes |
| `pdfData()` | Sending, printing, viewing anywhere | No |
| `archived()` | A sealed `Paper` that `PaperView` can still show | No |

### 5.5 Rendering

- `image(scale:)`: `scale` is relative to the paper size in points (`1.0` on letter gives 612 × 792 px).
- `image(fitting:)`: the largest image with the page's aspect ratio that fits the box.
- Rendering includes the stored background. Built on `PaperMarkup.draw(in:frame:options:) async`.

### 5.6 Text recognition

| Source | Provider |
|---|---|
| `.handwriting` | `PKStrokeRecognizer` (an actor, on device, 29 languages), fed a `PKDrawing` built from editable strokes. Search returns stroke IDs and bounds |
| `.typed` | `attributedText` of editable text-box shapes |
| `.locked` | Both of the above, applied to locked elements |
| `.background` | PDFKit text for text-based PDFs, or Vision `RecognizeTextRequest` for scanned pages and images |

- Background text is cached per `Paper`, keyed on the background bytes.
- Handwriting recognition is incremental, re-recognizing only changed stroke IDs.
- `indexableText()` wraps PaperKit's async `indexableContent`, and is cheaper than full recognition.
- Higher-level AI, such as summaries, is the app's job, for example by passing `recognizedText()` to Foundation Models.

### 5.7 Size, rotation, and resizing

- Setting `size` writes `PaperMarkup.bounds`. Content and stroke IDs are kept, and the page extends or crops from the bottom-right.
- `rotate(_:)`: `transformContent` with a 90° multiple plus a translation back into positive coordinates, then the width and height swap. Lossless. A PDF background gets its page rotation attribute updated, and an image background is rotated by whole pixels and re-encoded as PNG.
- `resize(to:scalingContent:)`: `false` behaves like setting `size`, and `true` also scales content with `transformContent`.

---

## 6. Internals

### 6.1 Package

```
Sources/
└─ PaperUI/      One library. Paper and every nested type, SwiftUI views, modifiers,
                 editor setting types, coordinator, rendering, recognition, file format.
                 Sample data (Paper.sample, Paper.samplePDF) for previews and tests.
Tests/           PaperUITests (Swift Testing)
Demo/            iPad app exercising every public API
```

`swift-tools-version: 6.4` (needed for `.v27` platforms). One module, one `import PaperUI`. Every client of `Paper` is a SwiftUI app on a 27 OS, so a separate UI-free module buys nothing, and splitting later is cheap if a real need appears. Organize by folder instead: `Model/` (Paper and nested types), `Views/`, `Modifiers/`, `Bridge/` (PaperKit conversions and the coordinator), `Output/` (rendering, recognition, file format), `Samples/`. Inside `extension Paper`, write `SwiftUI.Color` and `SwiftUI.Shape`, because the bare names resolve to `Paper.Color` and `Paper.Shape`.

### 6.2 `Paper` storage

- A live `PaperMarkup` (the single source of truth for content, size, and paper color), the optional background bytes, a `token: UUID` regenerated on every mutation, a serialized snapshot for `Codable`, and a projection cache.
- `==` returns true at once if tokens match. Otherwise it compares `PaperMarkup` (Apple's `Equatable`) and then the background bytes. `hash(into:)` uses `size` only.
- The projection cache (`elements`, `strokes`) is a `final class` guarded by a `Mutex` and replaced on mutation, so `Paper` stays `Sendable`.
- Editing goes through `subelements: MarkupOrderedSet` (mutable: `removeElement(for:)`, `removeStroke(for:)`, `removeAll(where:)`). Locking sets each element's `allowedInteractions`.

### 6.3 Coordinator (private)

- Observes `PaperMarkupViewController` with Swift Observation, and uses the delegate where Observation can't help (adornment taps and updates).
- **Loop prevention:** it tracks the last token pushed to and received from the controller. It writes into the controller only when the binding's token matches neither.
- **Coalescing:** the binding updates once per stroke end. The `Codable` snapshot refreshes in the background afterward.
- Owns one `PKToolPicker` per window.
- Applies borrowed environment (3.4), content-mode math (5.1), and locked-element guards (5.2) on each update.
- Feeds `PKStrokeRecognizer` with changed strokes.

### 6.4 Our API to PaperKit

| Ours | PaperKit / PencilKit |
|---|---|
| `Paper` | `PaperMarkup` |
| `size`, `color`, `contentBounds`, `indexableText()` | `bounds`, `backgroundColor`, `contentsRenderFrame`, `indexableContent` |
| `elements`, `strokes`, `remove(_:)` | `subelements: MarkupOrderedSet`, `subelements.strokes: [PKStroke]` |
| `lock`, `unlock`, `Element.isLocked` | element `allowedInteractions` (`.readOnly`, `.all`) |
| `insertShape`, `insertLine`, `insertText`, `insertImage` | `insertNewShape`, `insertNewLine`, `insertNewTextbox`, `insertNewImage` |
| `Paper.Shape`, `Paper.ShapeStyle` | `ShapeConfiguration` |
| `append(_:)`, `rotate`, `resize` | `append(contentsOf: PaperMarkup)`, `transformContent(_:)` |
| `dataRepresentation()`, `init(dataRepresentation:)` | the same on `PaperMarkup` |
| `image`, `pdfData` | `draw(in:frame:options:)` |
| `Paper.Stroke`, `Stroke.ID`, `Stroke.path` | `PKStroke`, `PKStroke.id`, `PKStrokePath` Bézier conversion |
| `Paper.Features` | `FeatureSet` (features, `inks`, `colorMaximumLinearExposure`) |
| `PaperEditor` | `PaperMarkupViewController` + `contentView` |
| `.paperTool`, `.paperToolPicker`, `.paperToolPickerAccessory` | `drawingTool`, `PKToolPicker`, `MarkupToolbarViewController` (macOS) |
| `.paperSelection`, `onPaperSelectionChange` | `selection`, `selectedMarkup` |
| `.paperScrollPosition`, `.paperContentMode`, `.paperZoomRange`, `onPaperGeometryChange` | `setContentVisibleFrame(_:animated:)`, `contentVisibleFrame`, `zoomRange`, `scrollConfiguration` |
| `.paperInput` | `directTouchMode`, `directTouchAutomaticallyDraws`, `indirectPointerTouchMode` |
| `.paperRulerActive`, `.disabled` | `isRulerActive`, `isEditable` |
| `.paperFeatures` | `supportedFeatureSet` |
| `.paperInsertionMenu` | `MarkupEditViewController` |
| `.paperAdornments` | `adornments`, `MarkupAdornment`, delegate callbacks |
| `\.undoManager` | `undoManager` |
| `recognizedText`, `search` | `PKStrokeRecognizer`, PDFKit, Vision |

---

## 7. Coverage

**Every PaperKit capability in the iOS 27 SDK has a SwiftUI path, apart from the intentional exclusions.** All the earlier unknowns were settled against the SDK headers: strokes are readable, IDs survive saving and appending, content can be removed, the selection is settable, the bounds are settable, and adornments, shapes, features, and touch modes are fully specified.

| Area | Status |
|---|---|
| Three behaviors that need a running app | `contentView` following zoom (2.1), eraser and lasso on locked strokes (5.2), vector PDF output (5.3). Each has a fallback |
| Erasing along a path from code | Not offered. `PaperMarkup` has no erase API, and erasing a `PKDrawing` splits strokes into pieces with new IDs. Apps remove whole strokes with `remove(_:)` |
| macOS differences | No direct-touch settings, `isRulerActive`, or `undoManager` override on macOS. Those modifiers do nothing there |
| iOS 27 PencilKit extras | Substroke ranges, `renderGroupID`, and recognizer language preferences are not wrapped. Added on request |
| `RenderingOptions` | Used internally only |

**Excluded by choice:** `PKDrawing` import, `removeContentUnsupported(by:)`, versioned feature sets, and OS versions before 27.

**Beyond PaperKit:** per-element locking with `lockAll()`, archive to a searchable PDF, embedded backgrounds, background OCR, content modes, and `Codable` tools.

---

## 8. Build plan

The SDK check and the package skeleton are done: 18 tests pass on macOS 27 and the iPad simulator. The work is on `phase1/sdk-findings`, waiting to be pushed.

### Phase 1: A working editor (MVP)

- Rework the skeleton to v2.1: collapse the four targets into the single `PaperUI` module, use a single `Paper` type, and adopt the nested names.
- `Paper` storage (6.2), `size`, `color`, `dataRepresentation`, and the `Codable` snapshot.
- `PaperEditor(paper:)` with `.paperTool`, `.paperToolPicker(isPresented:)`, `.paperFeatures`, `.paperContentMode`, `.paperZoomRange`, `.disabled`, and `\.undoManager`.
- The coordinator's loop prevention and coalescing.
- A demo app, plus the UI check for eraser and lasso on locked strokes.

**Done when** the demo draws, rotates the device without moving strokes, saves, relaunches, and restores.

### Phase 2: Backgrounds, locking, and output

- `Paper.Background`, the `on:` initializers, `PDFPageView`, and the `contentView` zoom check.
- `lock`, `unlock`, `lockAll`, `unlockAll`, `rotate`, `resize`, and `append`.
- `PaperView`, `image(scale:)`, `image(fitting:)`, `pdfData()` (text layer added in Phase 4), `Transferable`, and the `.swiftPaper` type. Includes the vector-PDF check.

**Done when** a PDF worksheet can be filled in, locked, rotated, thumbnailed, and shared as a PDF.

### Phase 3: Interaction

- `.paperSelection`, `onPaperSelectionChange`, `.paperScrollPosition`, `onPaperGeometryChange`, and `onPaperDrawingBegan`.
- Insert methods, `remove`, `Paper.Shape`, and `Paper.ShapeStyle`.
- `.paperInput`, `.paperRulerActive`, tool picker items, custom tools, the accessory, `.paperInsertionMenu`, and `.paperAdornments`.
- Borrowed environment, `elements`, `strokes`, and `Stroke.path`.

**Done when** every modifier in Section 3 works in the demo.

### Phase 4: Text and archive

- `recognizedText`, `search`, `indexableText`, and `scrollTo(match:)`.
- The searchable text layer in `pdfData()`, then `archive()` and `archived()`.
- Default accessibility labels.

**Done when** a scanned PDF with handwriting can be searched, a match revealed, and the page archived and still searched.

### Later, when needed

macOS and visionOS polish, a pure-SwiftUI tool palette, arbitrary SwiftUI backgrounds in the editor, view-only rotation, and the PencilKit extras from Section 7.
