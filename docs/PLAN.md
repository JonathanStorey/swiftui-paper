# SwiftUI Paper: Plan for a SwiftUI Port of PaperKit

**Status:** v1.18, Option E locked in, review fixes applied (see [REVIEW.md](REVIEW.md)), docs findings in Section 9.1 · **Date:** 2026-10-31

## 1. Goal

PaperKit is Apple's current home for Apple Pencil markup. It layers shapes, text, images, and an insertion menu on top of PencilKit ink, and it ships as UIKit/AppKit view controllers (`PaperMarkupViewController`, `MarkupEditViewController`, `MarkupToolbarViewController`) plus the `PaperMarkup` data model and `FeatureSet` configuration.

This project wraps all of that in an API that feels like it shipped in SwiftUI itself:

1. A single editor view that binds to a markup value the way `TextEditor` binds to a `String`.
2. Pure-Swift, `Codable`, `Hashable`, `Sendable` value types for tools, inks, colors, paper sizes, and strokes.
3. Strokes with stable identity (`Identifiable`) built on the new stroke IDs.
4. A module layout that keeps the portable model independent of UIKit and PaperKit so it can grow without rewrites.

**Scope.** The package stops at a single sheet of paper. `PaperEditor`, `PaperView`, and the `Paper` and `Markup` values they work with are the deliverable. Files, multi-page documents, and app metadata belong to the app that uses the package.

> **Verify against the SDK.** Type names below that start with `PK` or `Paper` and are not ours (`PaperMarkup`, `FeatureSet`, `PKInkingTool`, `PKStroke`) refer to Apple's frameworks. Signatures confirmed from Apple's documentation are marked in Section 9.1. The rest must be checked against the SDK headers in Phase 0. The architecture does not depend on any single member name.

---

## 2. The design question

PaperKit's surface splits into five kinds of state. The right packaging falls out of sorting them correctly.

| Kind | Examples | Direction | SwiftUI precedent |
|---|---|---|---|
| **Markup** | the canvas content | two-way | `TextEditor(text:)` |
| **Configuration** | feature set, enabled, ruler, finger-draws policy, background content | down only | `.textFieldStyle`, `.disabled`, `.scrollDisabled` |
| **Interaction state** | current tool, selection, tool picker visibility | two-way | `@FocusState` + `.focused`, `.sheet(isPresented:)` |
| **Layout and geometry** | how the page sits in the view, zoom scale, visible rect | down (content mode), up (geometry) | `Image` content modes, `.onScrollGeometryChange` |
| **Commands** | undo, insert shape, present insertion menu | one-shot | `UndoManager` in environment, `.popover(isPresented:)` |

Every option below is judged by how cleanly it handles all five rows.

---

## 3. Options

### Option A: Environment modifiers only

```swift
PaperEditor(markup: $markup)
    .paperTool(.pen(.black, width: 3))
    .paperFeatures(.latest)
    .paperRulerActive(true)
```

Each modifier writes an `EnvironmentValues` key. The representable reads them in `updateUIViewController` and applies diffs.

**Strengths.** Maximally idiomatic for configuration. Modifiers compose, inherit down the tree, and can be applied to a container holding several editors.

**Weaknesses.** The environment only flows down. It cannot tell you that the user picked a pencil from the tool picker, changed the selection, or zoomed. Commands have no natural home. Pushed to its limit this option becomes 30 modifiers with no way to read anything back.

**Verdict.** Correct for the configuration row. Wrong as the whole answer.

### Option B: A context object (`PaperContext`) in the environment

```swift
@State private var paper = PaperContext()

PaperEditor()
    .environment(paper)

// anywhere below
@Environment(PaperContext.self) var paper
paper.tool = .pencil(.blue)
paper.undo()
paper.insert(.shape(.rectangle))
```

An `@Observable` class owns the markup, tool, selection, zoom, and exposes command methods. This is the "coordinator in the environment" model.

**Strengths.** Two-way state and commands in one place. Easy to reach from a custom toolbar deep in the tree. Familiar to anyone who has written a view model.

**Weaknesses.**
- It hides ownership. The markup lives inside a reference type instead of in your own `@State` or `@Model`, so saving, undo integration, and previews become harder.
- It is a god object. Configuration that should be inherited declaratively becomes imperative mutation.
- It runs against the direction SwiftUI has moved. Apple keeps replacing proxies and reference handles with plain values and bindings: `ScrollViewReader`'s proxy gave way to a scroll-position value, and `@Observable` models are meant to be owned by the app, not handed out by a framework.
- Multiple editors on screen require multiple contexts and careful scoping.

**Verdict.** The coordinator should exist, but as a private implementation detail inside the representable, not as the public API.

### Option C: A custom property wrapper (`@PaperState`)

```swift
@PaperState private var paper   // DynamicProperty that owns a hidden coordinator

PaperEditor(paper: $paper)
```

**Strengths.** Can manage lifetime of non-value resources (for example a retained `PKToolPicker`) the way `@FocusState` and `@Namespace` manage engine-owned state.

**Weaknesses.** A custom `DynamicProperty` cannot participate in the engine the way `@FocusState` does. Underneath it is `@State` holding a reference, which is Option B with extra syntax. It also confuses readers about who owns the markup.

**Verdict.** No public custom property wrapper in v1. The legitimate need (owning the tool picker) is handled privately inside the representable's coordinator. Revisit only if a real lifetime problem appears that `@State` cannot solve.

### Option D: Reader/proxy for commands (`PaperReader`)

```swift
PaperReader { proxy in
    PaperEditor(markup: $markup)
    Button("Undo") { proxy.undo() }
}
```

Mirrors `ScrollViewReader`. Solves commands only, and copies a pattern Apple has already moved away from.

**Verdict.** Skip. Commands belong on value types and in standard environment values (see Section 4).

### Option E (recommended): Hybrid that mirrors existing SwiftUI

Sort each row to the SwiftUI pattern Apple already uses for it:

- **Markup:** a value binding, like `TextEditor`.
- **Configuration:** environment modifiers, like `.textFieldStyle`, and SwiftUI's own `.disabled` where one already exists.
- **Interaction state:** small value types and `isPresented` bindings, like `@FocusState` and `.sheet`.
- **Layout and geometry:** the editor fills its space like a resizable `Image`, a content mode places the page inside it, and a change callback reports zoom, like `.onScrollGeometryChange`.
- **Commands:** mutating methods on the markup, the standard `undoManager` environment value, and `isPresented` bindings.

The full API is in Section 4.

---

## 4. Recommended API

### 4.1 The editor

```swift
struct SketchView: View {
    @State private var paper = Paper(size: .letter)
    @State private var tool: PaperTool = .pen(.black, width: 3)
    @State private var selection = PaperSelection()
    @State private var showToolPicker = true
    @State private var showInsertMenu = false

    var body: some View {
        PaperEditor(paper: $paper)
            .paperTool($tool)                          // two-way: tool picker writes back
            .paperSelection($selection)                // two-way, like .focused($field)
            .paperContentMode(.fitWidth, anchor: .top) // like an Image content mode
            .paperFeatures(.latest)                    // config, down only
            .paperToolPicker(isPresented: $showToolPicker)
            .paperInsertionMenu(isPresented: $showInsertMenu)
            .disabled(isLocked)                        // SwiftUI's own modifier
            .toolbar {
                Button("Insert", systemImage: "plus") { showInsertMenu = true }
            }
    }
}
```

Why this shape wins:

- **The paper is yours.** It lives in `@State`, a SwiftData `@Model`, or wherever your app keeps data. Saving, previews, and tests touch a plain value.
- **Each two-way piece is optional.** If you don't care about selection, don't bind it. `TextField` works the same way with `.focused`.
- **Tools are values.** A custom SwiftUI palette and the system `PKToolPicker` can drive the same `@State var tool` at once, which makes a native SwiftUI toolbar a later add-on instead of a rewrite.
- **No redundant modifiers.** Editing on/off reads `\.isEnabled`, so `.disabled(true)` on the editor, or on any container above it, just works.
- **Commands are value mutations.** `paper.markup.insertShape(.rectangle, style: .outline, in: rect)` mirrors appending to a string.

**Two layers: `Paper` and `Markup`.** The test for what belongs together is "what does it take to draw this page correctly?" Size, background, and ink pass. Titles, page lists, and files do not. So the package has two value layers, and no document format:

| Type | Holds | Use it when |
|---|---|---|
| `Paper` | `markup` + `background` | Most apps. One self-contained sheet: save it, share it, thumbnail it, with nothing else needed |
| `Markup` | Ink, elements, paper size, paper color | Apps that manage backgrounds themselves, such as a 300-page annotated PDF that shouldn't copy each page into every sheet |

Both layers work with every view: `PaperEditor(paper:)` or `PaperEditor(markup:on:)`, and `PaperView(paper)` or `PaperView(markup, on:)`. Types are in Section 5.6.

**Background content.** PaperKit's mechanism is `PaperMarkupViewController.contentView`, documented as "the content that markup appears on top of" and settable to any `UIView`/`NSView`. Apple's WWDC25 sample uses a `UIImageView` holding a template. Our API exposes it through initializers, following SwiftUI's pattern of one generic builder initializer plus convenience initializers for common cases (like `Label(_:systemImage:)` beside `Label { } icon: { }`):

```swift
public struct PaperEditor<Background: View>: View {
    // General form: any SwiftUI view as the paper's background
    public init(markup: Binding<Markup>, @ViewBuilder on background: () -> Background)
}

extension PaperEditor where Background == PaperBackgroundView {
    public init(paper: Binding<Paper>)                          // background comes from the Paper
}

extension PaperEditor where Background == EmptyView {
    public init(markup: Binding<Markup>)                        // plain paper
}
extension PaperEditor where Background == Image {
    public init(markup: Binding<Markup>, on image: Image)       // template image
}
extension PaperEditor where Background == PDFPageView {
    public init(markup: Binding<Markup>, on page: PDFPage)      // one PDF page
}
```

```swift
PaperEditor(paper: $paper)                                   // the usual form
PaperEditor(markup: $markup)
PaperEditor(markup: $markup, on: Image("worksheet"))
PaperEditor(markup: $markup, on: pdf.page(at: 0)!)
PaperEditor(markup: $markup) { GridPattern(spacing: 20) }
```

Design notes:
- **The PDF initializer takes a `PDFPage`, not a `PDFDocument`.** A markup is one page, so the type says which page. Multi-page documents are the app's job (one `Markup` per page).
- **Labels stay `on:` for every form.** The argument type picks the overload, so the call reads "editor for this markup, on this page," and the trailing-closure form drops the label as SwiftUI builders do.
- **The background is laid out in the page's frame.** Whatever view is passed is sized to `markup.paperSize`, so an image stretches to the page like a `.resizable()` image in a fixed frame, and a PDF page fills it exactly.
- **Every form ends in `contentView`.** Internally the background becomes one `UIView` assigned to `PaperMarkupViewController.contentView`, framed to the page rect:
  - *View builder and `Image`:* the SwiftUI view is placed in a `UIHostingController`, and its view becomes `contentView`. (A SwiftUI `Image` can't be turned back into a `UIImage`, so it is hosted like any other view. Hosting a single image is cheap.)
  - *`PDFPage`:* skips SwiftUI entirely. The bridge assigns a native `CATiledLayer`-backed view that draws the page with PDFKit, because tiled drawing is what keeps vector content sharp as the user zooms. `PDFPageView` is just the SwiftUI face of that same view for use elsewhere.
  - *Zoom sharpness:* hosted and image backgrounds are limited by their resolution, as in Apple's `UIImageView` sample. Only the PDF path re-renders at every zoom level.
- **Initializers take only what the editor *is*: the markup and the paper it sits on.** Everything about *how* it behaves (tool, selection, features, content mode, zoom) stays a modifier, as with `TextEditor(text:)` plus `.font`, `.disabled`, and `.focused`. That includes the feature set even though `PaperMarkupViewController`'s initializer requires one: its `supportedFeatureSet` is a settable property, so `.paperFeatures` defaults to `.latest` and updates it.
- **Placeholders use the markup, not an init parameter.** `Markup.isEmpty` lets apps write `.overlay { if markup.isEmpty { Text("Draw here") } }` with no extra API.
- **Display-only is a different view.** Like `Text` beside `TextEditor`, a read-only `PaperView(markup)` takes a plain value instead of a binding. It is also how thumbnails are made (Section 4.7).
- **Initializers never resize the markup.** Writing to a binding from `init` is not allowed in SwiftUI. Matching sizes is done when the markup is created: `Markup(paperSize: PaperSize(page))` reads the PDF page's media box in points.

Rules:
- **Where the background lives depends on the layer.** With `Paper`, it is stored alongside the markup and travels with it. With the `Markup` forms, it is a view the app supplies and persists however it likes, the way a PDF viewer keeps the PDF separate from annotations. Either way it is never inside Apple's blob. Use `insertNewImage` only when the image should be a movable, selectable element.
- **PDF fits our units exactly.** PDF pages are measured in points, so `Paper(pdfPage: page)` sizes the markup to the page's media box and the two line up one to one with no scaling math.
- **`PDFPageView`** (public, usable on its own) is a small SwiftUI wrapper around a tiled `UIView` that draws a `PDFPage` with PDFKit, so it stays crisp when zoomed instead of blurring like a pre-rendered image.
- **Export flattens both.** `paper.image(scale:)` and `paper.pdfData()` draw the background, then the markup, matching Apple's thumbnail sample, which fills the context before calling `draw`.
- **Plain paper color** stays on the markup (`PaperMarkup.backgroundColor`), because it is content.

Open questions for Phase 0: does `contentView` scale and scroll with the markup automatically, and does a `UIHostingController` view work there? Phase 3 ships `Image` and `PDFPageView` first, then arbitrary SwiftUI content.

### 4.2 Configuration modifiers (environment)

Keep the list short and group by concern. Each is a plain `EnvironmentValues` entry, so it inherits.

| Modifier | Maps to |
|---|---|
| `.disabled(_ :)` (SwiftUI's own) | editable flag, read from `\.isEnabled` |
| `.paperFeatures(_ :PaperFeatures)` | `FeatureSet` (`.latest`, `.version(_)`, insert/remove features, HDR headroom) |
| `.paperRulerActive(_ :)` | ruler |
| `.paperInput(direct:pointer:)` | finger and trackpad/mouse behavior (Section 4.9) |
| `.paperContentMode(_ :anchor:)` | how the page sits in the view at rest: `PaperContentMode` plus a `UnitPoint` anchor (default `.center`) |
| `.paperZoomRange(_ :)` | min/max zoom, relative to the content mode's resting scale |

**Borrowed SwiftUI environment.** Before adding a `paper*` modifier, check whether SwiftUI already has one. These existing modifiers and environment values are honored by the editor, so they work on the editor or any container above it:

| SwiftUI API | What the editor does with it |
|---|---|
| `.disabled` / `\.isEnabled` | Read-only canvas (editable flag) |
| `.scrollDisabled` / `\.isScrollEnabled` | Locks pan and zoom at the resting position, for fixed worksheets and signature boxes |
| `.scrollIndicators` / `\.horizontalScrollIndicatorVisibility`, `\.verticalScrollIndicatorVisibility` | Scroll indicator visibility through `scrollConfiguration`, replacing the deprecated `shows…ScrollIndicator` properties |
| `.focused($isFocused)` | First responder, so keyboard shortcuts, the Edit menu (cut, copy, paste, select all), and hardware undo reach the canvas. Like `@FocusState` on a `TextEditor` |
| `.onPencilDoubleTap`, `.onPencilSqueeze`, `\.preferredPencilDoubleTapAction` | Not reimplemented. When the system tool picker is hidden, apps use SwiftUI's own Pencil gestures to change the `tool` binding. When it is visible, the picker handles them |
| `\.undoManager` | Undo (Section 4.5) |
| `\.layoutDirection` | `.leading`/`.trailing` anchors flip in right-to-left languages, as they do everywhere else in SwiftUI |
| `\.accessibilityReduceMotion` | Programmatic visible-frame changes (re-anchoring on rotation) skip animation |
| `\.displayScale` | `PaperView` renders at the screen's scale |

Deliberately not borrowed: `\.editMode` (overlaps `.disabled` with list-specific meaning), `.tint` (PaperKit does not expose a selection accent color), and `.backgroundStyle` (the paper color is stored in `PaperMarkup.backgroundColor`, so it is content, not environment).

`PaperFeatures` is our own `Hashable`, `Sendable` struct with static members (`.latest`, `.basic`) and modifiers (`.removing(.stickers)`), translated to `FeatureSet` in the bridge.

### 4.3 Interaction state

```swift
.paperTool($tool)                          // PaperTool, see 5.2
.paperSelection($selection)                // PaperSelection
.paperToolPicker(isPresented: $show)       // user can dismiss it, so it is a binding
.paperInsertionMenu(isPresented: $show)

public struct PaperSelection: Hashable, Sendable {
    public var ids: Set<PaperElement.ID>     // mirrors PaperKit's Set<MarkupOrderedSet.ElementID>
    public var isEmpty: Bool { ids.isEmpty }
    public mutating func clear()
}
```

**Selection direction depends on PaperKit.** `PaperMarkupViewController.selection` is a `Set<MarkupOrderedSet.ElementID>` covering strokes and elements alike, which is why `PaperSelection` holds one set. The docs do not say whether it is settable (PencilKit's own canvas selection became settable in iOS 27). Phase 0 checks this. If it is report-only, v1 ships `onPaperSelectionChange { selection in }` instead of a binding, and the binding arrives when the framework allows it. Shipping a binding that silently ignores writes would be worse than shipping no binding.

### 4.4 Layout, zoom, and geometry

**The editor fills the space it is offered.** `PaperEditor` is greedy, like `Color`, `ScrollView`, or a `.resizable()` image. Constrain it with the modifiers you already use, such as `.frame` and `.padding`. No `.aspectRatio` is needed: the page's shape comes from the markup and its placement from `.paperContentMode`. If someone applies `.aspectRatio` anyway, it behaves correctly, because the representable implements `sizeThatFits` and reports the page size as its ideal size.

**The page has a fixed size, the view does not.** Paper size is content, not layout, the same way an image's pixel size is. If it followed the view, rotating an iPad would resize the canvas and every stroke would land in the wrong place. Paper size lives on the markup (see 5.4).

**Content mode maps page to view.** This is the `Image` model applied to paper. We define our own `PaperContentMode` because SwiftUI's two-case `ContentMode` cannot express the notes-app layout, and adding cases later would be a breaking change.

```swift
public enum PaperContentMode: Hashable, Sendable {
    case fit        // whole page visible, letterboxed
    case fill       // page covers the view, overflow scrolls on whichever axis
    case fitWidth   // page matches the view's width, scrolls vertically
    case fitHeight  // page matches the view's height, scrolls horizontally
}
```

The four cases relate cleanly: `.fit` is the smaller of `.fitWidth` and `.fitHeight`, and `.fill` is the larger.

| Mode | At rest | Feels like |
|---|---|---|
| `.fit` (default) | Whole page visible, letterboxed | A sheet on a desk |
| `.fill` | Page covers the view, overflow on either axis | A whiteboard |
| `.fitWidth` | Width matches, scrolls down | A notes app |
| `.fitHeight` | Height matches, scrolls sideways | A timeline or storyboard |

With `.fill`, the overflow axis falls out of the two shapes. Compare the page's width÷height to the view's: if the page is relatively wider, it overflows horizontally; if relatively taller, vertically. A worked example with an 8.5 × 10 page (ratio 0.85) on an iPad:

| Orientation | View ratio | Page vs view | `.fill` scrolls |
|---|---|---|---|
| Portrait | ≈ 0.75 | page is wider | horizontally, slightly |
| Landscape | ≈ 1.33 | page is taller | vertically, a lot |

That is often the reverse of what people expect. Apps that want "match the width, always scroll down" should use `.fitWidth`.

**The anchor picks where the page sits at rest.** It is a plain `UnitPoint`, the same type `.defaultScrollAnchor` and `scaleEffect(anchor:)` use.

```swift
.paperContentMode(.fitWidth, anchor: .top)   // notes: start at the top
.paperContentMode(.fill, anchor: .leading)   // start at the left edge if it overflows sideways
.paperContentMode(.fit, anchor: .top)        // letterboxed page pinned to the top
```

In scrolling modes the anchor sets the initial scroll position. In `.fit` it decides where the letterbox space goes, just like `.frame(alignment:)` positions an `Image`. On rotation or resize the editor recomputes the resting scale and re-applies the anchor, unless the user has already scrolled or zoomed, in which case it keeps the same canvas point in view.

**Zoom is relative to the resting scale.** `zoomScale == 1` always means "at the content mode's resting size," on any device or orientation. That makes `.paperZoomRange(1...4)` portable and keeps app code free of point math.

```swift
PaperEditor(markup: $markup)
    .paperContentMode(.fitWidth, anchor: .top)
    .paperZoomRange(1...4)
    .onPaperGeometryChange(for: Bool.self) {     // read-back, like .onScrollGeometryChange
        $0.zoomScale > 1
    } action: { _, isZoomedIn in
        showsResetButton = isZoomedIn
    }

public struct PaperGeometry: Equatable, Sendable {
    public var zoomScale: CGFloat      // 1 == resting scale for the content mode
    public var visibleRect: CGRect     // in page coordinates
    public var contentSize: CGSize
}
```

The transform closure means the action fires only when the value you care about changes, not on every pinch frame.

Programmatic scrolling and zooming (reveal a search match, zoom to the selection) use `.paperScrollPosition` (Section 4.9). Search results made this a real need.

**Built on documented API.** `PaperMarkupViewController` exposes `zoomRange`, `contentVisibleFrame`, `setContentVisibleFrame(_:animated:)`, and a `scrollConfiguration`. Content modes and anchors become arithmetic: compute the page rect that should be visible at rest and call `setContentVisibleFrame`. `PaperGeometry.visibleRect` reads `contentVisibleFrame`. Phase 0 confirms the behavior through rotation; hosting our own `UIScrollView` stays as an unlikely fallback.

### 4.5 Undo

The editor uses the view controller's own `undoManager` (documented on `PaperMarkupViewController`) and exposes it through SwiftUI's `\.undoManager`, so an Undo button calls `undoManager?.undo()` as it would for a text view. One honest limit: changes the app writes into the `markup` binding (loading, sync, programmatic inserts) bypass the drawing undo stack. They are undoable only if the app registers them itself.

### 4.6 Events

Use the SwiftUI `onChange`/callback idiom rather than a delegate:

```swift
.onPaperDrawingBegan { ... }
.onChange(of: markup) { save() }   // works because Markup is Equatable
```

### 4.7 Rendering: thumbnails, previews, and export

Apple provides one rendering primitive: `PaperMarkup.draw(in: CGContext, frame:, options:) async`. Apple's own thumbnail sample creates a bitmap context, fills it white, and awaits `draw`. Everything here is built on that one call. The choice of `CGContext` decides the output format.

**Data API on `Paper`.** Because the paper already knows its size, the main control is a scale, like `ImageRenderer.scale`:

```swift
let thumb = try await paper.image(scale: 0.25)                          // quarter of paper size
let cell  = try await paper.image(fitting: CGSize(width: 120, height: 120))  // fixed grid cell
let pdf   = try await paper.pdfData()                                   // true paper size
```

- **`scale` is a `Double` relative to the paper size in points.** `1.0` on a letter page gives 612 × 792 pixels. For a sharp on-screen image, multiply by the screen's scale, which `PaperView` does automatically.
- **`fitting:`** returns the largest image with the page's aspect ratio that fits the box, for grids with fixed cells.
- **Background is always included,** because `Paper` carries it. That is the main reason `Paper` exists.
- `Markup` has the same three functions without a background, for apps on the lower layer, which draw their own background into the context first.

| Output | How it's made | Use it for |
|---|---|---|
| `CGImage` | Bitmap context | Thumbnails, lists, widgets. Convert with `Image(decorative:scale:)`, `UIImage(cgImage:)`, or encode PNG/JPEG/HEIC with ImageIO |
| PDF `Data` | PDF context sized to the paper | Print and share at true paper size. A PDF background stays vector, and ink should too if PaperKit draws vector into a PDF context (Phase 0 check) |

`CGImage` is the core format, not `UIImage`, so the API works the same on iOS and macOS and stays `Sendable`.

**`Transferable`.** `Paper` exports as its own data type plus PNG and PDF representations, so `ShareLink(item: paper, preview: ...)` and drag-and-drop work with no extra code.

**One read-only view: `PaperView`.** Rather than separate `PaperView` and `PaperThumbnail` types, there is one. A thumbnail is just a small `PaperView`.

```swift
PaperView(paper)                       // the usual form
PaperView(markup, on: pdfPage)         // lower layer, same "on:" forms as PaperEditor
    .frame(width: 120)                 // size it like any view; it keeps the page's aspect ratio
```

- **Renders a bitmap at its laid-out size** times `\.displayScale`, so a 120 pt thumbnail costs a 120 pt render, and a full-screen preview renders at full size.
- **Async like `AsyncImage`.** Shows a placeholder (the paper color) until the render finishes. Rendering runs in `.task(id:)` keyed on the paper's content and size, so it re-renders only when the content or size actually changes.
- **Cached by token.** Scrolling a grid of thumbnails back and forth doesn't re-render unchanged pages.
- **Sizes like `Image`.** Its ideal size is the paper size and it respects `.aspectRatio`, so `.frame(width:)` alone gives a correctly shaped thumbnail.
- **Not zoomable.** A read-only page that zooms is `PaperEditor` with `.disabled(true)`.
- **Not `ImageRenderer`-compatible.** `ImageRenderer` renders synchronously and would capture the placeholder. Use `paper.image(scale:)` instead.

### 4.8 Reading the page: handwriting and background text

Apple's recognition reads **ink and markup only**. It never looks at the background:

- `PaperMarkup.indexableContent: String?` (iOS 26) gives searchable text for the markup, meant for Spotlight-style indexing.
- `PKStrokeRecognizer` (iOS 27, an actor) recognizes handwriting on device in 29 languages: `recognizedText()`, `indexableContent`, `search(_:)` returning matches with bounds, and recognition limited to chosen stroke IDs. Apple states the new PencilKit APIs also work with PaperKit.

Text in the background comes from different frameworks:

| Background | Source of text |
|---|---|
| Text-based PDF | PDFKit: `PDFPage.string` and `PDFSelection` bounds. Exact, instant, no recognition |
| Scanned PDF or photo | Vision on-device OCR (`RecognizeTextRequest`, or `RecognizeDocumentsRequest` for structured documents), run on the page rendered to an image |

Because `Paper` holds both layers, it is the natural place to combine them:

```swift
let all      = try await paper.recognizedText()                    // default: .all
let notes    = try await paper.recognizedText(.handwriting)
let printed  = try await paper.recognizedText([.typed, .background])
let matches  = try await paper.search("invoice", in: .markup)      // same set type as recognizedText
```

The filter follows SwiftUI's `Edge` / `Edge.Set` pattern: a plain enum names one source, and a nested `OptionSet` selects several. One type serves both functions.

```swift
public enum PaperTextSource: Hashable, Sendable {
    case handwriting   // ink, via PKStrokeRecognizer
    case typed         // text boxes in the markup
    case locked        // the Paper's locked middle layer
    case background    // PDF text layer or Vision OCR

    public struct Set: OptionSet, Hashable, Sendable {
        public static let handwriting, typed, locked, background: Set
        public static let markup: Set = [.handwriting, .typed]
        public static let all: Set = [.handwriting, .typed, .locked, .background]
    }
}

public func recognizedText(_ sources: PaperTextSource.Set = .all) async throws -> String
public func search(_ query: String, in sources: PaperTextSource.Set = .all) async throws -> [PaperTextMatch]
```

Why an `OptionSet` rather than a single-choice enum: `.all` and `.markup` are real unions, and apps will want combinations like `[.typed, .background]` (all printed text). With an enum, every useful combination would need its own case. `Markup` has the same two functions, where `.background` simply contributes nothing. Whether typed text can be separated from handwriting depends on reading text boxes out of `subelements` (Phase 0).

- **`PaperTextMatch`** carries the matched text, its rect in page coordinates, and its single `PaperTextSource`, so an app can highlight results over the page or jump to them with `setContentVisibleFrame`.
- **Background recognition is cached** per `Paper` and keyed on the background data, since it only changes when the background does. OCR on a scanned page is the slow path, so it runs once.
- **Ink recognition follows edits.** The coordinator feeds the recognizer after each stroke ends, and stroke IDs let it re-recognize only what changed.
- **Higher-level AI is the app's call.** Summaries, questions, or extraction can pass `recognizedText()` to Apple's Foundation Models framework. The package supplies the text and its locations, not the model.

Phase 3 ships markup recognition. Background text (PDFKit first, Vision OCR second) lands in Phase 4.

### 4.9 Additions from the PaperKit coverage audit

These close the gaps found in Review 2. Importing `PKDrawing` and feature-set compatibility checks were deliberately dropped.

#### Scrolling and zooming from code

Search results and "zoom to selection" need a way to move the view. This follows SwiftUI's `ScrollPosition`: a small value the app holds in `@State`, changes by calling methods, and binds to the editor. `.onPaperGeometryChange` stays for observing; this is for commanding.

```swift
public struct PaperScrollPosition: Hashable, Sendable {
    public init()
    public var visibleRect: CGRect? { get }            // last reported, page coordinates
    public mutating func scrollTo(rect: CGRect, anchor: UnitPoint? = nil, zoom: Bool = true)
    public mutating func scrollTo(match: PaperTextMatch)
    public mutating func scrollTo(selection: PaperSelection)
    public mutating func zoomToFit()                    // back to the content mode's resting state
}

extension View {
    public func paperScrollPosition(_ position: Binding<PaperScrollPosition>) -> some View
}
```

```swift
@State private var position = PaperScrollPosition()

PaperEditor(paper: $paper)
    .paperScrollPosition($position)

Button("Find") { if let hit = matches.first { position.scrollTo(match: hit) } }
```

The editor implements each request with `setContentVisibleFrame(_:animated:)`, animating unless Reduce Motion is on.

#### Inserting elements from code

"Inserting" means adding new shapes, lines, text boxes, or images to the page from code rather than by drawing, such as a Stamp button that places an "Approved" text box, or pasting a signature image. PaperKit already supports this with four methods on `PaperMarkup` (`insertNewShape`, `insertNewLine`, `insertNewTextbox`, `insertNewImage`). We mirror them one to one on `Markup`, with our own value types in place of Apple's:

```swift
extension Markup {
    public mutating func insertShape(_ shape: PaperShape, style: PaperShapeStyle, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertLine(from start: CGPoint, to end: CGPoint, style: PaperShapeStyle, startArrow: Bool = false, endArrow: Bool = false)
    public mutating func insertText(_ text: AttributedString, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertImage(_ image: CGImage, in frame: CGRect, rotation: Angle = .zero)
}

public enum PaperShape: Hashable, Codable, Sendable {
    case rectangle, roundedRectangle, ellipse, triangle, star, speechBubble   // mirrors ShapeConfiguration (verify cases)
}

public struct PaperShapeStyle: Hashable, Codable, Sendable {
    public var stroke: PaperColor?
    public var fill: PaperColor?
    public var lineWidth: CGFloat
    public static let outline: PaperShapeStyle       // black stroke, no fill
    public static func filled(_ color: PaperColor) -> PaperShapeStyle
}
```

```swift
// A Stamp button that drops a text box in the middle of what the user sees
if let visible = position.visibleRect {
    let frame = CGRect(x: visible.midX - 100, y: visible.midY - 25, width: 200, height: 50)
    paper.markup.insertText(AttributedString("APPROVED"), in: frame)
}
```

Four named methods replace the earlier single `insert(_:in:)` with an undefined template. A line has endpoints, not a frame, so one shared signature never fit. All coordinates are page coordinates, and `Angle` comes from SwiftUI's own type.

#### Tool picker configuration

```swift
extension View {
    public func paperToolPicker(isPresented: Binding<Bool>, items: [PaperToolPickerItem] = PaperToolPickerItem.standard) -> some View
    public func paperToolPickerAccessory(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View
}

public enum PaperToolPickerItem: Hashable, Sendable {
    case ink(InkKind)
    case eraser(EraserMode)
    case lasso
    case ruler
    case custom(id: String, name: String, systemImage: String)
    public static let standard: [PaperToolPickerItem]
}

// PaperTool gains one case so the tool binding can report a custom tool
public enum PaperTool { /* existing cases */ case custom(id: String) }
```

When the user picks a custom item, the `tool` binding becomes `.custom(id:)`, and the app decides what that tool does (place a stamp, open a sheet). On macOS the same modifier shows `MarkupToolbarViewController` instead of `PKToolPicker`, the way `.toolbar` adapts per platform, so there is no separate macOS API.

#### Input: finger, trackpad, and mouse

Replaces `.paperTouchPolicy`, which only covered fingers. `PaperMarkupViewController` exposes `directTouchMode`, `directTouchAutomaticallyDraws`, and `indirectPointerTouchMode`:

```swift
extension View {
    public func paperInput(direct: PaperTouchMode = .automatic, pointer: PaperTouchMode = .automatic) -> some View
}

public enum PaperTouchMode: Hashable, Sendable {
    case automatic   // follow the system "Only Draw with Apple Pencil" setting (directTouchAutomaticallyDraws)
    case draw        // finger or pointer draws
    case navigate    // finger or pointer scrolls and selects; only Pencil draws
}
```

`direct` is a finger on the screen. `pointer` is a trackpad or mouse on iPad and Mac. Case names map to PaperKit's `TouchMode` (verify its cases in Phase 0).

#### Selection content

The selection binding holds IDs. To copy or share what is selected, the editor also reports the selection as its own markup, from `selectedMarkup: PaperMarkup`:

```swift
extension View {
    public func onPaperSelectionChange(perform action: @escaping (_ selection: PaperSelection, _ selectedContent: Markup) -> Void) -> some View
}
```

```swift
.onPaperSelectionChange { selection, selectedContent in
    shareable = selection.isEmpty ? nil : selectedContent   // ShareLink(item: Paper(markup: shareable))
}
```

If Phase 0 shows selection is report-only, this callback is also how selection reaches the app, replacing the binding.

#### Smaller additions

| Addition | Type | Built on |
|---|---|---|
| `Markup.contentBounds` | `var contentBounds: CGRect { get }` | `contentsRenderFrame`. For crop-to-content thumbnails and zoom-to-content |
| `Markup.indexableContent` | `var indexableContent: String? { get }` | Apple's cached text. Sync, so apps can feed Core Spotlight without running recognition |
| `Markup.erase(along:width:)` | `mutating func erase(along path: CGPath, width: CGFloat)` | iOS 27 programmatic erase with a `PKStrokePath` |
| `PaperStroke.path` | `var path: CGPath { get }` (plus `Path(_ stroke: PaperStroke)` in PaperUI) | iOS 27 `PKStrokePath` to Bézier conversion. Lets apps draw or hit-test strokes in SwiftUI |
| `Paper.resize(to:scalingContent:)` | `mutating func resize(to size: PaperSize, scalingContent: Bool)` | `transformContent(_:)` plus the size setter. `false` extends or crops, `true` scales the ink with the page |
| `.paperAdornments(_:)` | `func paperAdornments(_ adornments: [PaperAdornment]) -> some View` | `adornments` and `adornmentFrame(for:)`. Shape of `PaperAdornment` waits on Phase 0, since Apple's docs say little |
| VoiceOver label | no API | The editor and `PaperView` default their `accessibilityLabel` to `indexableContent`. Apps override with `.accessibilityLabel` |
| Preview samples | `static var sample: Paper { get }`, `static var samplePDF: Paper { get }` | In `PaperTesting`, so `#Preview` works without a device |

`path`, `erase(along:width:)`, and `contentBounds` live in `PaperCore` because they need PencilKit or PaperKit. `PaperModel` stays portable.

---

## 5. Value types

### 5.1 Color

Our color type mirrors SwiftUI's `Color.Resolved`: linear RGBA floats that may exceed 1.0 for HDR ink. It is a separate struct, so `PaperModel` does not import SwiftUI.

```swift
public struct PaperColor: Codable, Hashable, Sendable {
    public var red, green, blue, opacity: Float   // linear, may exceed 1.0 for HDR
}
```

`PaperUI` adds `init(_ resolved: Color.Resolved)`, `init(_ color: Color, in environment: EnvironmentValues)`, and `var color: Color`.

### 5.2 Inks and tools

```swift
public enum InkKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon
    // add new PencilKit ink types here; @unknown default maps to .pen
}

public struct PaperInk: Codable, Hashable, Sendable {
    public var kind: InkKind
    public var color: PaperColor
}

public struct InkingTool: Codable, Hashable, Sendable {
    public var ink: PaperInk
    public var width: CGFloat
}

public enum EraserMode: Codable, Hashable, Sendable {
    case vector
    case bitmap(width: CGFloat?)
}

public enum PaperTool: Codable, Hashable, Sendable {
    case inking(InkingTool)
    case eraser(EraserMode)
    case lasso
}

// Ergonomics mirror Font / ShapeStyle static members
public extension PaperTool {
    static func pen(_ color: PaperColor, width: CGFloat = 3) -> Self
    static func pencil(_ color: PaperColor, width: CGFloat = 2) -> Self
    static func marker(_ color: PaperColor, width: CGFloat = 12) -> Self
    // ...
    static let eraser = PaperTool.eraser(.vector)
}
```

Why an enum of structs rather than a class hierarchy like `PKTool`: exhaustive `switch`, free `Codable`/`Hashable` synthesis, and tools can be stored in `@AppStorage`-backed favorites or synced via CloudKit as plain data.

Forward compatibility: decoding uses a custom `init(from:)` that maps unknown `InkKind` raw values to `.pen` and preserves the original string, so a file written by a newer app version still opens.

### 5.3 Paper size

```swift
public struct PaperSize: Hashable, Codable, Sendable {
    public var size: CGSize                        // points, 72 per inch
    public init(width: Measurement<UnitLength>, height: Measurement<UnitLength>)
    public static let letter, legal, a4, a5, square: PaperSize
    public static func inches(_ w: Double, _ h: Double) -> PaperSize
    public static func millimeters(_ w: Double, _ h: Double) -> PaperSize
    public var landscape: PaperSize { get }        // swaps width and height
}
```

**A size, not a rect.** Apple's `PaperMarkup(bounds:)` takes a `CGRect`, but the origin is always `.zero` for a page, so exposing a rect would only invite a meaningless choice. The bridge builds the rect.

**Units: points, as an absolute size.** Points (1/72 inch) are what `PaperMarkup` bounds, PencilKit stroke widths, and text box font sizes already use, and they map one to one onto PDF and print. A ratio alone is not enough: a 3 pt pen line looks fine on a 612 pt-wide letter page and invisible on a 6,000 pt-wide one, so the absolute size gives tool widths and text sizes their meaning. The ratio is derived, never stored, and there is deliberately no ratio-only constructor.

Static members follow the `Font` and `Color` pattern.

### 5.4 Strokes with stable IDs

```swift
public struct PaperStroke: Identifiable, Codable, Hashable, Sendable {
    public let id: ID
    public let ink: PaperInk
    public let points: [PaperStrokePoint]
    public let transform: CGAffineTransform
    public let mask: PaperPath?
    public let randomSeed: UInt32

    public struct ID: Hashable, Codable, Sendable { let rawValue: UUID }   // PKStroke.id, iOS 27

    // Equality compares everything. Hashing uses id only.
    // Valid because equal values always share an id, and it keeps
    // Set/Dictionary operations O(1) instead of O(points).
    public func hash(into h: inout Hasher) { h.combine(id) }
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
```

Fields are `let` because a `PaperStroke` is a read-only snapshot of what is in the markup. Edits go through `Markup` methods, so there is no field you can change that silently goes nowhere.

`ID` wraps the iOS 27 `PKStroke` UUID in our own type, so app code never depends on PencilKit. Stable IDs unlock `ForEach` over strokes, selection that survives edits, and app data keyed by stroke (`[PaperStroke.ID: Tag]`) without the package needing to know about it.

### 5.5 Markup

**How PaperKit stores it.** Apple's `PaperMarkup` is a single value that holds the whole canvas: PencilKit ink strokes *and* inserted elements (shapes, text boxes, images, lines), interleaved in one z-order, plus the canvas bounds. Its initializer requires bounds, so a markup cannot exist without a size. It persists as one opaque blob through `dataRepresentation()` and `init(dataRepresentation:)`. Elements are created through insert calls on the markup and have no existence outside it.

**Our wrapper holds a live `PaperMarkup`, not raw `Data`.**

```swift
public struct Markup: Codable, Hashable, Sendable, Transferable {
    var base: PaperMarkup                  // the one source of truth
    var token: UUID                        // regenerated on every mutation
    private var cache: ProjectionCache     // final class, Mutex-guarded, copy-on-write

    public init(paperSize: PaperSize = .letter)

    public var paperSize: PaperSize {      // computed, never stored
        get { PaperSize(base.bounds.size) }
        set { base.bounds = CGRect(origin: .zero, size: newValue.size) }
    }

    public var isEmpty: Bool { get }               // no strokes or elements
    public var strokes: [PaperStroke] { get }      // decoded on first read, cached
    public var elements: [PaperElement] { get }    // decoded on first read, cached
    // Inserting new elements from code (Section 4.9)
    public mutating func insertShape(_ shape: PaperShape, style: PaperShapeStyle, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertLine(from start: CGPoint, to end: CGPoint, style: PaperShapeStyle, startArrow: Bool = false, endArrow: Bool = false)
    public mutating func insertText(_ text: AttributedString, in frame: CGRect, rotation: Angle = .zero)
    public mutating func insertImage(_ image: CGImage, in frame: CGRect, rotation: Angle = .zero)
    public mutating func erase(along path: CGPath, width: CGFloat)
    public var contentBounds: CGRect { get }       // PaperMarkup.contentsRenderFrame
    public var indexableContent: String? { get }   // PaperMarkup.indexableContent
    public mutating func append(_ other: Markup)
    public mutating func rotate(_ turn: PaperRotation)   // right-angle increments, see below
    public mutating func remove(_ ids: some Collection<PaperElement.ID>)   // pending Phase 0

    public func data() async throws -> Data        // wraps async dataRepresentation()
    public var paperColor: CGColor? { get set }    // PaperMarkup.backgroundColor, part of the content
    public func image(scale: Double) async throws -> CGImage
    public func image(fitting box: CGSize) async throws -> CGImage
    public func pdfData() async throws -> Data
}
```

Key decisions:

- **One source of truth, including size.** `paperSize` reads and writes the wrapped `PaperMarkup`'s bounds. Nothing is stored twice. If Apple's bounds turn out to be read-only, the setter rebuilds the markup with new bounds and re-appends its contents. Changing size after drawing extends or crops the page from the bottom-right without moving any strokes.
- **No serialization on the hot path.** Holding a live `PaperMarkup` means the coordinator can update the binding at stroke end without encoding anything. Serialization happens only in `data()` and `encode(to:)`. This matters because `dataRepresentation()` is `async throws` (confirmed), which makes synchronous `Data` storage impossible.
- **`Codable` with an async source.** `encode(to:)` is synchronous but `dataRepresentation()` is async, so `Markup` keeps a serialized snapshot that the coordinator refreshes in the background after each stroke, and `encode(to:)` writes that snapshot. Apps that need guaranteed-fresh bytes call `try await markup.data()`. Decoding is simple because `init(dataRepresentation:)` is synchronous.
- **Projections are cached safely.** `strokes` and `elements` decode once per token and are stored in a private `final class` box guarded by a `Mutex`. Mutations replace the box (copy-on-write), so copies never share stale caches and the type stays `Sendable`.
- **Cheap equality.** `==` returns true immediately when tokens match. Otherwise it falls back to Apple's own `Equatable` conformance on `PaperMarkup`. `hash` uses `paperSize` only, which is coarse but always consistent with `==`.
- **Rotation is a content edit, in right angles only.** `markup.rotate(.clockwise)` turns the page the way Preview's Rotate Left/Right does: the paper size swaps width and height, and every stroke and element turns with it. Because the page is truly rotated, it saves, exports, and prints rotated with no extra orientation flag to track.

  ```swift
  public enum PaperRotation: Hashable, Sendable, CaseIterable {
      case clockwise, counterclockwise, halfTurn
  }

  markup.rotate(.clockwise)          // letter portrait → letter landscape, content turned 90°
  ```

  Implementation uses two documented pieces: `transformContent(_:)` with a 90° rotation plus a translation back into positive coordinates, then the `paperSize` setter to swap the dimensions. Right angles keep it lossless: points land on exact coordinates, the page stays a rectangle, and four quarter turns return the original. Stroke UUIDs survive transforms per Apple, so selection and app data keyed by ID stay valid. In the editor, rotation is a binding write like any other markup change, so the coordinator re-applies the content mode and anchor, and the app registers undo for it. Free-angle rotation is deliberately excluded: it would leave the page a non-rectangle or force a bounding box that grows on every turn.

  A display-only rotation (turning the view while the page stays put, for comfortable drawing) would be a separate view modifier. It is not in v1.
- **Inserts take a frame.** A value has no idea what is on screen, so each insert takes a position in page coordinates, matching Apple's `insertNewShape(configuration:frame:rotation:)` family. To insert where the user is looking, read `PaperScrollPosition.visibleRect` (Section 4.9).
- **Removal is unconfirmed.** The documented `PaperMarkup` API can insert, append, and transform, but shows no remove method. Removal may work by mutating `subelements`. Until Phase 0 confirms it, `remove(_:)` is provisional.
- **Name.** Apple owns `PaperMarkup`, so ours is `Markup`, disambiguated as `PaperUI.Markup` if ever needed.
- **Strokes and elements are never stored separately.** Z-order lives in the markup, Apple's blob carries data we cannot reconstruct, and two editable copies eventually disagree.
- **Off-screen rendering.** `image(scale:)`, `image(fitting:)`, and `pdfData()` are `async` because Apple's `draw(in:frame:options:)` is. See Section 4.7.

### 5.6 Paper: three fixed layers

Every `Paper` has the same three layers, bottom to top. There is no nesting.

| Layer | Property | Type | Editable in `PaperEditor` | Holds |
|---|---|---|---|---|
| Top | `markup` | `Markup` | Yes | Current work |
| Middle | `locked` | `Markup` | No (visible only) | Earlier work that has been flattened |
| Bottom | `background` | `PaperBackground?` | No | A PDF page or image template |

```swift
public struct Paper: Codable, Hashable, Sendable, Transferable {
    public var markup: Markup                      // top: editable
    public var locked: Markup                      // middle: visible, not editable (empty by default)
    public var background: PaperBackground?        // bottom: static template

    public init(size: PaperSize = .letter, background: PaperBackground? = nil)
    public init(markup: Markup, locked: Markup? = nil, background: PaperBackground? = nil)
    public init(pdfPage: PDFPage)                  // size from the page's media box
    public init(image: CGImage, size: PaperSize)   // image stretched to the page

    public mutating func flatten()                 // top merges into locked; top becomes empty
    public mutating func unlock()                  // locked merges under top; locked becomes empty
    public mutating func archive() async throws    // one-way: all layers baked into a searchable PDF background

    public var size: PaperSize { get set }         // keeps both markups the same size
    public mutating func rotate(_ turn: PaperRotation)   // turns all three layers together

    public func image(scale: Double) async throws -> CGImage
    public func image(fitting box: CGSize) async throws -> CGImage
    public func pdfData() async throws -> Data
}

public enum PaperBackground: Codable, Hashable, Sendable {
    case image(Data)       // encoded PNG / JPEG / HEIC, stretched to the page
    case pdfPage(Data)     // a single-page PDF, extracted from the source document
}
```

**Flatten and unlock.**

```swift
paper.flatten()    // "commit": the student's answers become part of the locked worksheet
paper.unlock()     // "reopen": everything locked becomes editable again, under the current ink
```

- **`flatten()`** appends `markup` onto `locked` with PaperKit's `append(contentsOf: PaperMarkup)`, then resets `markup` to an empty markup of the same size. Appending lands on top, so the newest work stays above older work, exactly as it looked.
- **`unlock()`** is the reverse: it starts from `locked`, appends `markup` onto it, makes the result the new `markup`, and empties `locked`. Starting from `locked` keeps the current ink on top.
- **Repeated flattening accumulates.** Each `flatten()` adds the top layer onto whatever is already locked, so a review cycle (draw, flatten, draw, flatten) builds one locked layer in order.
- Both are ordinary changes to the binding, undoable if the app registers them. Phase 0 check 7 confirms `append(contentsOf:)` keeps stroke UUIDs.

**Is the locked layer compacted? No, deliberately.** Flattening merges two markups into one `PaperMarkup`, losslessly. Every stroke stays vector with its ID, text stays searchable, and `unlock()` can bring it all back. The stored size is about the same as before flattening, since nothing is thrown away. That is the right default, because the alternatives all destroy something:

| Possible compaction | Gains | Loses |
|---|---|---|
| Rasterize to an image | Fixed size, fast drawing | Sharpness when zoomed, stroke IDs, handwriting recognition, unlock |
| Render to PDF | Vector, often smaller for dense ink | Stroke IDs, PencilKit recognition, unlock |

**`archive()`: the explicit one-way compaction.**

```swift
var copy = paper
try await copy.archive()     // async: rendering and recognition are async
paper = copy
```

1. Recognize the text in `markup` and `locked` (handwriting and text boxes), with positions.
2. Render all three layers into a single-page PDF with `pdfData()`. Ink stays vector, so it is sharp at any zoom, not an image.
3. Write the recognized text into that PDF as an invisible text layer at the matching positions, the same technique scanners use to make scanned PDFs searchable.
4. The result becomes `background` as `.pdfPage`, and `markup` and `locked` are emptied.

After archiving, the page looks identical and **is still searchable**: the text now comes from the PDF's own text layer through PDFKit, reported as `.background`. Copying text out of it works in any PDF viewer too. What is given up is editing: stroke IDs, `unlock()`, and per-stroke recognition are gone. Archiving an image background produces a PDF background that contains the image.

Use it for finished pages: signed forms, graded worksheets, anything that should not change. It ships in Phase 4 with recognition, since step 1 depends on it.

Key decisions:

- **Fixed layers instead of nesting.** An earlier draft allowed `.paper(Paper)` backgrounds that could nest without limit. Three named layers cover the real cases (template, locked work, current work) with no recursion in rendering, rotation, or equality.
- **Size has one meaning.** `markup` and `locked` each wrap a `PaperMarkup` with its own bounds, so `size` sets both, and every initializer and mutation keeps them equal. Reading `size` reads `markup.paperSize`.
- **Embedded background, not referenced.** The background is stored as data, so a `Paper` is self-contained. Apps that can't afford embedding use the `Markup` layer with `PaperEditor(markup:on:)`.
- **PDF pages are extracted.** `Paper(pdfPage:)` copies the one page into a single-page PDF. Shared fonts and resources are duplicated per page, an acceptable cost for a self-contained sheet.
- **No `.color` background.** Paper color is stored in Apple's blob (`markup.paperColor`). `flatten()` and `unlock()` keep the top layer's color if set, otherwise the locked layer's.
- **Rotation turns all three layers.** Markups rotate as in Section 5.5. A PDF page gets its rotation attribute updated, and an image is rotated by whole pixels and re-encoded as PNG. All lossless.
- **Rendering stays sharp.** The editor shows `locked` through the tiled PDF view, rendered once to single-page PDF with `pdfData()` and refreshed only when `locked` changes. This relies on PaperKit drawing vector output into a PDF context (a Phase 0 check). The fallback is a high-resolution bitmap re-rendered past a zoom threshold.
- **Text recognition sees every layer.** `PaperTextSource` gains a `.locked` case, so `recognizedText(.locked)` reads only flattened work, and `.all` reads all three layers.
- **Equality.** `==` checks `markup`, then `locked` (cheap token checks), and compares background data last.

---

## 6. The bridge (where the coordinator lives)

`PaperEditor` is a `UIViewControllerRepresentable` (`NSViewControllerRepresentable` on macOS) wrapping `PaperMarkupViewController`. Its private `Coordinator` is the "paperContext". It:

- Observes the view controller's properties with Swift Observation (the controller is `Observable`, and Apple's sample watches `markup` this way), uses the delegate only where Observation can't help, and acts as the `PKToolPicker` observer, and owns the tool picker's lifetime. One picker per window, shared between editors.
- Converts between our value types and framework types (`PaperTool ↔ PKTool`, `PaperFeatures → FeatureSet`, `PaperStroke ← PKStroke`).
- Prevents feedback loops. It records the last `token` it pushed and the last it received. `updateUIViewController` only writes markup into the view controller when the binding's token differs from both, which means the change came from outside (load, sync, programmatic insert).
- Coalesces writes. Delegate change callbacks during an active stroke are batched so the binding updates once per stroke end, not per touch sample. If serialization is async, it refreshes the markup's snapshot in the background afterward.
- Computes the resting scale from the content mode on every layout change (rotation, split view), keeps the user's relative zoom across those changes, and reports geometry through the transform closure.
- Reads the borrowed environment values in 4.2 (`\.isEnabled`, `\.isScrollEnabled`, scroll indicator visibility, focus, layout direction, reduce motion) and applies them to the view controller.

Users never see this type. All the density that tempted Option B is real, and it is handled here.

---

## 7. Package organization

One Swift package, three library targets, a test-support target, and one demo app.

```
swiftui-paper/
├─ Package.swift
├─ Sources/
│  ├─ PaperModel/          # portable: Foundation + CoreGraphics only
│  │  ├─ Color/PaperColor.swift
│  │  ├─ Tools/InkKind.swift, PaperInk.swift, PaperTool.swift
│  │  ├─ Size/PaperSize.swift
│  │  ├─ Strokes/PaperStroke.swift, PaperStrokePoint.swift, PaperPath.swift
│  │  └─ State/PaperSelection.swift, PaperGeometry.swift, PaperFeatures.swift, PaperContentMode.swift
│  ├─ PaperCore/           # imports PaperKit + PencilKit; owns Markup
│  │  ├─ Markup/Markup.swift, Markup+Codable.swift, ProjectionCache.swift, PaperElement.swift
│  │  ├─ Paper/Paper.swift, PaperBackground.swift, Paper+Rendering.swift
│  │  └─ Conversions/PKTool+PaperTool.swift, PKStroke+PaperStroke.swift, FeatureSet+PaperFeatures.swift
│  ├─ PaperUI/             # public SwiftUI API; @_exported import PaperModel, PaperCore
│  │  ├─ PaperEditor.swift
│  │  ├─ PaperEditorCoordinator.swift      (iOS)
│  │  ├─ PaperEditorCoordinator+macOS.swift
│  │  ├─ Modifiers/Config.swift, Bindings.swift, Events.swift
│  │  ├─ Environment/PaperEnvironmentKeys.swift
│  │  ├─ Color/PaperColor+SwiftUI.swift
│  │  └─ Views/PaperView.swift, PDFPageView.swift, PaperToolbar.swift (Phase 4)
│  └─ PaperTesting/        # fixtures, sample markups, snapshot helpers
├─ Tests/
│  ├─ PaperModelTests/     # Codable round-trips, Hashable laws, forward-compat decoding
│  ├─ PaperCoreTests/      # Markup round-trips, size get/set, stroke ID stability, PK conversions
│  └─ PaperUITests/        # coordinator loop prevention, geometry reporting
├─ Demo/SwiftPaperDemo/    # app target: single-canvas sketch app, custom toolbar
└─ docs/PLAN.md, docs/REVIEW.md
```

Rules that keep this healthy:

- **`PaperModel`** never imports UIKit, AppKit, SwiftUI, PencilKit, or PaperKit. It holds everything that is plain data: tools, inks, colors, sizes, strokes, selection, geometry. It compiles and tests on any platform and can be shared with a server or widget.
- **`PaperCore`** is the only target that touches Apple's markup frameworks. It owns `Markup`, because `Markup` wraps a live `PaperMarkup`, and `Paper`, because `Paper` contains a `Markup` and renders PDF backgrounds with PDFKit. If Apple renames something, this target changes and nothing else does.
- **`PaperUI`** holds the SwiftUI views and modifiers and re-exports the other two, so app code needs one import.
- Use Swift Testing (`@Test`) throughout. Property-style tests check that `decode(encode(x)) == x` and that `a == b` implies equal hashes.

Platforms: iOS 27, iPadOS 27, macOS 27, and visionOS 27 minimum. PaperKit itself starts at 26, but stable stroke IDs arrive in 27, and the plan depends on them. Swift 6 language mode with strict concurrency.

---

## 8. Roadmap

| Phase | Deliverable | Done when |
|---|---|---|
| **0. Spike** | Bare `PaperEditor(markup:)` on iPad that answers the checks in Section 9.2 | Markup round-trips through `@State` without loops; strokes found in `subelements` with UUIDs that survive save; selection can (or provably cannot) be set; `bounds` setter behavior known; `.fitWidth` + `.top` anchor works |
| **1. Model** | `PaperModel` types, `Markup` in `PaperCore`, `Codable`/`Hashable` tests, tool and stroke conversion | Lossless PK ↔ Paper round-trip on fixture strokes; stroke IDs survive save and reload; `paperSize` get/set round-trips; four quarter turns return an equal markup with the same IDs; `Paper` round-trips through `Codable` with its background |
| **2. Core API** | `.paperTool`, `.paperFeatures`, `.paperToolPicker(isPresented:)`, `.disabled`, `.paperContentMode`, `.paperZoomRange`, loop-safe coordinator | Tool picker and a SwiftUI button both change the tool with no flicker; all four content modes behave through rotation |
| **3. Interaction** | Selection (binding or callback per Phase 0), `PaperView`, image and PDF export, `onPaperGeometryChange`, insertion menu, `Image` and `PDFPageView` backgrounds, `onPaperDrawingBegan` | Selection survives edits by stroke ID; geometry action fires only on transformed-value changes |
| **4. Native UI, text, and audit additions** | `PaperToolbar` in pure SwiftUI; `recognizedText()` and `search(_:)` across ink, PDF text, and Vision OCR; `archive()`; `.paperScrollPosition`, tool picker items, `.paperInput`, insert methods, Section 4.9 smaller additions | Demo app ships without `PKToolPicker` |
| **5. Platforms** | macOS (`MarkupToolbarViewController`), visionOS | Same demo runs on every supported platform |

---

## 9. Risks and open questions

### 9.1 What Apple's documentation already answers

Checked against Apple's PaperKit reference pages and the WWDC26 PencilKit session (203) on 2026-10-31.

| Question | Answer from docs | Effect on the plan |
|---|---|---|
| Is `dataRepresentation()` async? | **Yes:** `func dataRepresentation() async throws -> Data`. `init(dataRepresentation:)` is sync and `throws` | Confirms 5.5: hold a live `PaperMarkup`, keep a background-refreshed snapshot for `encode(to:)`, expose `try await markup.data()` |
| What does `PaperMarkup` conform to? | `Identifiable`, `Equatable`, `Sendable`. **Not** `Codable` or `Hashable` | Wrapper still needed for `Codable`/`Hashable`. Apple's `Equatable` can back our `==` once the token check misses |
| Can we read the contents? | `subelements: MarkupOrderedSet`, keyed by `MarkupOrderedSet.ElementID`. No stroke or `PKDrawing` getter (`append(contentsOf: PKDrawing)` is write-only) | `elements` projection is feasible. `strokes` depends on whether ink appears inside `subelements` (Phase 0) |
| Do strokes have stable IDs? | **Yes, iOS 27:** `PKStroke` and `PKStrokePath` are `Identifiable` with a stable `UUID` that survives transforms, edits, and undo. Apple says the new PencilKit APIs also work with PaperKit | `PaperStroke.ID` wraps a `UUID`. Raises the floor to iOS 27 for stroke identity |
| Is selection settable? | Controller exposes `selection: Set<MarkupOrderedSet.ElementID>` and `selectedMarkup`. PKCanvasView selection became controllable in iOS 27. Setter on PaperKit's `selection` not stated | `PaperSelection` should be one `Set<ElementID>`, not separate stroke and element sets. Setter still a Phase 0 check |
| Can we control scrolling? | **Largely yes:** `scrollConfiguration`, `contentVisibleFrame`, `setContentVisibleFrame(_:animated:)`, `zoomRange` | Content modes and anchors can be built on `setContentVisibleFrame`. Our own `UIScrollView` fallback is likely unnecessary |
| Undo? | Controller exposes `undoManager: UndoManager?` | Bridge it to `\.undoManager`. Binding writes still bypass it |
| Insert where the user is looking? | `suggestedFrameForInserting(contentInFrame:)` | Lets the editor pick a frame for menu inserts without the value knowing the screen |
| Change paper size? | `bounds` is listed as `var bounds: CGRect`; settability not stated. `transformContent(_:)` exists | `paperSize` setter design holds; Phase 0 confirms whether it writes bounds directly |
| Observation? | The controller is `Observable`, and Apple's sample watches `markup` with `Observations` | The coordinator can observe properties instead of relying only on delegate callbacks |
| Platforms | iOS, iPadOS, macOS, visionOS 26.0+ | visionOS returns to the platform list |

### 9.2 Remaining Phase 0 checks

1. **Ink inside `subelements`.** Do strokes appear in `MarkupOrderedSet`, and do they carry the iOS 27 stroke UUIDs? This decides whether `Markup.strokes` is possible.
2. **Stroke ID stability across save.** Do UUIDs survive `dataRepresentation()` → `init(dataRepresentation:)`?
3. **Selection setter.** Can we assign `selection` programmatically? If not, selection ships as a callback.
4. **`bounds` setter.** Settable directly, or must the `paperSize` setter rebuild the markup? Rotation depends on this too.
5. **Removal.** Can elements and strokes be removed by mutating `subelements`, since `PaperMarkup` documents no remove method?
7. **`append(contentsOf:)` and IDs.** Does appending one markup onto another (used by `flatten()` and `unlock()`) preserve stroke UUIDs, and what happens when both contain the same ID?
6. **Content modes on `setContentVisibleFrame`.** Confirm `.fitWidth` + `.top` anchor and resting-scale zoom can be built on it, and what `ScrollConfiguration` exposes.

### 9.3 Other risks

- **Element model depth.** `MarkupOrderedSet` element types are not documented in detail. `PaperElement` may start as an ID plus frame.
- **Background content.** Hosting SwiftUI content in `contentView` and scaling it with zoom. `Image` first.
- **HDR color fidelity.** Confirm linear components above 1.0 survive conversion to and from `PKInk`.
- **Tool picker ownership.** `PKToolPicker` is per-window. Two editors in one window share one picker.
- **OS floor.** Stroke IDs need iOS 27. Either target iOS 27 from the start, or ship strokes without IDs on 26. Recommendation: target 27 and keep the design simple.

---

## 10. Recommendation

Build **Option E**. Bind the paper like `TextEditor`, configure with environment modifiers and SwiftUI's own `.disabled`, bind tool and selection like `@FocusState`, place the page like an `Image` content mode, observe zoom like `onScrollGeometryChange`, and route undo through the standard `undoManager`. Keep the coordinator, but keep it private. Skip custom property wrappers and reader/proxy types.

The case is simple. Every piece of this API already has a SwiftUI precedent, so a developer who knows SwiftUI already knows how to use it. The markup stays in the developer's hands as a plain value, which makes persistence, previews, and testing trivial. Tools as value types are the quiet multiplier: they let a pure SwiftUI toolbar, saved favorites, and sync all share one `@State` without touching PencilKit. A public `PaperContext` would have been faster to write and slower to live with, and SwiftUI's steady shift from proxies to plain values shows which direction to bet on.

Start with Phase 0. Apple's documentation already settled async saving, scroll control, undo, conformances, platforms, and stroke identity. What remains is six yes/no checks that only a running app can answer (Section 9.2), and each already has a fallback in this plan. Nothing beyond Phase 0 should start until those answers are in.
