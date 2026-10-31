# SwiftUI Paper: Plan for a SwiftUI Port of PaperKit

**Status:** v1.1, Option E locked in · **Date:** 2026-10-31

## 1. Goal

PaperKit is Apple's current home for Apple Pencil markup. It layers shapes, text, images, and an insertion menu on top of PencilKit ink, and it ships as UIKit/AppKit view controllers (`PaperMarkupViewController`, `MarkupEditViewController`, `MarkupToolbarViewController`) plus the `PaperMarkup` data model and `FeatureSet` configuration.

This project wraps all of that in an API that feels like it shipped in SwiftUI itself:

1. A single editor view that binds to a markup value the way `TextEditor` binds to a `String`.
2. Pure-Swift, `Codable`, `Hashable`, `Sendable` value types for tools, inks, colors, and strokes.
3. Strokes with stable identity (`Identifiable`) built on the new stroke IDs.
4. A module layout that keeps the model independent of UIKit so it can grow without rewrites.

> **Verify against the SDK.** Type names below that start with `PK` or `Paper` and are not ours (`PaperMarkup`, `FeatureSet`, `PKInkingTool`, `PKStroke`) refer to Apple's frameworks. Exact member names should be checked against the current SDK headers before Phase 1 code lands. The architecture does not depend on any single member name.

---

## 2. The design question

PaperKit's surface splits into four kinds of state. The right packaging falls out of sorting them correctly.

| Kind | Examples | Direction | SwiftUI precedent |
|---|---|---|---|
| **Markup** | the canvas content | two-way | `TextEditor(text:)` |
| **Configuration** | feature set, editable, ruler, finger-draws policy, background content | down only | `.textFieldStyle`, `.disabled`, `.scrollDisabled` |
| **Interaction state** | current tool, selection | two-way | `@FocusState` + `.focused` |
| **Layout and geometry** | how the page sits in the view, zoom scale, visible rect | down (content mode), up (geometry) | `Image` + `.aspectRatio(contentMode:)`, `.onScrollGeometryChange` |
| **Commands** | undo, insert shape, present insertion menu | one-shot | `UndoManager` in environment, `.popover(isPresented:)` |

Every option below is judged by how cleanly it handles all four rows.

---

## 3. Options

### Option A: Environment modifiers only

```swift
PaperEditor(markup: $markup)
    .paperTool(.pen(.black, width: 3))
    .paperFeatures(.latest)
    .paperRulerActive(true)
    .paperEditingDisabled(!isEditing)
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
- It does not match how Apple has evolved SwiftUI. Apple moved *away* from this shape: `ScrollViewReader`/`ScrollViewProxy` gave way to the `ScrollPosition` value type in iOS 18.
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

Mirrors `ScrollViewReader`. Solves commands only, and copies a pattern Apple has already superseded.

**Verdict.** Skip. Commands belong on value types and in standard environment values (see Section 4).

### Option E (recommended): Hybrid that mirrors existing SwiftUI

Sort each row to the SwiftUI pattern Apple already uses for it:

- **Markup:** a value binding, like `TextEditor`.
- **Configuration:** environment modifiers, like `.textFieldStyle`.
- **Interaction state:** small value types bound by modifiers, like `@FocusState`.
- **Layout and geometry:** the editor fills its space like a resizable `Image`, a content mode places the page inside it, and a change callback reports zoom, like `.onScrollGeometryChange`.
- **Commands:** mutating methods on those values, the standard `undoManager` environment value, and `isPresented` bindings.

The full API is in Section 4.

---

## 4. Recommended API

### 4.1 The editor

```swift
struct NotesView: View {
    @State private var markup = Markup()
    @State private var tool: PaperTool = .pen(.black, width: 3)
    @State private var selection = PaperSelection()
    @State private var showInsertMenu = false

    var body: some View {
        PaperEditor(markup: $markup) {
            Image("worksheet")                 // optional background content
        }
        .paperTool($tool)                      // two-way: tool picker writes back
        .paperSelection($selection)            // two-way, like .focused($field)
        .paperContentMode(.fit)                // like Image .aspectRatio(contentMode:)
        .paperFeatures(.latest)                // config, down only
        .paperToolPicker(isVisible: true)      // system PKToolPicker
        .paperInsertionMenu(isPresented: $showInsertMenu)
        .paperEditingDisabled(false)
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
- **Undo comes for free.** The editor registers with `@Environment(\.undoManager)`. Your Undo button calls `undoManager?.undo()` exactly as it would for any SwiftUI text view.
- **Commands are value mutations.** `markup.insert(.shape(.rectangle))` mirrors appending to a string.

### 4.2 Configuration modifiers (environment)

Keep the list short and group by concern. Each is a plain `EnvironmentValues` entry, so it inherits.

| Modifier | Maps to |
|---|---|
| `.paperFeatures(_ :PaperFeatures)` | `FeatureSet` (`.latest`, `.version(_)`, insert/remove features, HDR headroom) |
| `.paperEditingDisabled(_ :)` | editable flag |
| `.paperRulerActive(_ :)` | ruler |
| `.paperTouchPolicy(_ :)` | Pencil-only vs finger drawing |
| `.paperContentMode(_ :anchor:)` | how the page sits in the view at rest: SwiftUI's own `ContentMode` (`.fit`, `.fill`) plus a `UnitPoint` anchor (default `.center`) |
| `.paperZoomRange(_ :)` | min/max zoom, relative to the content mode's resting scale |
| `.paperToolPicker(isVisible:)` | `PKToolPicker` visibility, observer wiring |

`PaperFeatures` is our own `Hashable`, `Sendable` struct with static members (`.latest`, `.basic`) and modifiers (`.removing(.stickers)`), translated to `FeatureSet` in the bridge.

### 4.3 Interaction-state values

```swift
public struct PaperSelection: Hashable, Sendable {
    public var strokeIDs: Set<PaperStroke.ID>
    public var elementIDs: Set<PaperElement.ID>
    public var isEmpty: Bool { strokeIDs.isEmpty && elementIDs.isEmpty }
    public mutating func clear()
}
```

### 4.4 Layout, zoom, and geometry

**The editor fills the space it is offered.** `PaperEditor` is greedy, like `Color`, `ScrollView`, or a `.resizable()` image. Constrain it with the modifiers you already use: `.frame`, `.padding`, `.aspectRatio`.

**`.aspectRatio` shapes the view, not the page.** It is SwiftUI's standard modifier, and we don't override it. It changes the editor's frame to match the page shape, so there is no empty margin around the page:

```swift
PaperEditor(markup: $markup)
    .aspectRatio(contentMode: .fit)   // frame takes the page's shape, letterboxed by the parent
```

This works with no ratio argument, exactly as it does on `Image`, because the representable implements `sizeThatFits`. It returns the proposed size when the parent offers one (so the editor stays greedy) and the page size when asked for its ideal size (which is what `.aspectRatio` reads). When the frame already matches the page, `.paperContentMode` has nothing left to do. The two modifiers answer different questions: `.aspectRatio` sets the shape of the box, and `.paperContentMode` places the page inside whatever box results.

**The page has a fixed size, the view does not.** `Markup.bounds` is content, not layout, the same way an image's pixel size is. If bounds followed the view, rotating an iPad would resize the canvas and every stroke would land in the wrong place. You set the paper size when you create the markup:

```swift
@State private var markup = Markup(paperSize: .letter)            // 8.5 × 11 in
@State private var markup = Markup(paperSize: .a4)
@State private var markup = Markup(paperSize: .inches(8.5, 10))   // custom
@State private var markup = Markup(paperSize: .aspectRatio(4/3))  // shape only

public struct PaperSize: Hashable, Codable, Sendable {
    public var size: CGSize                        // points, 72 per inch
    public static let letter, legal, a4, a5, square: PaperSize
    public static func inches(_ w: Double, _ h: Double) -> PaperSize
    public static func millimeters(_ w: Double, _ h: Double) -> PaperSize
    public static func aspectRatio(_ ratio: CGFloat) -> PaperSize
    public var landscape: PaperSize { get }        // swaps width and height
}
```

Static members follow the `Font` and `Color` pattern. Paper size belongs on the markup, not on a view modifier, because strokes are stored in page coordinates: the size has to travel with the content. A `Markup()` created with no size adopts the editor's size on first layout, then stays fixed.

**Content mode maps one to the other.** This is the `Image` model applied to paper, reusing SwiftUI's own `ContentMode` type:

| Mode | At rest | Feels like |
|---|---|---|
| `.fit` (default) | Whole page visible, letterboxed | A sheet on a desk |
| `.fill` | Page fills the view, overflow scrolls | A notes app or whiteboard |

With `.fill`, the overflow axis falls out of the two shapes. A tall page in a wide view overflows vertically, a wide page in a tall view overflows horizontally. Nobody picks the axis, which means the app also cannot know in advance which edge needs to show first.

The rule is: compare the page's width÷height to the view's. If the page is relatively wider, it overflows horizontally. If it is relatively taller, it overflows vertically. A worked example with an 8.5 × 10 page (ratio 0.85) on an iPad:

| Orientation | View ratio | Page vs view | `.fill` scrolls |
|---|---|---|---|
| Portrait | ≈ 0.75 | page is wider | horizontally, slightly |
| Landscape | ≈ 1.33 | page is taller | vertically, a lot |

That is often the reverse of what people expect, so the demo app should show it. Apps that want "match the width, always scroll vertically" (a notes app) need a width-matching mode rather than `.fill`. Supporting it would mean replacing SwiftUI's `ContentMode` with our own enum, so it stays out of v1.

**The anchor picks where the page sits at rest.** It is a plain `UnitPoint`, the same type `.defaultScrollAnchor` and `scaleEffect(anchor:)` use, so `.top`, `.topLeading`, and `.center` all work with no new vocabulary.

```swift
.paperContentMode(.fill, anchor: .top)       // notes: start at the top of the page
.paperContentMode(.fill, anchor: .leading)   // timeline: start at the left edge
.paperContentMode(.fit, anchor: .top)        // letterboxed page pinned to the top
```

One anchor serves both modes. In `.fill` it sets the initial scroll position along whichever axis overflows. In `.fit` it decides where the letterbox space goes, just like `.frame(alignment:)` positions an `Image`. On rotation or resize the editor recomputes the resting scale and re-applies the anchor, unless the user has already scrolled or zoomed, in which case it keeps the same canvas point in view.

**Zoom is relative to the resting scale.** `zoomScale == 1` always means "at the content mode's resting size," on any device or orientation. That makes `.paperZoomRange(1...4)` portable and keeps app code free of point math. No viewport type is needed, since the user owns zoom with their fingers:

```swift
PaperEditor(markup: $markup)
    .paperContentMode(.fill, anchor: .top)       // resting placement, like Image
    .paperZoomRange(1...4)                       // relative to the resting scale
    .onPaperGeometryChange(for: Bool.self) {     // read-back, like .onScrollGeometryChange
        $0.zoomScale > 1
    } action: { _, isZoomedIn in
        showsResetButton = isZoomedIn
    }

public struct PaperGeometry: Equatable, Sendable {
    public var zoomScale: CGFloat      // 1 == resting scale for the content mode
    public var visibleRect: CGRect     // in canvas coordinates
    public var contentSize: CGSize
}
```

The transform closure means the action fires only when the value you care about changes, not on every pinch frame. That matches how `onScrollGeometryChange` keeps scroll observation cheap.

Programmatic zoom (zoom to a rect, zoom to the selection) is **out of v1**. If a real use case appears, the Swifty answer is a binding, `.paperZoom($scale)`, mirroring `.scrollPosition(id:)`. A value with pending-command methods and read-only fields is what we are avoiding.

### 4.5 Events

Use the SwiftUI `onChange`/callback idiom rather than a delegate:

```swift
.onPaperDrawingBegan { ... }
.onChange(of: markup) { save() }   // works because Markup is Equatable
```

---

## 5. Value types

All of these live in `PaperModel`, which imports Foundation and CoreGraphics only. No UIKit, no PencilKit.

### 5.1 Color

Use SwiftUI's `Color.Resolved` as the storage type. It is already `Codable`, `Hashable`, and `Sendable`, and it stores linear components, which matters for PaperKit's HDR ink support. Wrap it so `PaperModel` does not import SwiftUI:

```swift
public struct PaperColor: Codable, Hashable, Sendable {
    public var red, green, blue, opacity: Float   // linear, may exceed 1.0 for HDR
}
```

`PaperUI` adds `init(_ color: Color, in environment: EnvironmentValues)` and `var color: Color`.

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

### 5.3 Strokes with stable IDs

```swift
public struct PaperStroke: Identifiable, Codable, Hashable, Sendable {
    public let id: ID
    public var ink: PaperInk
    public var points: [PaperStrokePoint]
    public var transform: CGAffineTransform
    public var mask: PaperPath?
    public var randomSeed: UInt32

    public struct ID: Hashable, Codable, Sendable { let rawValue: String }

    // Equality compares everything. Hashing uses id only.
    // Valid because equal values always share an id, and it keeps
    // Set/Dictionary operations O(1) instead of O(points).
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct PaperStrokePoint: Codable, Hashable, Sendable {
    public var location: CGPoint
    public var timeOffset: TimeInterval
    public var size: CGSize
    public var opacity: CGFloat
    public var force: CGFloat
    public var azimuth: CGFloat
    public var altitude: CGFloat
}
```

`ID` wraps the framework's stroke identifier as a string so it survives encoding regardless of the underlying type. Stable IDs unlock the features that make this worth doing: `ForEach` over strokes in a layer list, selection that survives edits, per-stroke metadata dictionaries (`[PaperStroke.ID: Tag]`), and minimal diffs for sync and collaboration.

### 5.4 Markup and its contents

**Scope.** This package stops at the canvas. `PaperEditor` and the `Markup` value it binds to are the deliverable. Files, multi-page documents, and app metadata belong to the app that uses the package, which can store `Markup` values however it likes because they are `Codable`.

**How PaperKit stores it.** Apple's `PaperMarkup` is a single value that holds the whole canvas: PencilKit ink strokes *and* the inserted elements (shapes, text boxes, images, lines), interleaved in one z-order, plus the canvas bounds. It persists as one opaque blob through `dataRepresentation()` and `init(dataRepresentation:)`. Elements are created through insert calls on the markup (`insertNewShape`, `insertNewTextbox`, `insertNewImage`, `insertNewLine`) and ink can be appended from a `PKDrawing`. Elements have no existence outside a markup.

**Our types.**

| Type | What it is | Stored? |
|---|---|---|
| `Markup` | One canvas. Wraps one Apple `PaperMarkup` and adds `Codable`, `Hashable`, and cheap equality. `PaperEditor(markup:)` binds to it | Yes, as Apple's blob |
| `PaperStroke`, `PaperElement` | Read-only views of what is inside a markup | **No.** Derived on read |

```swift
public struct Markup: Codable, Hashable, Sendable, Transferable {
    public var bounds: CGRect
    var storage: Data            // PaperMarkup.dataRepresentation(), the source of truth
    var token: UUID              // regenerated on every change

    public var strokes: [PaperStroke] { get }          // derived, cached
    public var elements: [PaperElement] { get }        // derived, cached
    public mutating func insert(_ element: PaperElement.Template)
    public mutating func removeStrokes(_ ids: some Collection<PaperStroke.ID>)
}
```

**Why not name it `PaperMarkup`?** Apple already owns that name. Any file that imports both PaperKit and our package would hit an ambiguous-type error, including our own bridge target. `Markup` reads naturally at the call site (`@State var markup = Markup()`), and the module name disambiguates it if needed (`PaperUI.Markup`).

**Why wrap Apple's type at all?** Apple's `PaperMarkup` is not `Codable` or `Hashable`. Adding those conformances retroactively to a type we don't own is fragile and draws compiler warnings. A thin wrapper also lets us give it fast equality, which `onChange(of:)` and SwiftUI diffing depend on.

**Should strokes and elements be stored separately? No.**

1. **Z-order lives in the markup.** A text box can sit above one stroke and below the next. Splitting them means inventing an ordering scheme Apple already maintains.
2. **Fidelity.** Apple's blob carries data we cannot see or reconstruct. Rebuilding a markup from our own arrays would silently drop it.
3. **Drift.** Two editable copies of the same content eventually disagree.

Stable IDs still matter for anything outside the markup. An app can key its own data to a `PaperStroke.ID` without the package needing to know about it.

Key decisions for `Markup`:

- **Edits go through the markup.** `insert` and `removeStrokes` mutate the blob, then invalidate the cached projections. Same mental model as editing a `String` and reading its `.count`.
- **Cheap equality.** `==` returns true immediately when tokens match, and compares `bounds` and `storage` only when they differ. `hash` uses `bounds` and `storage.count`, which stays consistent with `==`.
- **Rendering off-screen.** `Markup.image(scale:)` and an `ImageRenderer`-friendly `PaperThumbnail` view, built on the framework's draw-into-context API.

---

## 6. The bridge (where the coordinator lives)

`PaperEditor` is a `UIViewControllerRepresentable` (`NSViewControllerRepresentable` on macOS) wrapping `PaperMarkupViewController`. Its private `Coordinator` is the "paperContext". It:

- Acts as the view controller's delegate and the `PKToolPicker` observer, and owns the tool picker's lifetime.
- Converts between our value types and framework types (`PaperTool ↔ PKTool`, `PaperFeatures → FeatureSet`, `Markup ↔ PaperMarkup`).
- Prevents feedback loops. It records the last `token` it pushed and the last it received. `updateUIViewController` only writes markup into the view controller when the binding's token differs from both, which means the change came from outside (load, undo from another view, sync).
- Coalesces writes. Delegate change callbacks during an active stroke are batched so the binding updates once per stroke end, not per touch sample.
- Computes the resting scale from the content mode on every layout change (rotation, split view), keeps the user's relative zoom across those changes, and reports geometry changes through the transform closure.

Users never see this type. That is the point: all the density that tempted Option B is real, and it is handled here.

---

## 7. Package organization

One Swift package, four targets, one demo app.

```
swiftui-paper/
├─ Package.swift
├─ Sources/
│  ├─ PaperModel/          # Foundation + CoreGraphics only
│  │  ├─ Color/PaperColor.swift
│  │  ├─ Tools/InkKind.swift, PaperInk.swift, PaperTool.swift
│  │  ├─ Strokes/PaperStroke.swift, PaperStrokePoint.swift, PaperPath.swift
│  │  ├─ Markup/Markup.swift, PaperElement.swift
│  │  └─ State/PaperSelection.swift, PaperGeometry.swift, PaperFeatures.swift
│  ├─ PaperBridge/         # PaperKit + PencilKit conversions, internal
│  │  ├─ PKTool+PaperTool.swift
│  │  ├─ PKStroke+PaperStroke.swift
│  │  ├─ FeatureSet+PaperFeatures.swift
│  │  └─ PaperMarkup+Markup.swift
│  ├─ PaperUI/             # public SwiftUI API, @_exported import PaperModel
│  │  ├─ PaperEditor.swift
│  │  ├─ PaperEditorCoordinator.swift      (iOS / visionOS)
│  │  ├─ PaperEditorCoordinator+macOS.swift
│  │  ├─ Modifiers/Config.swift, Bindings.swift, Events.swift
│  │  ├─ Environment/PaperEnvironmentKeys.swift
│  │  └─ Views/PaperThumbnail.swift, PaperToolbar.swift (Phase 4)
│  └─ PaperTesting/        # fixtures, sample markups, snapshot helpers
├─ Tests/
│  ├─ PaperModelTests/     # Codable round-trips, Hashable laws, forward-compat decoding
│  ├─ PaperBridgeTests/    # lossless PK ↔ Paper conversions
│  └─ PaperUITests/        # coordinator loop prevention, geometry reporting
├─ Demo/SwiftPaperDemo/    # app target: single-canvas sketch app, custom toolbar
└─ docs/PLAN.md
```

Rules that keep this healthy:

- `PaperModel` never imports UIKit, AppKit, SwiftUI, PencilKit, or PaperKit. It compiles and tests on any platform and can be shared with a server or widget.
- `PaperBridge` is the only target that touches Apple's markup frameworks. If Apple renames something, one target changes.
- `PaperUI` re-exports `PaperModel` so app code needs one import.
- Use Swift Testing (`@Test`) throughout. Property-style tests check that `decode(encode(x)) == x` and that `a == b` implies equal hashes.

Platforms: iOS 26, iPadOS 26, macOS 26, visionOS 26 minimum (PaperKit's floor). Swift 6 language mode with strict concurrency, since every model type is `Sendable`.

---

## 8. Roadmap

| Phase | Deliverable | Done when |
|---|---|---|
| **0. Spike** | Bare `PaperEditor(markup:)` on iPad, markup round-trips through `@State` | Draw, background, relaunch, markup restored |
| **1. Model** | `PaperModel` types, `Codable`/`Hashable` tests, `PaperBridge` tool and stroke conversion | Lossless PK ↔ Paper round-trip on fixture strokes |
| **2. Core API** | `.paperTool`, `.paperFeatures`, `.paperToolPicker`, undo via environment, loop-safe coordinator | Tool picker and a SwiftUI button both change the tool with no flicker or loops |
| **3. Interaction** | `PaperSelection`, `onPaperGeometryChange`, `paperContentMode`, insertion menu, `onPaperDrawingBegan` | Selection survives edits by stroke ID; geometry action fires only on transformed-value changes |
| **4. Native UI** | `PaperToolbar` in pure SwiftUI, `PaperThumbnail` | Demo app ships without `PKToolPicker` |
| **5. Platforms** | macOS (`MarkupToolbarViewController`), visionOS polish | Same demo runs on all three |

---

## 9. Risks and open questions

1. **Stroke ID access.** The plan assumes the new stroke IDs are readable and stable across `dataRepresentation()` round-trips. Phase 1 must prove this with a test before anything depends on it.
2. **Element model depth.** PaperKit may not expose shapes, text boxes, and images as inspectable values. If not, `PaperElement` starts as an opaque ID plus bounds and grows as Apple opens the model.
3. **Large-canvas performance.** Re-serializing on every stroke end may be too slow for very large pages. Fallback: keep `PaperMarkup` live in the coordinator and serialize lazily on read of `storage`.
4. **HDR color fidelity.** Confirm `Color.Resolved` linear components preserve values above 1.0 through encoding.
5. **Tool picker ownership.** `PKToolPicker` is per-window. Two editors in one window must share one picker. The coordinator should look up an existing picker for the window before creating one.

---

## 10. Recommendation

Build **Option E**. Bind the markup like `TextEditor`, configure with environment modifiers like `.textFieldStyle`, bind tool and selection as small value types like `@FocusState`, observe zoom like `onScrollGeometryChange`, and route undo through the standard `undoManager`. Keep the coordinator, but keep it private. Skip custom property wrappers and reader/proxy types.

The case is simple. Every piece of this API already has a SwiftUI precedent, so a developer who knows SwiftUI already knows how to use it. The markup stays in the developer's hands as a plain value, which is what makes `Codable` persistence, previews, and testing trivial. Tools as value types are the quiet multiplier: they let a pure SwiftUI toolbar, saved favorites, and sync all share one `@State` without touching PencilKit. A public `PaperContext` would have been faster to write and slower to live with, and Apple's own retreat from `ScrollViewReader` to `ScrollPosition` shows which direction SwiftUI is heading.

Start with Phase 0 this week. Its only job is to prove that a `Markup` value survives the round-trip through the coordinator without loops, because everything else in this plan rests on that.
