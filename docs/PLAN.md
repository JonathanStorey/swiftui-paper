# SwiftUI Paper: API Specification and Build Plan

**Status:** v2.0 · **Date:** 2026-11-01 · Decision history lives in [REVIEW.md](REVIEW.md) and the git log.

SwiftUI Paper wraps Apple's PaperKit (and the iOS 27 PencilKit additions it builds on) in an API that reads like native SwiftUI. Its scope is **one sheet of paper**: an editor, a read-only view, and the value types they work with. Files, multi-page documents, and app metadata belong to the app.

**Platforms:** iOS, iPadOS, macOS, visionOS 27+. Swift 6 language mode, strict concurrency. Backward compatibility (older OS versions, older PaperKit feature sets, PencilKit `PKDrawing` import) is intentionally out of scope.

**Design rules used throughout**

- Content is a value the app owns (`Paper`, `Markup`), bound like `TextEditor(text:)`.
- Initializers say what a view *is*. Modifiers say how it *behaves*.
- If SwiftUI already has a modifier or environment value for something, use it instead of inventing a `paper*` one.
- Two-way interaction state is a binding to a small value type, like `@FocusState`.
- No public coordinator, context object, proxy, or custom property wrapper.
- Every public type is `Sendable`. Value types are `Hashable`, and `Codable` where storing them makes sense.

> Items marked **(verify)** depend on PaperKit behavior Apple's documentation doesn't state. Each has a fallback in Section 8 and is resolved during Phase 1.

---

## 1. Overview

```
┌──────────── Views ─────────────┐   ┌────────── Values ──────────┐
│ PaperEditor   edit, zoom       │   │ Paper                      │
│ PaperView     read-only render │◀──│  ├─ markup:  Markup  (top) │
│ PDFPageView   sharp PDF page   │   │  ├─ locked:  Markup  (mid) │
└────────────────────────────────┘   │  └─ background (bottom)    │
                                     │ Markup ── wraps PaperMarkup│
                                     └────────────────────────────┘
```

```swift
import PaperUI

struct WorksheetView: View {
    @State private var paper = Paper(pdfPage: worksheetPage)
    @State private var tool: PaperTool = .pen(.black, width: 3)
    @State private var position = PaperScrollPosition()
    @State private var showPicker = true

    var body: some View {
        PaperEditor(paper: $paper)
            .paperTool($tool)
            .paperToolPicker(isPresented: $showPicker)
            .paperContentMode(.fitWidth, anchor: .top)
            .paperScrollPosition($position)
            .toolbar {
                Button("Submit") { paper.flatten() }
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
    public init(markup: Binding<Markup>, @ViewBuilder on background: () -> Background)
}
extension PaperEditor where Background == PaperBackgroundView {
    public init(paper: Binding<Paper>)                       // the usual form
}
extension PaperEditor where Background == EmptyView {
    public init(markup: Binding<Markup>)                     // plain paper
}
extension PaperEditor where Background == Image {
    public init(markup: Binding<Markup>, on image: Image)
}
extension PaperEditor where Background == PDFPageView {
    public init(markup: Binding<Markup>, on page: PDFPage)
}
```

**Behavior**

- **Editing.** With `paper:`, only `paper.markup` is editable. `paper.locked` and `paper.background` are visible underneath and cannot be touched. The `markup:` forms are for apps that manage backgrounds themselves.
- **Sizing.** Greedy: fills the space offered, like `Color` or a `.resizable()` image. Its ideal size (from `sizeThatFits` with an unspecified proposal) is the paper size, so `.aspectRatio(contentMode:)` works if applied.
- **Page placement.** Set by `.paperContentMode(_:anchor:)` (Section 3.2). The page keeps its own size, so rotation of the device never moves strokes.
- **Background framing.** Any background is laid out in the page rect and scales with zoom.
- **Initializers never write to the binding.** Matching a markup to a PDF page's size happens when the value is created (`Paper(pdfPage:)`, `PaperSize(page)`).

**Internals**

- `UIViewControllerRepresentable` (`NSViewControllerRepresentable` on macOS) wrapping `PaperMarkupViewController`, created with `supportedFeatureSet` from `.paperFeatures` (default `.latest`).
- Backgrounds become `PaperMarkupViewController.contentView`, framed to the page rect:
  - View builder and `Image`: the view is placed in a `UIHostingController`, and its view is assigned. (A SwiftUI `Image` can't be turned back into a `UIImage`.)
  - `PDFPage`: a native `CATiledLayer` view drawing the page with PDFKit, which stays sharp at every zoom.
  - `paper:` form: a stacked view (`PaperBackgroundView`) with the background (PDF tiled view or hosted image) at the bottom and `locked` above it. `locked` is rendered once to an untagged single-page PDF and shown through the tiled view, then re-rendered only when `locked` changes.
- Whether `contentView` follows zoom and scroll automatically is **(verify)**. Fallback: the coordinator applies the scroll view's transform to `contentView` itself.

### 2.2 `PaperView` (read-only, also the thumbnail)

```swift
public struct PaperView<Background: View>: View {
    public init(_ markup: Markup, @ViewBuilder on background: () -> Background)
}
extension PaperView where Background == PaperBackgroundView { public init(_ paper: Paper) }
extension PaperView where Background == EmptyView          { public init(_ markup: Markup) }
extension PaperView where Background == Image              { public init(_ markup: Markup, on image: Image) }
extension PaperView where Background == PDFPageView        { public init(_ markup: Markup, on page: PDFPage) }
```

**Behavior**

- Renders a bitmap at its laid-out size times `\.displayScale`, so a 120 pt thumbnail costs a 120 pt render.
- Ideal size is the paper size, and it keeps the page's aspect ratio, so `.frame(width: 120)` alone gives a correctly shaped thumbnail.
- Async like `AsyncImage`: shows the paper color until rendering finishes.
- Not zoomable. For a zoomable read-only page, use `PaperEditor(...).disabled(true)`.
- Default `accessibilityLabel` is the markup's `indexableContent`.
- Not usable with `ImageRenderer` (it renders synchronously and would capture the placeholder). Use `paper.image(scale:)`.

**Internals:** `.task(id:)` keyed on content tokens plus size, calling `image(fitting:)`. Results cached by token and size in a process-wide `NSCache`.

### 2.3 `PDFPageView`

```swift
public struct PDFPageView: View {
    public init(_ page: PDFPage)
}
```

A SwiftUI face for the same tiled PDF view the editor uses. Usable on its own.

---

## 3. Modifiers

### 3.1 Two-way bindings

```swift
extension View {
    public func paperTool(_ tool: Binding<PaperTool>) -> some View
    public func paperSelection(_ selection: Binding<PaperSelection>) -> some View          // (verify) setter
    public func paperScrollPosition(_ position: Binding<PaperScrollPosition>) -> some View
    public func paperToolPicker(isPresented: Binding<Bool>, items: [PaperToolPickerItem] = PaperToolPickerItem.standard) -> some View
    public func paperInsertionMenu(isPresented: Binding<Bool>) -> some View
}
```

| Modifier | Behavior | PaperKit underneath |
|---|---|---|
| `paperTool(_:)` | Two-way. Picking a tool in the system picker writes back. Choosing a custom picker item sets `.custom(id:)` | `drawingTool: any PKTool`, `PKToolPickerObserver` |
| `paperSelection(_:)` | Two-way if PaperKit allows setting. Otherwise, read through `onPaperSelectionChange` | `selection: Set<MarkupOrderedSet.ElementID>` |
| `paperScrollPosition(_:)` | The app calls methods on the value. The editor scrolls and reports `visibleRect` back | `setContentVisibleFrame(_:animated:)`, `contentVisibleFrame` |
| `paperToolPicker(isPresented:items:)` | System tool picker on iOS and visionOS, Apple's markup toolbar on macOS. The user can dismiss it, so it is a binding | `PKToolPicker` / `MarkupToolbarViewController` |
| `paperInsertionMenu(isPresented:)` | Apple's insertion menu for shapes, text, images, and signatures | `MarkupEditViewController` |

### 3.2 Configuration

```swift
extension View {
    public func paperFeatures(_ features: PaperFeatures) -> some View
    public func paperContentMode(_ mode: PaperContentMode, anchor: UnitPoint = .center) -> some View
    public func paperZoomRange(_ range: ClosedRange<CGFloat>) -> some View
    public func paperInput(direct: PaperTouchMode = .automatic, pointer: PaperTouchMode = .automatic) -> some View
    public func paperRulerActive(_ isActive: Bool) -> some View
    public func paperToolPickerAccessory(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View
    public func paperAdornments(_ adornments: [PaperAdornment]) -> some View             // (verify) shape
}
```

All are environment values, so they apply to every editor below them.

| Modifier | Behavior | PaperKit underneath |
|---|---|---|
| `paperFeatures(_:)` | Which tools and elements exist. Default `.latest` | `supportedFeatureSet: FeatureSet` |
| `paperContentMode(_:anchor:)` | How the page sits in the view at rest (Section 5.1). Default `.fit`, `.center` | `setContentVisibleFrame`, `zoomRange` |
| `paperZoomRange(_:)` | Min and max zoom, where `1` is the content mode's resting scale. Default `1...4` | `zoomRange` |
| `paperInput(direct:pointer:)` | `direct`: finger. `pointer`: trackpad or mouse | `directTouchMode`, `directTouchAutomaticallyDraws`, `indirectPointerTouchMode` |
| `paperRulerActive(_:)` | Shows the ruler | `isRulerActive` |
| `paperToolPickerAccessory(...)` | One accessory button in the tool picker | `PKToolPicker.accessoryItem` |
| `paperAdornments(_:)` | App-supplied adornments on markup | `adornments`, `adornmentFrame(for:)` |

### 3.3 Events

```swift
extension View {
    public func onPaperGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (PaperGeometry) -> T, action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View
    public func onPaperSelectionChange(perform action: @escaping (_ selection: PaperSelection, _ selectedContent: Markup) -> Void) -> some View
    public func onPaperDrawingBegan(perform action: @escaping () -> Void) -> some View
}
```

- `onPaperGeometryChange` fires only when the transformed value changes, as `onScrollGeometryChange` does.
- `onPaperSelectionChange` passes the selected content as its own `Markup` (from `selectedMarkup`), ready to copy or share.
- Content changes need no event: use `.onChange(of: paper)`.

### 3.4 Borrowed SwiftUI modifiers and environment

| SwiftUI API | Editor behavior |
|---|---|
| `.disabled` / `\.isEnabled` | Read-only canvas (`isEditable`) |
| `.scrollDisabled` / `\.isScrollEnabled` | Locks pan and zoom at rest |
| `.scrollIndicators` | Indicator visibility via `scrollConfiguration` |
| `.focused($isFocused)` | First responder: keyboard shortcuts, Edit menu, hardware undo |
| `\.undoManager` | Exposes the controller's `undoManager` |
| `.onPencilDoubleTap`, `.onPencilSqueeze` | Not reimplemented. Apps change the `tool` binding from them when the picker is hidden |
| `\.layoutDirection` | `.leading`/`.trailing` anchors flip in right-to-left languages |
| `\.accessibilityReduceMotion` | Programmatic scrolling is not animated |
| `\.displayScale` | `PaperView` render resolution |
| `.accessibilityLabel` | Overrides the default label taken from `indexableContent` |

**Undo rule:** drawing and editing in the canvas are undoable through `\.undoManager`. Changes the app writes to the binding (inserting, flattening, loading) are undoable only if the app registers them.

---

## 4. Value types

### 4.1 `Paper`: one self-contained sheet

```swift
public struct Paper: Codable, Hashable, Sendable, Transferable {
    public var markup: Markup                       // top: editable
    public var locked: Markup                       // middle: visible, not editable; empty by default
    public var background: PaperBackground?         // bottom: static template

    public init(size: PaperSize = .letter, background: PaperBackground? = nil)
    public init(markup: Markup, locked: Markup? = nil, background: PaperBackground? = nil)
    public init(pdfPage: PDFPage)                   // size from the page's media box
    public init(image: CGImage, size: PaperSize)    // image stretched to the page
    public init(dataRepresentation data: Data) throws

    public var size: PaperSize { get set }          // keeps markup and locked the same size
    public var isEmpty: Bool { get }                // markup and locked both empty

    // Layers
    public mutating func flatten()                  // markup appended onto locked; markup emptied
    public mutating func unlock()                   // locked placed under markup; locked emptied
    public mutating func archive() async throws     // all layers baked into a searchable PDF background
    public func archived() async throws -> Paper

    // Page edits
    public mutating func rotate(_ turn: PaperRotation)
    public mutating func resize(to size: PaperSize, scalingContent: Bool)

    // Saving and output
    public func dataRepresentation() async throws -> Data
    public func pdfData() async throws -> Data      // searchable PDF, same bytes archive() stores
    public func image(scale: Double) async throws -> CGImage
    public func image(fitting box: CGSize) async throws -> CGImage

    // Text
    public func recognizedText(_ sources: PaperTextSource.Set = .all) async throws -> String
    public func search(_ query: String, in sources: PaperTextSource.Set = .all) async throws -> [PaperTextMatch]
}

public enum PaperBackground: Codable, Hashable, Sendable {
    case image(Data)        // encoded PNG / JPEG / HEIC, stretched to the page
    case pdfPage(Data)      // a single-page PDF extracted from the source document
}
```

`Transferable` representations: `.swiftPaper` (custom `UTType` conforming to `public.data`), PDF (from `pdfData()`), and PNG (from `image(scale: 2)`).

### 4.2 `Markup`: the content layer

```swift
public struct Markup: Codable, Hashable, Sendable, Transferable {
    public init(paperSize: PaperSize = .letter)
    public init(dataRepresentation data: Data) throws

    public var paperSize: PaperSize { get set }     // PaperMarkup.bounds
    public var paperColor: CGColor? { get set }     // PaperMarkup.backgroundColor
    public var isEmpty: Bool { get }
    public var contentBounds: CGRect { get }        // PaperMarkup.contentsRenderFrame
    public var indexableContent: String? { get }    // PaperMarkup.indexableContent

    // Read-only projections
    public var elements: [PaperElement] { get }
    public var strokes: [PaperStroke] { get }       // (verify) ink readable via subelements

    // Edits
    public mutating func insertShape(_ shape: PaperShape, style: PaperShapeStyle, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertLine(from start: CGPoint, to end: CGPoint, style: PaperShapeStyle, startArrow: Bool = false, endArrow: Bool = false)
    public mutating func insertText(_ text: AttributedString, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertImage(_ image: CGImage, in frame: CGRect, rotation: Angle = .zero)
    public mutating func remove(_ ids: some Collection<PaperElement.ID>)        // (verify)
    public mutating func erase(along path: CGPath, width: CGFloat)
    public mutating func append(_ other: Markup)                                // other lands on top
    public mutating func rotate(_ turn: PaperRotation)
    public mutating func resize(to size: PaperSize, scalingContent: Bool)

    // Saving and output (no background)
    public func dataRepresentation() async throws -> Data
    public func pdfData() async throws -> Data
    public func image(scale: Double) async throws -> CGImage
    public func image(fitting box: CGSize) async throws -> CGImage

    // Text (sources .handwriting and .typed)
    public func recognizedText(_ sources: PaperTextSource.Set = .markup) async throws -> String
    public func search(_ query: String, in sources: PaperTextSource.Set = .markup) async throws -> [PaperTextMatch]
}
```

All coordinates are page coordinates in points, with the origin at the top left.

### 4.3 Elements, strokes, and selection

```swift
public struct PaperElement: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Codable, Sendable { }   // wraps MarkupOrderedSet.ElementID
    public enum Kind: Hashable, Sendable { case stroke(PaperStroke.ID), shape, line, text, image, other }
    public let id: ID
    public let kind: Kind
    public let frame: CGRect
}

public struct PaperStroke: Identifiable, Codable, Hashable, Sendable {
    public struct ID: Hashable, Codable, Sendable { }   // wraps PKStroke.id (UUID, iOS 27)
    public let id: ID
    public let ink: PaperInk
    public let points: [PaperStrokePoint]
    public let transform: CGAffineTransform
    public let mask: CGPath?
    public let randomSeed: UInt32
    public var path: CGPath { get }                     // PKStrokePath → Bézier (iOS 27)
}

public struct PaperStrokePoint: Codable, Hashable, Sendable {
    public let location: CGPoint
    public let timeOffset: TimeInterval
    public let size: CGSize
    public let opacity: CGFloat
    public let force: CGFloat
    public let azimuth: CGFloat
    public let altitude: CGFloat
}

public struct PaperSelection: Hashable, Sendable {
    public init()
    public var ids: Set<PaperElement.ID>
    public var isEmpty: Bool { get }
    public mutating func clear()
}
```

`PaperUI` adds `extension Path { public init(_ stroke: PaperStroke) }`. Strokes and elements are snapshots: fields are `let`, and all edits go through `Markup`. `PaperStroke` hashes by `id` only, while equality compares every field.

### 4.4 Tools

```swift
public enum PaperTool: Codable, Hashable, Sendable {
    case inking(InkingTool)
    case eraser(EraserMode)
    case lasso
    case custom(id: String)

    public static func pen(_ color: PaperColor, width: CGFloat = 3) -> PaperTool
    public static func pencil(_ color: PaperColor, width: CGFloat = 2) -> PaperTool
    public static func marker(_ color: PaperColor, width: CGFloat = 12) -> PaperTool
    public static func monoline(_ color: PaperColor, width: CGFloat = 3) -> PaperTool
    public static func fountainPen(_ color: PaperColor, width: CGFloat = 4) -> PaperTool
    public static func watercolor(_ color: PaperColor, width: CGFloat = 20) -> PaperTool
    public static func crayon(_ color: PaperColor, width: CGFloat = 12) -> PaperTool
    public static let eraser: PaperTool              // .eraser(.vector)
}

public struct InkingTool: Codable, Hashable, Sendable { public var ink: PaperInk; public var width: CGFloat }
public struct PaperInk: Codable, Hashable, Sendable { public var kind: InkKind; public var color: PaperColor }
public enum InkKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon
}
public enum EraserMode: Codable, Hashable, Sendable { case vector; case bitmap(width: CGFloat?) }

public enum PaperToolPickerItem: Hashable, Sendable {
    case ink(InkKind)
    case eraser(EraserMode)
    case lasso
    case ruler
    case custom(id: String, name: String, systemImage: String)
    public static let standard: [PaperToolPickerItem]
}
```

Decoding an unknown `InkKind` from a newer file falls back to `.pen` rather than failing.

### 4.5 Shapes (for inserting)

```swift
public enum PaperShape: Codable, Hashable, Sendable {
    case rectangle, roundedRectangle, ellipse, triangle, star, speechBubble   // (verify) ShapeConfiguration cases
}

public struct PaperShapeStyle: Codable, Hashable, Sendable {
    public init(stroke: PaperColor? = .black, fill: PaperColor? = nil, lineWidth: CGFloat = 2)
    public var stroke: PaperColor?
    public var fill: PaperColor?
    public var lineWidth: CGFloat
    public static let outline: PaperShapeStyle
    public static func filled(_ color: PaperColor) -> PaperShapeStyle
}
```

### 4.6 Size, layout, and geometry

```swift
public struct PaperSize: Codable, Hashable, Sendable {
    public var size: CGSize                                      // points, 72 per inch
    public init(_ size: CGSize)
    public init(width: Measurement<UnitLength>, height: Measurement<UnitLength>)
    public init(_ page: PDFPage)                                 // media box
    public static let letter, legal, a4, a5, square: PaperSize
    public static func inches(_ width: Double, _ height: Double) -> PaperSize
    public static func millimeters(_ width: Double, _ height: Double) -> PaperSize
    public var landscape: PaperSize { get }
}

public enum PaperRotation: Hashable, Sendable, CaseIterable { case clockwise, counterclockwise, halfTurn }

public enum PaperContentMode: Hashable, Sendable { case fit, fill, fitWidth, fitHeight }

public struct PaperGeometry: Equatable, Sendable {
    public var zoomScale: CGFloat          // 1 == the content mode's resting scale
    public var visibleRect: CGRect         // page coordinates
    public var contentSize: CGSize
}

public struct PaperScrollPosition: Hashable, Sendable {
    public init()
    public var visibleRect: CGRect? { get }                      // last reported by the editor
    public mutating func scrollTo(rect: CGRect, anchor: UnitPoint? = nil, zoom: Bool = true)
    public mutating func scrollTo(match: PaperTextMatch)
    public mutating func scrollTo(selection: PaperSelection)
    public mutating func zoomToFit()                             // back to the resting state
}
```

### 4.7 Text

```swift
public enum PaperTextSource: Hashable, Sendable {
    case handwriting      // ink in markup
    case typed            // text boxes in markup
    case locked           // anything in the locked layer
    case background       // PDF text layer or OCR of the background

    public struct Set: OptionSet, Hashable, Sendable {
        public static let handwriting, typed, locked, background: Set
        public static let markup: Set        // [.handwriting, .typed]
        public static let all: Set
    }
}

public struct PaperTextMatch: Hashable, Sendable {
    public let text: String
    public let bounds: CGRect             // page coordinates
    public let source: PaperTextSource
}
```

### 4.8 Configuration types

```swift
public struct PaperColor: Codable, Hashable, Sendable {
    public var red, green, blue, opacity: Float          // linear; may exceed 1.0 for HDR
    public static let black, white, red, blue, green, yellow: PaperColor
}
// PaperUI: init(_ resolved: Color.Resolved), init(_ color: Color, in environment: EnvironmentValues), var color: Color

public struct PaperFeatures: Hashable, Sendable {
    public static let latest: PaperFeatures
    public func removing(_ feature: Feature) -> PaperFeatures
    public func inserting(_ feature: Feature) -> PaperFeatures
    public var maximumHDRExposure: Double                 // FeatureSet.colorMaximumLinearExposure
    public enum Feature: Hashable, Sendable { }           // (verify) mirrors FeatureSet's features
}

public enum PaperTouchMode: Hashable, Sendable {
    case automatic        // follow the system "Only Draw with Apple Pencil" setting
    case draw
    case navigate         // scroll and select; only Pencil draws
}                         // (verify) maps to PaperMarkupViewController.TouchMode

public struct PaperAdornment: Hashable, Sendable { }      // (verify) shape follows MarkupAdornment
```

---

## 5. Behavior specifications

### 5.1 Content modes

The page has a fixed size. The view is whatever SwiftUI offers. The content mode picks the resting scale:

| Mode | Resting scale | Overflow |
|---|---|---|
| `.fit` | min(viewW / pageW, viewH / pageH) | None; letterboxed |
| `.fill` | max(viewW / pageW, viewH / pageH) | Whichever axis the page is relatively longer in |
| `.fitWidth` | viewW / pageW | Vertical |
| `.fitHeight` | viewH / pageH | Horizontal |

- The anchor (`UnitPoint`) sets the initial scroll position in overflowing modes, and where letterbox space goes in `.fit`.
- On rotation or resize, the resting scale is recomputed and the anchor re-applied, unless the user has scrolled or zoomed. In that case the same page point stays in view and relative zoom is kept.
- `zoomScale` and `paperZoomRange` are relative to the resting scale.

### 5.2 Layers

| Operation | Result | Implementation |
|---|---|---|
| `flatten()` | `locked = locked + markup`, `markup = empty` | `locked.append(markup)`, then a new empty `Markup` of the same size |
| `unlock()` | `markup = locked + markup`, `locked = empty` | Start from `locked`, append `markup` so current ink stays on top |
| `archive()` | `background = .pdfPage(searchable PDF of all layers)`, both markups empty | See 5.3 |

- Flattening is lossless and repeatable. Strokes keep vector form and IDs, and stay searchable as `.locked`.
- Paper color: after `flatten()` or `unlock()`, the top layer's color wins if set.
- All three layers share one size. `size`, `rotate`, and `resize` apply to every layer.

### 5.3 Archive and PDF output

`pdfData()`, `archive()`, `archived()`, and the PDF `Transferable` representation all produce the same PDF:

1. Recognize text in `markup` and `locked` with positions (Section 5.6).
2. Render background, then `locked`, then `markup` into a PDF context sized to the paper.
3. Write the recognized text as an invisible text layer at the matching positions.

`archive()` stores that PDF as the background and empties both markups. The page looks identical and stays searchable through PDFKit as `.background`, but stroke IDs and editing are gone. An image background is embedded in the PDF.

### 5.4 Saving

```swift
let data  = try await paper.dataRepresentation()
let paper = try Paper(dataRepresentation: data)
```

- **Format:** a versioned binary property list holding a format version, the two `PaperMarkup` blobs exactly as Apple produced them, and the background bytes.
- **Async save, sync load,** mirroring `PaperMarkup`.
- **`Codable`** writes the most recent background-refreshed snapshot, which can trail the newest stroke briefly. Use `dataRepresentation()` when freshness matters.
- **SwiftData:** store as `Data` with `@Attribute(.externalStorage)`.

| Format | Use | Editable afterward |
|---|---|---|
| `dataRepresentation()` | Saving work | Yes |
| `pdfData()` | Sending, printing, viewing anywhere | No |
| `archived()` | A sealed `Paper` that can still be shown with `PaperView` | No |

### 5.5 Rendering

- `image(scale:)`: `scale` is relative to the paper size in points (`1.0` on letter gives 612 × 792 px).
- `image(fitting:)`: the largest image with the page's aspect ratio that fits the box.
- `Paper` rendering includes all layers. `Markup` rendering draws only the markup, onto the paper color.
- Built on `PaperMarkup.draw(in:frame:options:) async`.

### 5.6 Text recognition

| Source | Provider |
|---|---|
| `.handwriting` | `PKStrokeRecognizer` (iOS 27, on device, 29 languages), fed by stroke ID |
| `.typed` | Text box contents from `subelements` **(verify)** |
| `.locked` | Same two providers applied to `locked` |
| `.background` | PDFKit text layer for text-based PDFs; Vision `RecognizeTextRequest` for scanned pages and images |

- Background text is cached per `Paper`, keyed on the background bytes.
- Handwriting recognition is incremental: after each stroke, only changed stroke IDs are re-recognized.
- Higher-level AI (summaries, questions) is the app's job, for example by passing `recognizedText()` to Foundation Models.

### 5.7 Rotation and resizing

- `rotate(_:)`: `transformContent` with a 90° multiple plus a translation back into positive coordinates, then width and height swap. Lossless. PDF backgrounds get their page rotation attribute updated, and image backgrounds are rotated by whole pixels and re-encoded as PNG.
- `resize(to:scalingContent:)`: `false` extends or crops from the bottom-right corner, and `true` scales content with `transformContent`.

---

## 6. Internals

### 6.1 Package

```
Sources/
└─ PaperUI/      The whole library, one module: value types, PaperKit wrapping, rendering,
                 recognition, file format, SwiftUI views, modifiers, coordinator
Tests/
└─ PaperUITests/ Swift Testing, with fixtures (Paper.sample, Paper.samplePDF)
Demo/            iPad app exercising every public API
```

One module, imported as `import PaperUI`. Splitting off a framework-free value-type module was considered and dropped: no planned use needs the types without PaperKit.

### 6.2 `Markup` internals

- Stores a live `PaperMarkup` (the single source of truth), a `token: UUID` regenerated on every mutation, a serialized snapshot for `Codable`, and a projection cache.
- `paperSize` reads and writes `PaperMarkup.bounds`. If bounds are read-only **(verify)**, the setter builds a new `PaperMarkup(bounds:)` and appends the old content.
- `==` returns true at once if tokens match, and otherwise falls back to `PaperMarkup`'s own `Equatable`. `hash(into:)` uses `paperSize` only, which is consistent with `==`.
- The projection cache (`elements`, `strokes`) is a `final class` guarded by a `Mutex`, replaced on mutation (copy-on-write), so the struct stays `Sendable`.

### 6.3 Coordinator (private)

- Observes `PaperMarkupViewController` with Swift Observation (it is `Observable`), and uses the delegate only where Observation can't help.
- **Loop prevention:** it records the last token pushed to the controller and the last received from it. `updateUIViewController` writes markup into the controller only when the binding's token matches neither.
- **Coalescing:** the binding updates once per stroke end, not per touch sample. The `Codable` snapshot refreshes in the background afterward.
- Owns one `PKToolPicker` per window, shared by editors in that window.
- Applies borrowed environment values (Section 3.4) and content-mode math (Section 5.1) on every layout change.
- Feeds `PKStrokeRecognizer` with changed stroke IDs.

### 6.4 Our API to PaperKit

| Ours | PaperKit / PencilKit |
|---|---|
| `Markup` | `PaperMarkup` |
| `Markup.paperSize`, `.paperColor`, `.contentBounds`, `.indexableContent` | `bounds`, `backgroundColor`, `contentsRenderFrame`, `indexableContent` |
| `insertShape` / `insertLine` / `insertText` / `insertImage` | `insertNewShape` / `insertNewLine` / `insertNewTextbox` / `insertNewImage` |
| `append(_:)`, `rotate`, `resize(scalingContent: true)` | `append(contentsOf: PaperMarkup)`, `transformContent(_:)` |
| `elements`, `remove(_:)` | `subelements: MarkupOrderedSet` |
| `erase(along:width:)`, `PaperStroke.path` | iOS 27 `PKStrokePath` erase and Bézier conversion |
| `dataRepresentation()`, `init(dataRepresentation:)` | same names on `PaperMarkup` |
| `image`, `pdfData` | `draw(in:frame:options:)` |
| `PaperEditor` | `PaperMarkupViewController` (+ `contentView`) |
| `.paperTool`, `.paperToolPicker`, `.paperToolPickerAccessory` | `drawingTool`, `PKToolPicker` (custom items, accessory), `MarkupToolbarViewController` on macOS |
| `.paperSelection`, `onPaperSelectionChange` | `selection`, `selectedMarkup` |
| `.paperScrollPosition`, `.paperContentMode`, `.paperZoomRange`, `onPaperGeometryChange` | `setContentVisibleFrame(_:animated:)`, `contentVisibleFrame`, `zoomRange`, `scrollConfiguration` |
| `.paperInput` | `directTouchMode`, `directTouchAutomaticallyDraws`, `indirectPointerTouchMode` |
| `.paperRulerActive`, `.disabled` | `isRulerActive`, `isEditable` |
| `.paperFeatures` | `supportedFeatureSet: FeatureSet` |
| `.paperInsertionMenu` | `MarkupEditViewController` |
| `.paperAdornments` | `adornments`, `adornmentFrame(for:)` |
| `\.undoManager` | `undoManager` |
| `recognizedText`, `search` | `PKStrokeRecognizer`, `indexableContent`, PDFKit, Vision |

---

## 7. Coverage: is all of PaperKit wrapped?

**Yes, for everything Apple documents, apart from the intentional backward-compatibility exclusions.** Every documented `PaperMarkup` member and every documented `PaperMarkupViewController` capability in Section 6.4 has a SwiftUI path. The remaining gaps come from places where Apple's documentation is silent or thin, not from design choices:

| Area | Status | Why |
|---|---|---|
| Adornments | Placeholder API | `MarkupAdornment` is barely documented. `PaperAdornment` takes its shape once the SDK header is read |
| Element details | Shallow | `MarkupOrderedSet` element types aren't documented, so `PaperElement` exposes kind and frame only. Richer reading (text box contents, shape style) grows with what the SDK reveals |
| Removing content | Provisional | `PaperMarkup` documents insert, append, and transform, but no remove. Depends on whether `subelements` is mutable |
| Setting the selection | Provisional | `selection` is documented, but not whether it is settable. Otherwise read-only via `onPaperSelectionChange` |
| Delegate events | Partial | The `Delegate` protocol's methods aren't listed. Only drawing-began is wrapped. Others are added as found |
| `ScrollConfiguration` | Partial | Its members aren't documented beyond scroll indicators |
| `FeatureSet` granularity | Partial | `PaperFeatures.Feature` mirrors whatever features the SDK enumerates |
| `RenderingOptions` for `draw` | Internal only | Used internally for rendering; not exposed until a need appears |
| iOS 27 PencilKit extras | Not wrapped | Substroke ranges, `renderGroupID`, recognizer language preferences. Niche; added on request |

**Excluded by choice:** `append(contentsOf: PKDrawing)` import, `removeContentUnsupported(by:)`, versioned feature sets, and OS versions before 27.

**Beyond PaperKit:** the package adds things PaperKit doesn't have: `Paper` layers, flatten, unlock, and archive, embedded backgrounds, searchable PDF output, background OCR, content modes, and value-type tools that are `Codable`.

---

## 8. Build plan

**No separate spike phase.** Every **(verify)** item sits behind an API whose fallback is already designed, so none of them can force a redesign before building starts. Each is resolved as the first task of the phase that uses it, and anything else surfaces as a bug to fix.

### Phase 1: A working editor (MVP)

Goal: draw on an iPad, save, and reload.

- Package skeleton: one library target and one test target.
- Value types: tools, colors, sizes, content modes, geometry.
- `Markup`: live `PaperMarkup`, token, `paperSize`, `paperColor`, `dataRepresentation`, `Codable` snapshot.
- `PaperEditor(markup:)` with `.paperTool`, `.paperToolPicker(isPresented:)`, `.paperFeatures`, `.paperContentMode`, `.paperZoomRange`, `.disabled`, `\.undoManager`.
- Coordinator loop prevention and coalescing.
- First tests: stroke ID round-trip through `dataRepresentation`, `bounds` setter behavior, content modes through rotation.

**Done when** a demo app draws, rotates the device without moving strokes, saves, relaunches, and restores.

### Phase 2: Paper, backgrounds, and output

- `Paper` with three layers, `PaperBackground`, `PaperEditor(paper:)`, the `on:` initializers, `PDFPageView`.
- `flatten()`, `unlock()`, `rotate`, `resize`, `append`.
- `PaperView`, `image(scale:)`, `image(fitting:)`, `pdfData()` (without the text layer for now), `Transferable`, the `.swiftPaper` file format.
- First tasks: does `contentView` follow zoom? Does `append(contentsOf:)` keep IDs? Is PDF output vector?

**Done when** a PDF worksheet can be filled in, flattened, rotated, thumbnailed, and shared as a PDF.

### Phase 3: Interaction

- `.paperSelection` (or `onPaperSelectionChange` alone if read-only), `.paperScrollPosition`, `onPaperGeometryChange`, `onPaperDrawingBegan`.
- Insert methods, `remove`, `erase(along:width:)`, `PaperShape` and `PaperShapeStyle`.
- `.paperInput`, `.paperRulerActive`, tool picker items, custom tools, accessory, `.paperInsertionMenu`.
- Borrowed environment (Section 3.4), `elements`, `strokes`, `PaperStroke.path`.

**Done when** every modifier in Section 3 works in the demo.

### Phase 4: Text and archive

- `recognizedText(_:)` and `search(_:in:)` across all four sources, `PaperTextMatch`, `scrollTo(match:)`.
- Searchable text layer in `pdfData()`, then `archive()` and `archived()`.
- Default accessibility labels.

**Done when** a scanned PDF with handwriting can be searched, a match revealed, and the page archived and still searched.

### Later, when needed

macOS and visionOS polish, a pure-SwiftUI tool palette, adornments, arbitrary SwiftUI backgrounds in the editor, view-only rotation, and the iOS 27 PencilKit extras from Section 7.
