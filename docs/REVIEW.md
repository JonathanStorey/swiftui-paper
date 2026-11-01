# Plan Review: Critique of PLAN.md

**Reviewed:** PLAN.md as of 2026-10-31 (Option E locked in) · **Verdict:** The API shape is sound. The model layer has two structural contradictions that must be fixed before Phase 1, and several assumptions about PaperKit need to be proven in the Phase 0 spike rather than later.

> **Update:** All findings below were applied in PLAN.md v1.2.

Findings are ranked by how much rework they would cause if discovered late.

---

## Tier 1: Structural problems (fix before writing code)

### 1. `Markup` cannot live in `PaperModel`

The plan puts `Markup.swift` in `PaperModel`, which "never imports PaperKit." But `Markup.strokes`, `Markup.elements`, `insert(_:)`, `removeStrokes(_:)`, and `image(scale:)` all require decoding Apple's blob, which requires PaperKit. As written, the rule and the type contradict each other.

**Fix.** Split by capability. `PaperModel` holds the plain data (`Markup` as `paperSize` + `storage` + `token`, plus `Codable`/`Hashable`). The operations that need PaperKit become extensions in `PaperBridge` (or `PaperUI`), so `markup.strokes` only exists once you import the UI module. `PaperModel` stays portable, and the API reads the same at the call site.

### 2. Paper size has two sources of truth

`Markup` stores `paperSize` as a public `var`, and Apple's blob in `storage` also contains the bounds. Section 5.4 argues hard for "one source of truth" and then breaks it here. Setting `markup.paperSize = .a4` would leave the blob saying letter.

**Fix.** Make `paperSize` a computed property. The getter reads it from the cached decoded markup, and the setter rewrites the blob. Or make it `let` in v1 and add resizing later.

### 3. `dataRepresentation()` is likely `async`

The whole binding design assumes the coordinator can serialize synchronously at stroke end and write `storage` into the binding. If `PaperMarkup.dataRepresentation()` is `async throws` (my recollection is that it is), then `Markup` can't hold a fresh `Data` the moment a stroke ends, and `onChange(of: markup)` fires late or out of order.

**Fix.** Check the SDK first. If it is async, keep a live `PaperMarkup` inside `Markup` as the source of truth (it is already a `Sendable` value type) and serialize only in `encode(to:)` or an explicit `markup.data()` call. This promotes Risk 3 from "fallback" to "probably the default design," which is better learned now than in Phase 2.

### 4. "Derived, cached" needs a reference box

A struct's computed property can't write to a cache. Caching `strokes` and `elements` inside a value type requires a private class box, which complicates `Sendable` (it needs a lock or `Mutex`) and copy-on-write. That is fine, but the plan should say so. Otherwise, a naive version will re-decode the full blob on every access to `strokes` inside a `ForEach`.

---

## Tier 2: Unproven PaperKit assumptions (prove in Phase 0)

These are the places where the API promises something the wrapped view controller may not allow.

| # | Assumption | Why it might fail | Fallback |
|---|---|---|---|
| 5 | **We control placement and scrolling** (`.paperContentMode`, anchor, `.fill`, resting scale) | `PaperMarkupViewController` owns its scroll view internally. We may only get a zoom range and a visible-frame callback, not insets or content offset | Wrap the VC in our own `UIScrollView`, or limit v1 to `.fit` |
| 6 | **Selection is two-way** | PaperKit reports selection changes, but setting selection programmatically by ID may not be public | Make `.paperSelection` read-only (`onPaperSelectionChange`) until it is |
| 7 | **Undo uses SwiftUI's `undoManager`** | The VC registers undo on its own responder-chain `UndoManager`. Markup changes pushed in through the binding bypass undo entirely | Document that external writes are not undoable, and surface the VC's manager instead of claiming integration |
| 8 | **Background content as a SwiftUI closure** | The VC wants a `UIView` under the markup that scales with zoom. Hosting SwiftUI content there means a `UIHostingController` that tracks zoom without re-rendering | Ship `Image`-only backgrounds first |
| 9 | **`markup.insert(.shape(...))` as a pure value mutation** | Inserting needs a position. A value has no idea what is on screen, so "insert at center of view" can't be expressed | Take an explicit `CGRect`, or route view-relative inserts through the insertion menu |
| 10 | **visionOS support** | Not confirmed that PaperKit ships there | Drop from the platform list until verified |

**Recommendation.** Expand Phase 0 from "markup round-trips" to "markup round-trips, `.fill` + anchor works, selection can be set, undo works after an external write." Those four checks decide whether Section 4 survives.

---

## Tier 3: API polish

11. **`.paperEditingDisabled` should be `.disabled`.** SwiftUI already has `\.isEnabled` in the environment. Reading it means `Form { ... }.disabled(true)` just works, and there's one fewer modifier. This is the most Swifty change on the list.
12. **`.paperToolPicker(isVisible:)` should take a binding.** The user can dismiss the picker, so its visibility is two-way, like `.sheet(isPresented:)`. Rename it to `.paperToolPicker(isPresented: $show)`.
13. **`PaperStroke` fields should be read-only.** Strokes are projections, but their fields are `public var`, which invites edits that go nowhere. Use `public let` or `public private(set)`.
14. **`Markup()` adopting the editor's size mutates state during layout.** That triggers SwiftUI's "modifying state during view update" warning, and it contradicts "size is content." Default to `.letter`, or require a size.
15. **The `ScrollPosition` argument now cuts against us.** Section 3 and Section 10 cite the move to `ScrollPosition` as proof of direction, but we then rejected that pattern for zoom as un-Swifty. Reword it as "Apple moved from proxies to values," which is the part we actually rely on.
16. **The width-matching mode is deferred, but it is the notes-app default.** If `.fitWidth`/`.fitHeight` is likely, introducing `PaperContentMode` now costs nothing. Retrofitting it later means a breaking change to `.paperContentMode`'s signature.

---

## Tier 4: Housekeeping

17. Section 2 says "four kinds of state" and "all four rows," but the table has five rows.
18. Section 5.1 says "use `Color.Resolved` as the storage type," then defines its own struct. The intent (mirror `Color.Resolved`, convert at the UI layer) should be stated plainly.
19. The roadmap puts `paperContentMode` in Phase 3, but layout is foundational, and item 5 says it is the riskiest assumption. Move it to Phase 0/2.
20. The status line still says v1.1. Bump it when these fixes land.

---

## What holds up well

- **Option E's sorting of state by kind.** The rows table is the strongest idea in the plan and survived every revision today.
- **Tools as a `Codable` enum.** This is low risk, high payoff, and independent of every PaperKit unknown.
- **The private coordinator.** It is the right home for all the density, and the loop-prevention token scheme is correct.
- **Paper size in points on the markup**, and **`Image`-style content modes**. Both are clean and well argued.

---

# Review 2: PaperKit coverage audit

**Reviewed:** PLAN.md v1.13 on 2026-11-01, against the documented PaperKit API (`PaperMarkup`, `PaperMarkupViewController`, `FeatureSet`) and the iOS 27 PencilKit additions from WWDC26 session 203.

**Verdict:** The architecture covers PaperKit well. The gaps are surface area: several documented capabilities have no public path through our API, and one gap (revealing a search result) contradicts a decision we made earlier.

## Tier 1: Missing capabilities that most apps will need

### 1. Revealing a rect, which search now requires
Section 4.8 says search results can be jumped to with `setContentVisibleFrame`, but programmatic zoom and scroll are "out of v1." Search now provides the real use case we said we'd wait for. Options:
- **`.paperScrollPosition($position)`**, mirroring SwiftUI's `ScrollPosition`: the app calls `position.scrollTo(rect:)`, and the editor reports where it landed. This is Apple's current pattern, though we called it un-Swifty for zoom.
- **A one-shot reveal binding**, `.paperReveal($rect)`: the app sets a rect, the editor scrolls to it and sets the binding back to `nil`. It is simpler, but the editor writing back to clear it is unusual.
- **Recommendation:** `ScrollPosition`-style. Apple chose it for the same problem, and it covers "zoom to selection" too.

### 2. Defining elements to insert (`PaperElement.Template`)
`insert(_:in:)` takes a template the plan never defines. PaperKit's insert API is specific, and our type should mirror it:
```swift
public enum PaperElementTemplate: Hashable, Sendable {
    case shape(PaperShape, style: PaperShapeStyle, rotation: Angle = .zero)     // ShapeConfiguration
    case line(from: CGPoint, to: CGPoint, style: PaperShapeStyle,
              startArrow: Bool = false, endArrow: Bool = true)                   // insertNewLine markers
    case text(AttributedString, rotation: Angle = .zero)                          // insertNewTextbox
    case image(CGImage, rotation: Angle = .zero)                                  // insertNewImage
}
```
`PaperShapeStyle` wraps `ShapeConfiguration` (shape type, stroke and fill colors, line width) as a `Codable` value, the same treatment tools got.

### 3. Importing PencilKit drawings
`PaperMarkup.append(contentsOf: PKDrawing)` is the migration path for every existing PencilKit app, and we don't expose it. Add `Markup(drawing: PKDrawing, size:)` and `markup.append(_ drawing: PKDrawing)` in `PaperCore`. This could be the package's most persuasive feature for adopters.

### 4. Tool picker configuration
`.paperToolPicker(isPresented:)` only toggles visibility. Modern `PKToolPicker` lets apps choose which tools appear, add custom tool items, and add an accessory button. Add `.paperToolPicker(isPresented:tools:)` with a `PaperToolPickerItem` list (`.pen`, `.pencil`, `.marker`, `.eraser`, `.lasso`, `.ruler`, `.custom(...)`). Phase 0 should confirm what `PaperMarkupViewController`'s picker integration allows.

### 5. Touch modes, including trackpad and mouse
`.paperTouchPolicy` is described as Pencil-only versus finger. The controller actually exposes `directTouchMode`, `directTouchAutomaticallyDraws`, and `indirectPointerTouchMode` (trackpad and mouse on iPad and Mac). Replace it with `.paperInput(direct: .pencilOnly, pointer: .draw)` mapping to `TouchMode`, so pointer behavior isn't silently left at the default.

## Tier 2: Documented features with no path through our API

| PaperKit / PencilKit feature | Gap | Proposed surface |
|---|---|---|
| `selectedMarkup: PaperMarkup` | Can't copy, share, or export just the selection | `.onPaperSelectionChange { selection, selectedMarkup in }`, or a `selectedMarkup` read-back on the selection value |
| `contentsRenderFrame` | No "bounds of what's actually drawn" | `markup.contentBounds`, for crop-to-content thumbnails and zoom-to-content |
| `featureSet`, `removeContentUnsupported(by:)` | No way to check a markup against an older feature set before sharing | `markup.requiredFeatures` and `markup.removeUnsupported(by:)` |
| `adornments: [MarkupAdornment]`, `adornmentFrame(for:)` | Not covered at all | Needs Phase 0 investigation first. Likely a modifier taking adornment values |
| `transformContent(_:)` (general) | Only used for rotation | `paper.resize(to:scalingContent:)` for scaling a page and its ink together |
| iOS 27 programmatic erase with a `PKStrokePath` | Missing | `markup.erase(along: Path)` |
| iOS 27 `PKStrokePath` ↔ Bézier conversion | Strokes can't be drawn or hit-tested in SwiftUI | `stroke.path: Path` on `PaperStroke` |
| macOS `MarkupToolbarViewController` | Phase 5, no API sketched | `.paperToolbar()` on macOS, the counterpart of `.paperToolPicker` |

## Tier 3: SwiftUI integration gaps

- **Accessibility.** The editor and `PaperView` should provide a default `accessibilityLabel` from `indexableContent`, so VoiceOver can read a page's handwriting. Apps override it with `.accessibilityLabel` as usual. Nearly free, and easy to forget.
- **Spotlight and search indexing.** `paper.indexableContent` (a sync property using Apple's cached value) helps apps feed Core Spotlight without running full recognition.
- **Previews.** `PaperTesting` should ship `Paper.sample` values so `#Preview` works without a device or Pencil.
- **Apple Pencil Pro hover.** Hover previews come from PencilKit. Confirm PaperKit shows them by default, and document `.paperHoverPreview(_:)` only if it can be turned off.

## Deliberately left out
- **Substroke ranges and `renderGroupID`:** niche iOS 27 APIs. Expose them if an app asks.
- **A custom recognizer configuration API:** `preferredLanguages` can wait until someone needs a non-default language.

> **Update (2026-11-01):** Folded into PLAN.md v1.14, Section 4.9. Dropped at Jonathan's direction: PKDrawing import (Tier 1 #3) and feature-set compatibility checks (`requiredFeatures`, `removeUnsupported(by:)`).
