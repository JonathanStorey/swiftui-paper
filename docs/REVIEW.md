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
