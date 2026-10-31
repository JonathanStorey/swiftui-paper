# SwiftUI Paper: Plan for a SwiftUI Port of PaperKit

**Status:** v1.2, Option E locked in, review fixes applied (see [REVIEW.md](REVIEW.md)) · **Date:** 2026-10-31

## 1. Goal

PaperKit is Apple's current home for Apple Pencil markup. It layers shapes, text, images, and an insertion menu on top of PencilKit ink, and it ships as UIKit/AppKit view controllers (`PaperMarkupViewController`, `MarkupEditViewController`, `MarkupToolbarViewController`) plus the `PaperMarkup` data model and `FeatureSet` configuration.

This project wraps all of that in an API that feels like it shipped in SwiftUI itself:

1. A single editor view that binds to a markup value the way `TextEditor` binds to a `String`.
2. Pure-Swift, `Codable`, `Hashable`, `Sendable` value types for tools, inks, colors, paper sizes, and strokes.
3. Strokes with stable identity (`Identifiable`) built on the new stroke IDs.
4. A module layout that keeps the portable model independent of UIKit and PaperKit so it can grow without rewrites.

**Scope.** The package stops at the canvas. `PaperEditor` and the `Markup` value it binds to are the deliverable. Files, multi-page documents, and app metadata belong to the app that uses the package.

> **Verify against the SDK.** Type names below that start with `PK` or `Paper` and are not ours (`PaperMarkup`, `FeatureSet`, `PKInkingTool`, `PKStroke`) refer to Apple's frameworks. Exact member names and signatures, especially whether `dataRepresentation()` is `async`, must be checked against the current SDK headers in Phase 0. The architecture does not depend on any single member name.

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
    @State private var markup = Markup(paperSize: .letter)
    @State private var tool: PaperTool = .pen(.black, width: 3)
    @State private var selection = PaperSelection()
    @State private var showToolPicker = true
    @State private var showInsertMenu = false

    var body: some View {
        PaperEditor(markup: $markup)
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

- **The markup is yours.** It lives in `@State`, a SwiftData `@Model`, or wherever your app keeps data. Saving, previews, and tests touch a plain value.
- **Each two-way piece is optional.** If you don't care about selection, don't bind it. `TextField` works the same way with `.focused`.
- **Tools are values.** A custom SwiftUI palette and the system `PKToolPicker` can drive the same `@State var tool` at once, which makes a native SwiftUI toolbar a later add-on instead of a rewrite.
- **No redundant modifiers.** Editing on/off reads `\.isEnabled`, so `.disabled(true)` on the editor, or on any container above it, just works.
- **Commands are value mutations.** `markup.insert(.rectangle, in: rect)` mirrors appending to a string.

**Background content** (`PaperEditor(markup:) { Image("worksheet") }`) is a Phase 3 feature. PaperKit wants a `UIView` under the markup that scales with zoom, and hosting arbitrary SwiftUI content there is non-trivial. Phase 3 ships `Image` backgrounds first.

### 4.2 Configuration modifiers (environment)

Keep the list short and group by concern. Each is a plain `EnvironmentValues` entry, so it inherits.

| Modifier | Maps to |
|---|---|
| `.disabled(_ :)` (SwiftUI's own) | editable flag, read from `\.isEnabled` |
| `.paperFeatures(_ :PaperFeatures)` | `FeatureSet` (`.latest`, `.version(_)`, insert/remove features, HDR headroom) |
| `.paperRulerActive(_ :)` | ruler |
| `.paperTouchPolicy(_ :)` | Pencil-only vs finger drawing |
| `.paperContentMode(_ :anchor:)` | how the page sits in the view at rest: `PaperContentMode` plus a `UnitPoint` anchor (default `.center`) |
| `.paperZoomRange(_ :)` | min/max zoom, relative to the content mode's resting scale |

`PaperFeatures` is our own `Hashable`, `Sendable` struct with static members (`.latest`, `.basic`) and modifiers (`.removing(.stickers)`), translated to `FeatureSet` in the bridge.

### 4.3 Interaction state

```swift
.paperTool($tool)                          // PaperTool, see 5.2
.paperSelection($selection)                // PaperSelection
.paperToolPicker(isPresented: $show)       // user can dismiss it, so it is a binding
.paperInsertionMenu(isPresented: $show)

public struct PaperSelection: Hashable, Sendable {
    public var strokeIDs: Set<PaperStroke.ID>
    public var elementIDs: Set<PaperElement.ID>
    public var isEmpty: Bool { strokeIDs.isEmpty && elementIDs.isEmpty }
    public mutating func clear()
}
```

**Selection direction depends on PaperKit.** PaperKit reports selection changes. Setting the selection programmatically by ID may not be public. Phase 0 checks this. If it is report-only, v1 ships `onPaperSelectionChange { selection in }` instead of a binding, and the binding arrives when the framework allows it. Shipping a binding that silently ignores writes would be worse than shipping no binding.

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

Programmatic zoom (zoom to a rect, zoom to the selection) is **out of v1**. If a real use case appears, the Swifty answer is a binding, `.paperZoom($scale)`.

**This whole section depends on controlling PaperKit's scroll view.** `PaperMarkupViewController` owns its scrolling internally. We may only get a zoom range and a visible-frame callback, not content insets or offsets. Phase 0 proves `.fitWidth` + anchor works. If it can't be done through the view controller, the fallback is hosting the view controller inside our own `UIScrollView`, and the last resort is shipping `.fit` only in v1.

### 4.5 Undo

The editor uses the view controller's own undo stack and exposes it through SwiftUI's `\.undoManager`, so an Undo button calls `undoManager?.undo()` as it would for a text view. One honest limit: changes the app writes into the `markup` binding (loading, sync, programmatic inserts) bypass the drawing undo stack. They are undoable only if the app registers them itself. Phase 0 confirms how PaperKit's undo stack and SwiftUI's environment value connect.

### 4.6 Events

Use the SwiftUI `onChange`/callback idiom rather than a delegate:

```swift
.onPaperDrawingBegan { ... }
.onChange(of: markup) { save() }   // works because Markup is Equatable
```

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

    public struct ID: Hashable, Codable, Sendable { let rawValue: String }

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

`ID` wraps the framework's stroke identifier as a string so it survives encoding regardless of the underlying type. Stable IDs unlock `ForEach` over strokes, selection that survives edits, and app data keyed by stroke (`[PaperStroke.ID: Tag]`) without the package needing to know about it.

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

    public var strokes: [PaperStroke] { get }      // decoded on first read, cached
    public var elements: [PaperElement] { get }    // decoded on first read, cached
    public mutating func insert(_ element: PaperElement.Template, in rect: CGRect)
    public mutating func removeStrokes(_ ids: some Collection<PaperStroke.ID>)

    public func data() async throws -> Data        // explicit serialization
}
```

Key decisions:

- **One source of truth, including size.** `paperSize` reads and writes the wrapped `PaperMarkup`'s bounds. Nothing is stored twice. If Apple's bounds turn out to be read-only, the setter rebuilds the markup with new bounds and re-appends its contents. Changing size after drawing extends or crops the page from the bottom-right without moving any strokes.
- **No serialization on the hot path.** Holding a live `PaperMarkup` means the coordinator can update the binding at stroke end without encoding anything. Serialization happens only in `data()` and `encode(to:)`. This matters because `dataRepresentation()` is likely `async`, which would make synchronous `Data` storage impossible.
- **`Codable` with an async source.** `encode(to:)` is synchronous. If `dataRepresentation()` is async, `Markup` keeps a serialized snapshot that the coordinator refreshes in the background after each stroke, and `encode(to:)` writes that snapshot. Apps that need guaranteed-fresh bytes call `try await markup.data()`. Phase 0 settles which path is needed.
- **Projections are cached safely.** `strokes` and `elements` decode once per token and are stored in a private `final class` box guarded by a `Mutex`. Mutations replace the box (copy-on-write), so copies never share stale caches and the type stays `Sendable`.
- **Cheap equality.** `==` returns true immediately when tokens match. Otherwise it compares `paperSize` and the serialized snapshots. `hash` uses `paperSize` only, which is coarse but always consistent with `==`.
- **Inserts take a rect.** A value has no idea what is on screen, so `insert` requires a position in page coordinates. "Insert where the user is looking" goes through the insertion menu, which the editor positions itself.
- **Name.** Apple owns `PaperMarkup`, so ours is `Markup`, disambiguated as `PaperUI.Markup` if ever needed.
- **Strokes and elements are never stored separately.** Z-order lives in the markup, Apple's blob carries data we cannot reconstruct, and two editable copies eventually disagree.
- **Off-screen rendering.** `Markup.image(scale:)` and an `ImageRenderer`-friendly `PaperThumbnail` view, built on the framework's draw-into-context API.

---

## 6. The bridge (where the coordinator lives)

`PaperEditor` is a `UIViewControllerRepresentable` (`NSViewControllerRepresentable` on macOS) wrapping `PaperMarkupViewController`. Its private `Coordinator` is the "paperContext". It:

- Acts as the view controller's delegate and the `PKToolPicker` observer, and owns the tool picker's lifetime. One picker per window, shared between editors.
- Converts between our value types and framework types (`PaperTool ↔ PKTool`, `PaperFeatures → FeatureSet`, `PaperStroke ← PKStroke`).
- Prevents feedback loops. It records the last `token` it pushed and the last it received. `updateUIViewController` only writes markup into the view controller when the binding's token differs from both, which means the change came from outside (load, sync, programmatic insert).
- Coalesces writes. Delegate change callbacks during an active stroke are batched so the binding updates once per stroke end, not per touch sample. If serialization is async, it refreshes the markup's snapshot in the background afterward.
- Computes the resting scale from the content mode on every layout change (rotation, split view), keeps the user's relative zoom across those changes, and reports geometry through the transform closure.
- Reads `\.isEnabled` and maps it to the view controller's editable flag.

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
│  │  └─ Conversions/PKTool+PaperTool.swift, PKStroke+PaperStroke.swift, FeatureSet+PaperFeatures.swift
│  ├─ PaperUI/             # public SwiftUI API; @_exported import PaperModel, PaperCore
│  │  ├─ PaperEditor.swift
│  │  ├─ PaperEditorCoordinator.swift      (iOS)
│  │  ├─ PaperEditorCoordinator+macOS.swift
│  │  ├─ Modifiers/Config.swift, Bindings.swift, Events.swift
│  │  ├─ Environment/PaperEnvironmentKeys.swift
│  │  ├─ Color/PaperColor+SwiftUI.swift
│  │  └─ Views/PaperThumbnail.swift, PaperToolbar.swift (Phase 4)
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
- **`PaperCore`** is the only target that touches Apple's markup frameworks. It owns `Markup`, because `Markup` wraps a live `PaperMarkup`. If Apple renames something, this target changes and nothing else does.
- **`PaperUI`** holds the SwiftUI views and modifiers and re-exports the other two, so app code needs one import.
- Use Swift Testing (`@Test`) throughout. Property-style tests check that `decode(encode(x)) == x` and that `a == b` implies equal hashes.

Platforms: iOS 26, iPadOS 26, and macOS 26 minimum (PaperKit's floor). visionOS is added only once PaperKit availability there is confirmed. Swift 6 language mode with strict concurrency.

---

## 8. Roadmap

| Phase | Deliverable | Done when |
|---|---|---|
| **0. Spike** | Bare `PaperEditor(markup:)` on iPad that answers the five open questions in Section 9 | Markup round-trips through `@State` without loops; `.fitWidth` + `.top` anchor works; selection can (or provably cannot) be set by ID; undo works after an external write; `dataRepresentation()` sync/async confirmed |
| **1. Model** | `PaperModel` types, `Markup` in `PaperCore`, `Codable`/`Hashable` tests, tool and stroke conversion | Lossless PK ↔ Paper round-trip on fixture strokes; stroke IDs survive save and reload; `paperSize` get/set round-trips |
| **2. Core API** | `.paperTool`, `.paperFeatures`, `.paperToolPicker(isPresented:)`, `.disabled`, `.paperContentMode`, `.paperZoomRange`, loop-safe coordinator | Tool picker and a SwiftUI button both change the tool with no flicker; all four content modes behave through rotation |
| **3. Interaction** | Selection (binding or callback per Phase 0), `onPaperGeometryChange`, insertion menu, `Image` backgrounds, `onPaperDrawingBegan` | Selection survives edits by stroke ID; geometry action fires only on transformed-value changes |
| **4. Native UI** | `PaperToolbar` in pure SwiftUI, `PaperThumbnail` | Demo app ships without `PKToolPicker` |
| **5. Platforms** | macOS (`MarkupToolbarViewController`), visionOS if supported | Same demo runs on every supported platform |

---

## 9. Risks and open questions

Ranked by how much of the plan each one can invalidate. Items 1 through 5 are Phase 0's job.

1. **Scroll control.** `.paperContentMode`, anchors, and resting-scale zoom assume we can control placement inside `PaperMarkupViewController`. Fallback: our own `UIScrollView` around it, then `.fit`-only.
2. **Async serialization.** If `dataRepresentation()` is `async`, `Markup` keeps a background-refreshed snapshot for `encode(to:)` (Section 5.5). Already designed for, but it must be confirmed.
3. **Stroke ID access and stability.** The plan assumes the new stroke IDs are readable and stable across `dataRepresentation()` round-trips.
4. **Programmatic selection.** If setting selection by ID is not public, selection ships as a callback, not a binding.
5. **Undo integration.** Confirm how PaperKit's undo stack surfaces through SwiftUI's `\.undoManager`, and document that binding writes bypass it.
6. **Element model depth.** PaperKit may not expose shapes, text boxes, and images as inspectable values. If not, `PaperElement` starts as an opaque ID plus bounds.
7. **Background content.** Hosting SwiftUI content under the markup and scaling it with zoom. `Image` first.
8. **Mutable bounds.** If `PaperMarkup.bounds` is read-only, the `paperSize` setter rebuilds the markup. Test that it preserves z-order and IDs.
9. **HDR color fidelity.** Confirm linear components above 1.0 survive conversion to and from `PKInk`.
10. **Tool picker ownership.** `PKToolPicker` is per-window. Two editors in one window share one picker.

---

## 10. Recommendation

Build **Option E**. Bind the markup like `TextEditor`, configure with environment modifiers and SwiftUI's own `.disabled`, bind tool and selection like `@FocusState`, place the page like an `Image` content mode, observe zoom like `onScrollGeometryChange`, and route undo through the standard `undoManager`. Keep the coordinator, but keep it private. Skip custom property wrappers and reader/proxy types.

The case is simple. Every piece of this API already has a SwiftUI precedent, so a developer who knows SwiftUI already knows how to use it. The markup stays in the developer's hands as a plain value, which makes persistence, previews, and testing trivial. Tools as value types are the quiet multiplier: they let a pure SwiftUI toolbar, saved favorites, and sync all share one `@State` without touching PencilKit. A public `PaperContext` would have been faster to write and slower to live with, and SwiftUI's steady shift from proxies to plain values shows which direction to bet on.

Start with Phase 0. It is now a short list of yes/no questions about PaperKit, and every answer is already paired with a fallback in this plan. Nothing beyond Phase 0 should start until those answers are in.
