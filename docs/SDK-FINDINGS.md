# SDK Findings (Phase 1)

**Date:** 2026-11-01 · **Toolchain:** Xcode 27.0 (27A266a), Swift 6.4 · **SDKs:** iOS 27.0, iOS Simulator 27.0, macOS 27.0, visionOS 27.0

This resolves the **(verify)** items in [PLAN.md](PLAN.md) v2.0 against the shipped `.swiftinterface` files and runtime tests. Declarations are quoted verbatim, with module qualifiers (`PaperKit::`, `CoreFoundation::` and so on) removed for readability.

Sources:

- `iPhoneOS.sdk/.../PaperKit.framework/Modules/PaperKit.swiftmodule/arm64e-apple-ios.swiftinterface` (PaperKit user-module-version 379)
- `iPhoneOS.sdk/.../PencilKit.framework/Modules/PencilKit.swiftmodule/arm64e-apple-ios.swiftinterface` (616.100) and the PencilKit ObjC headers
- the macOS and visionOS interfaces of both frameworks, for platform differences

Runtime answers come from `Tests/PaperUITests/MarkupTests.swift` (`PaperKitBehaviorTests`). They ran on macOS 27 and on an iPad Pro 11-inch (M5) iOS 27.0 simulator with identical results.

---

## Summary: PLAN.md (verify) items

| PLAN.md | Item | Verdict | Answer |
|---|---|---|---|
| §2.1 L96 | `contentView` follows zoom and scroll | **Unknown** | `contentView: UIView? { get set }` exists on all platforms. Following zoom needs a UI run, so it stays a Phase 2 first task |
| §3.1 L140 | `paperSelection` setter | **Confirmed** | `selection: Set<MarkupOrderedSet.ElementID> { get set }` on iOS, macOS, visionOS 27. `selectedMarkup` is also `get set` |
| §3.2 L165, §4.8 L481 | `PaperAdornment` shape | **Changed (now known)** | `MarkupAdornment` = `id: UUID`, `anchor`, `imageConfiguration`, `dragRegion`, `scalesWithZoom`. See [B.4](#b4-adornments) |
| §4.2 L277 | Ink readable via `subelements` | **Confirmed** | `subelements.strokes: [PKStroke]`, and `subscript(id: UUID) -> PKStroke?`. IDs survive `dataRepresentation` (tested) |
| §4.2 L284 | `remove(_:)` | **Confirmed** | `subelements` is `get set _modify`, and `MarkupOrderedSet` has `removeElement(for:)`, `removeStroke(for:)`, `remove(at:)`, `removeAll(where:)` (tested) |
| §4.5 L388 | `PaperShape` cases | **Changed** | Cases are `rectangle, ellipse, line, chatBubble, roundedRectangle, regularPolygon, star, arrowShape`. There is no `triangle` (use `regularPolygon` with 3 sides). `speechBubble` is called `chatBubble`. `arrowShape` is new |
| §4.8 L472 | `PaperFeatures.Feature` | **Confirmed (now known)** | `images, stickers, loupes, links, shapeFills, shapeStrokes, shapeOpacity, text, drawing`. `FeatureSet` also has `shapes`, `inks`, `lineMarkerPositions` and `colorMaximumLinearExposure` |
| §4.8 L479 | `PaperTouchMode` ↔ `TouchMode` | **Changed** | `TouchMode` has only `.selection` and `.drawing`. "Automatic" is a separate `directTouchAutomaticallyDraws: Bool`. macOS has neither direct-touch property |
| §5.6 L555 | `.typed` from `subelements` | **Confirmed, with a twist** | There is no text element type. `insertNewTextbox` creates a `ShapeMarkup` (rectangle) whose `attributedText` holds the text (tested). Any shape can carry text |
| §6.2 L590 | `bounds` settable | **Confirmed** | `bounds: CGRect { get set }`. Setting it keeps content and stroke IDs (tested). No fallback needed |

### Other things that affect the plan

1. **No erase API on `PaperMarkup`.** Erasing exists only on `PKDrawing` (`erasePath` / `erasingPath`). `Markup.erase(along:width:)` has to pull `subelements.strokes` into a `PKDrawing`, erase, and write the result back. An erased stroke is **split into new strokes with new IDs** (tested: 1 stroke became 2 pieces, and neither kept the original ID). So stroke IDs are stable through save/load and `append`, but not through erasing.
2. **`append(contentsOf: PKDrawing)` reassigns stroke IDs** (tested). `subelements.append(PKStroke)` and `append(contentsOf: PaperMarkup)` keep IDs and order (tested). PKDrawing import is out of scope anyway.
3. **`PKStrokePath.id` is a different UUID from `PKStroke.id`** (tested). `PaperStroke.ID` must wrap `PKStroke.id`, which is the value used in `ElementID.stroke(UUID)`.
4. **`roundedRectangle` reads back as `.rectangle`** with a `cornerRadius`. `ShapeMarkup.Shape` (the readable form) has 7 cases. Rounded corners are a parameter of `.rectangle`.
5. **`ShapeConfiguration` defaults** are `fillColor` black, `strokeColor` nil and `lineWidth` 0. `PaperShapeStyle` must always set all three explicitly.
6. **Element types.** `MarkupOrderedSet.ElementID` has the cases `shape`, `image`, `link`, `loupe` and `stroke(UUID)`. `PaperElement.Kind` should gain `link` and `loupe`. `text` is a shape with text, not its own kind.
7. **Per-element interaction locks.** Every `Markup` element has `allowedInteractions: MarkupInteractions` (`rotate, resize, delete, move, style, select, all, readOnly`). This is worth weighing for the `locked` layer: it might replace the render-to-PDF approach in §2.1.
8. **`FeatureSet.latest == .version1`** in this SDK, and its `colorMaximumLinearExposure` defaults to `1.0`. `inks` includes `reed` (`com.apple.ink.reedcalligraphy`, iOS 26), which `InkKind` in §4.4 doesn't list.
9. **macOS controller gaps.** The macOS `PaperMarkupViewController` (`NSViewController`) has no `directTouchMode`, `directTouchAutomaticallyDraws`, `isRulerActive`, `undoManager` override or `supportedFeatureSet` getter. Its `ScrollConfiguration` has no `adjustedContentInset` or `contentInsetAdjustmentBehavior`. There is no `MarkupEditViewController` (it uses `MarkupToolbarViewController`). visionOS has the same members as iOS.
10. **`MarkupAdornment.ImageConfiguration` takes `UIImage` / `UIColor`.** A `Sendable`, cross-platform `PaperAdornment` should store a system image name or `CGImage` and convert.
11. **`PKStrokeRecognizer` takes a whole `PKDrawing`** (`updateDrawing(_:)`), not stroke deltas. "Incremental by stroke ID" in §5.6 is the recognizer's internal job. We call `updateDrawing(PKDrawing(strokes: subelements.strokes))` and query `recognizedText(strokeIDs:)`.

---

## A. PaperMarkup

### A.1 Core

```swift
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct PaperMarkup : Sendable, Equatable {
  public init(dataRepresentation: Data) throws
  public init(bounds: CGRect)
  public func dataRepresentation() async throws -> Data
  public var indexableContent: String? { get async }
  public var bounds: CGRect { get set }
  public var contentsRenderFrame: CGRect { get }
  nonisolated(nonsending) public func draw(in context: CGContext, frame: CGRect, options: RenderingOptions = RenderingOptions()) async
  public mutating func append(contentsOf other: PaperMarkup)
  public mutating func append(contentsOf drawing: PKDrawing)
  public mutating func transformContent(_ transform: CGAffineTransform)
  public mutating func insertNewShape(configuration: ShapeConfiguration, frame: CGRect, rotation: CGFloat = 0)
  public mutating func insertNewLine(configuration: ShapeConfiguration, from start: CGPoint, to end: CGPoint, startMarker lineStartMarker: Bool = false, endMarker lineEndMarker: Bool = false)
  public mutating func insertNewTextbox(attributedText: NSAttributedString, frame: CGRect, rotation: CGFloat = 0)
  public mutating func insertNewTextbox(attributedText: AttributedString, frame: CGRect, rotation: CGFloat = 0)
  public mutating func insertNewImage(_ image: CGImage, frame: CGRect, rotation: CGFloat = 0)
  public var featureSet: FeatureSet { get }
  public mutating func removeContentUnsupported(by featureSet: FeatureSet)
}
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension PaperMarkup : Identifiable {
  public var id: MarkupID<PaperMarkup> { get set }
  public var backgroundColor: CGColor? { get set }
  public var subelements: MarkupOrderedSet { get set _modify }
}
```

- `bounds`: **get/set**.
- `indexableContent` is `get async`, so `Markup.indexableContent` must be async too. PLAN §4.2 declares it as a sync `{ get }`.
- There is no remove or delete method on `PaperMarkup` itself. Removal goes through `subelements`.
- Errors: `enum MarkupError { case incorrectFormat, malformedData, incompatibleFormatTooNew }`.
- `UTType.paperkit` exists (iOS/macOS/visionOS 26).

### A.2 MarkupOrderedSet

```swift
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
public struct MarkupOrderedSet : Sendable {
  public typealias Element = any Markup
  public init()
  @discardableResult public mutating func append(_ item: Element) -> (inserted: Bool, index: Int)
  public mutating func append(contentsOf elements: some Sequence<Element>)
  @discardableResult public mutating func insert(_ item: Element, at index: Int) -> (inserted: Bool, index: Int)
  public func contains(_ element: Element) -> Bool
  public func firstIndex(of element: Element) -> Int?
  @discardableResult public mutating func remove(_ member: Element) -> Element?
  @discardableResult public mutating func updateOrAppend(_ item: Element) -> Element?
  @discardableResult public mutating func removeElement(for id: ElementID) -> Element?
  @discardableResult public mutating func removeElement<T>(for id: MarkupID<T>) -> T? where T : Markup
  @discardableResult public mutating func removeStroke(for id: UUID) -> PKStroke?
  public subscript(id: ElementID) -> Element? { get set }
  public subscript<T>(id: MarkupID<T>) -> T? where T : Markup { get set }
  public subscript(id: UUID) -> PKStroke? { get set }
  public var count: Int { get }
}
extension MarkupOrderedSet : BidirectionalCollection, RandomAccessCollection { ... }   // Index = Int
extension MarkupOrderedSet {
  @discardableResult public mutating func remove(at index: Int) -> Element
  public mutating func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows
  public subscript(index: Int) -> Element { get }
}
extension MarkupOrderedSet {
  public struct ElementIDs : RandomAccessCollection { ... }   // Element = ElementID
  public var ids: ElementIDs { get }
  public var strokes: [PKStroke] { get }
}
```

`MarkupOrderedSet` is **mutable**, can be read in order, and is addressable by ID.

### A.3 IDs

```swift
public struct MarkupID<Element> : Sendable, Hashable, RawRepresentable, Codable {
  public init() where Element : Markup
  public init?(rawValue: Data)
  public var rawValue: Data { get }
}
extension MarkupOrderedSet {
  public enum ElementID : Sendable, Hashable, RawRepresentable, Codable {
    case shape(MarkupID<ShapeMarkup>)
    case image(MarkupID<ImageMarkup>)
    case link(MarkupID<LinkMarkup>)
    case loupe(MarkupID<LoupeMarkup>)
    case stroke(UUID)
    public init<T>(_ id: MarkupID<T>) where T : Markup
    public init(_ id: UUID)
    public init?(rawValue: Data)
    public var rawValue: Data { get }
  }
}
```

`ElementID` is `Codable` and has `Data` raw values, so `PaperElement.ID` can wrap it directly and stay `Codable`. Strokes are identified by `PKStroke.id` (UUID).

### A.4 Element types (the `Markup` protocol)

```swift
public protocol Markup : Sendable {
  var elementID: MarkupOrderedSet.ElementID { get }
  var renderFrame: CGRect { get }
  mutating func applyTransform(_ transform: CGAffineTransform)
  var featureSet: FeatureSet { get }
  mutating func removeContentUnsupported(by featureSet: FeatureSet) -> Bool
  var frame: CGRect { get set }
  var rotation: CGFloat { get set }
  var allowedInteractions: MarkupInteractions { get set }
}
```

Conformers: `PKStroke` (via extension), `ShapeMarkup`, `ImageMarkup`, `LinkMarkup`, `LoupeMarkup`. **Name clash:** PaperKit's protocol is called `Markup`, and so is our struct. Inside our module, refer to PaperKit's as `PaperKit.Markup`.

`ShapeMarkup` (abridged):

```swift
public struct ShapeMarkup : Markup, Identifiable {
  public var id: MarkupID<ShapeMarkup>
  public init(configuration: ShapeConfiguration, frame: CGRect, rotation: CGFloat = 0.0)
  public init(shape: ShapeMarkup.Shape, frame: CGRect, rotation: CGFloat = 0.0, fillColor: CGColor? = nil, strokeColor: CGColor? = nil, lineWidth: CGFloat = 1.0, opacity: CGFloat = 1.0, startLineMarker: ShapeMarkup.LineMarker = .none, endLineMarker: ShapeMarkup.LineMarker = .none, attributedText: AttributedString = Foundation.AttributedString(), allowedInteractions: MarkupInteractions = .all, autoresizing: MarkupAutoresizing = [], id: MarkupID<ShapeMarkup> = MarkupID())
  public var fillColor: CGColor? { get set }
  public var strokeColor: CGColor? { get set }
  public var lineWidth: CGFloat { get _modify }
  public var opacity: CGFloat { get _modify }
  public var shape: ShapeMarkup.Shape { get set }
  public var shapeScaled: ShapeMarkup.Shape { get set }
  public enum LineMarker : Sendable { case none, arrow }
  public var startLineMarker: ShapeMarkup.LineMarker { get set }
  public var endLineMarker: ShapeMarkup.LineMarker { get set }
  public var attributedText: AttributedString { get set }
  public var autoresizing: MarkupAutoresizing { get set }
}
extension ShapeMarkup {
  public enum Shape : Sendable, Hashable {
    case rectangle(Rectangle)          // cornerRadius: CGFloat?
    case ellipse(Ellipse)
    case line(Line)                    // start, control: CGPoint?, end
    case chatBubble(ChatBubble)        // tailLocation, tailAngle
    case regularPolygon(RegularPolygon)// sides: Int
    case star(Star)                    // points: Int, innerRadius: CGFloat
    case arrowShape(ArrowShape)        // cornerPoint: CGPoint
    public var configurationType: ShapeConfiguration.Shape { get }
    public var path: CGPath { get }
    ...
  }
}
```

`ImageMarkup`: `image: CGImage? { get async }`, `opacity`, `contentsBounds`, `orientation`, `accessibilityDescription`, `replaceImage(with:)`. `LinkMarkup`: `url: URL`. `LoupeMarkup`: `magnification`, `strokeColor`, `lineWidth`.

`PKStroke` as a `Markup` adds `frame { get set }`, `rotation { get set }` and `allowedInteractions { get set }`.

### A.5 ShapeConfiguration

```swift
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
public struct ShapeConfiguration {
  public var type: ShapeConfiguration.Shape
  public var fillColor: CGColor?
  public var strokeColor: CGColor?
  public var lineWidth: CGFloat
  public init(type: ShapeConfiguration.Shape, fillColor: CGColor? = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), strokeColor: CGColor? = nil, lineWidth: CGFloat = 0)
}
extension ShapeConfiguration {
  public enum Shape : Hashable, CaseIterable, Sendable {
    case rectangle, ellipse, line, chatBubble, roundedRectangle, regularPolygon, star, arrowShape
  }
}
```

`ShapeConfiguration` itself is **not** `Sendable` (it holds `CGColor`). Build it at the call site; don't store it.

Suggested `PaperShape` (replacing §4.5): `rectangle(cornerRadius: CGFloat? = nil)`, `ellipse`, `polygon(sides: Int)`, `star(points: Int, innerRadius: CGFloat)`, `speechBubble` (→ `chatBubble`), `arrow` (→ `arrowShape`). Inserting through `ShapeMarkup(shape:...)` into `subelements` reaches every parameter. `insertNewShape(configuration:)` only reaches the preset cases.

### A.6 RenderingOptions

```swift
public struct RenderingOptions : Equatable, Sendable {
  public var darkUserInterfaceStyle: Bool
  public var rightToLeftLayoutDirection: Bool
  public init(traitCollection: UITraitCollection)
  public init(darkUserInterfaceStyle: Bool = false, layoutRightToLeft: Bool = false)
}
```

---

## B. PaperMarkupViewController (iOS / visionOS)

```swift
@MainActor @preconcurrency public class PaperMarkupViewController : UIViewController, PKToolPickerObserver {
  public init(markup: PaperMarkup? = nil, supportedFeatureSet: FeatureSet)
  weak public var delegate: (any Delegate)? { get set _modify }
  public var markup: PaperMarkup? { get set }
  override public var undoManager: UndoManager? { get }
  public var contentView: UIView? { get set _modify }
  public var isEditable: Bool { get set _modify }
  public var drawingTool: any PKTool { get set _modify }
  public var directTouchMode: TouchMode { get set _modify }
  public var directTouchAutomaticallyDraws: Bool { get set _modify }
  public var indirectPointerTouchMode: TouchMode { get set _modify }
  public func suggestedFrameForInserting(contentInFrame frame: CGRect) -> CGRect
  public var selectedMarkup: PaperMarkup { get set }
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  public var selection: Set<MarkupOrderedSet.ElementID> { get set _modify }
  @available(iOS 27.0, visionOS 27.0, *)
  public var scrollConfiguration: ScrollConfiguration { get }
  public var isRulerActive: Bool { get set _modify }
  public var contentVisibleFrame: CGRect { get set }
  public func setContentVisibleFrame(_ rect: CGRect, animated: Bool)
  public var zoomRange: ClosedRange<CGFloat> { get set _modify }
  public var supportedFeatureSet: FeatureSet { get }
  @available(iOS 27.0, visionOS 27.0, *)
  public var adornments: [MarkupAdornment] { get set _modify }
  @available(iOS 27.0, visionOS 27.0, *)
  public func adornmentFrame(for id: UUID) -> CGRect?
  @objc public func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker)
  @objc public func toolPickerIsRulerActiveDidChange(_ toolPicker: PKToolPicker)
}
extension PaperMarkupViewController : nonisolated Observable {}
```

`showsVerticalScrollIndicator` and `showsHorizontalScrollIndicator` are deprecated in 27 and renamed to `scrollConfiguration.visibleScrollIndicators`.

### B.1 TouchMode

```swift
extension PaperMarkupViewController {
  public enum TouchMode : Hashable, Sendable {
    case selection
    case drawing
  }
}
```

Mapping for `PaperTouchMode`:

| PaperTouchMode | `direct:` (iOS/visionOS) | `pointer:` |
|---|---|---|
| `.automatic` | `directTouchAutomaticallyDraws = true` | leave the controller default |
| `.draw` | `directTouchAutomaticallyDraws = false`, `directTouchMode = .drawing` | `.drawing` |
| `.navigate` | `directTouchAutomaticallyDraws = false`, `directTouchMode = .selection` | `.selection` |

How `directTouchAutomaticallyDraws` interacts with `directTouchMode` is not documented, so this needs a check on device. On macOS only `pointer:` applies.

### B.2 ScrollConfiguration

```swift
@available(iOS 27.0, visionOS 27.0, *)
final public class ScrollConfiguration {     // Observable
  final public var visibleScrollIndicators: Axis { get set }
  final public var bounces: Axis { get set }
  final public var alwaysBounces: Axis { get set }
  final public var bouncesZoom: Bool { get set }
  final public var contentInset: UIEdgeInsets { get set }
  final public var adjustedContentInset: UIEdgeInsets { get }                       // iOS/visionOS only
  final public var contentInsetAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior { get set }  // iOS/visionOS only
  final public var isScrollEnabled: Bool { get set }
  final public var isDirectionalLockEnabled: Bool { get set }
  final public var scrollsToTop: Bool { get set }
  final public var verticalScrollIndicatorInsets: UIEdgeInsets { get set }
  final public var horizontalScrollIndicatorInsets: UIEdgeInsets { get set }
  final public var zoomScale: CGFloat { get set }
}
public struct Axis : OptionSet { static let horizontal, vertical, both }
```

`.scrollDisabled` maps to `isScrollEnabled`. `.scrollIndicators` maps to `visibleScrollIndicators`. `zoomScale` is settable, which helps the content-mode math.

### B.3 Delegate

```swift
public protocol Delegate : AnyObject {
  func paperMarkupViewControllerDidChangeMarkup(_:)
  func paperMarkupViewControllerDidChangeSelection(_:)
  func paperMarkupViewControllerDidBeginDrawing(_:)
  func paperMarkupViewControllerDidChangeContentVisibleFrame(_:)
  @available(iOS 27.0, visionOS 27.0, *)
  func paperMarkupViewController(_:didTapAdornmentWithID id: UUID)
  @available(iOS 27.0, visionOS 27.0, *)
  func paperMarkupViewController(_:willUpdateAdornmentWithID id: UUID, toProposedAnchor proposedAnchor: MarkupAdornment.Anchor) -> MarkupAdornment.Anchor?
  @available(iOS 27.0, visionOS 27.0, *)
  func paperMarkupViewController(_:didUpdateAdornmentWithID id: UUID, toAnchor anchor: MarkupAdornment.Anchor)
}
```

All methods have default implementations. This fills the §7 "Delegate events: Partial" gap: markup change, selection change, drawing began, visible-frame change, and three adornment events.

### B.4 Adornments

```swift
public struct MarkupAdornment : Equatable, Hashable, Identifiable, Sendable, Codable {
  public var id: UUID
  public var anchor: Anchor
  public var imageConfiguration: ImageConfiguration
  public var dragRegion: DragRegion
  public var scalesWithZoom: Bool
  public init(id: UUID = UUID(), anchor: Anchor, imageConfiguration: ImageConfiguration = .default, dragRegion: DragRegion = .canvas, scalesWithZoom: Bool = false)
}
extension MarkupAdornment {
  public struct Anchor : Hashable, Sendable, CustomStringConvertible, Codable {
    public static func canvas(location: CGPoint) -> Anchor
    public func location(in markup: PaperMarkup) -> CGPoint?
  }
  public struct ImageConfiguration : Hashable, Sendable, Codable {
    public static let `default`: ImageConfiguration
    public static func systemImage(_ name: String, tint: UIColor = .tintColor, size: CGSize? = nil, alignmentAnchor: CGPoint = .zero) -> ImageConfiguration
    public static func image(_ image: UIImage, alignmentAnchor: CGPoint = .zero) -> ImageConfiguration
  }
  public struct DragRegion : Hashable, Sendable, Codable {
    public static let fixed: DragRegion
    public static let canvas: DragRegion
  }
}
```

The only public anchor is `.canvas(location:)`. `Anchor.location(in:)` hints that element-attached anchors exist internally, but none are public. Suggested shape:

```swift
public struct PaperAdornment: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var location: CGPoint            // page coordinates
    public var systemImage: String?         // nil = default marker
    public var isDraggable: Bool            // .canvas vs .fixed
    public var scalesWithZoom: Bool
}
```

Plus `onPaperAdornmentTap` and a binding for drags. The binding comes from the will/did-update delegate methods.

### B.5 macOS differences

`PaperMarkupViewController : NSViewController`. It has `delegate`, `markup`, `init(markup:supportedFeatureSet:)`, `contentView: NSView?`, `isEditable`, `drawingTool`, `indirectPointerTouchMode`, `selection`, `selectedMarkup`, `scrollConfiguration` (no `adjustedContentInset` or `contentInsetAdjustmentBehavior`, and `NSEdgeInsets`), `contentVisibleFrame`, `setContentVisibleFrame`, `zoomRange`, `adornments`, `adornmentFrame(for:)` and `suggestedFrameForInserting`.

It is missing `directTouchMode`, `directTouchAutomaticallyDraws`, `isRulerActive`, the `undoManager` override, the `supportedFeatureSet` getter and `MarkupEditViewController`. It has `MarkupToolbarViewController` instead. The coordinator keeps its own copy of the feature set on macOS.

---

## C. FeatureSet

```swift
public struct FeatureSet : Equatable, Sendable {
  public var contentVersion: ContentVersion          // enum { case version1 }
  public var shapes: Set<ShapeConfiguration.Shape>
  public enum Feature : Hashable, CaseIterable, Sendable {
    case images, stickers, loupes, links, shapeFills, shapeStrokes, shapeOpacity, text, drawing
  }
  public var features: Set<Feature>
  public func contains(_ feature: Feature) -> Bool
  public mutating func insert(_ newFeature: Feature)
  public mutating func remove(_ feature: Feature)
  public var inks: Set<PKInkingTool.InkType>
  public struct LineMarkerPositions : OptionSet, Sendable, Hashable { static let plain, single, double, all }
  public var lineMarkerPositions: LineMarkerPositions
  public var colorMaximumLinearExposure: CGFloat
  public static var version1: FeatureSet { get }
  public static var latest: FeatureSet { get }
  public static var empty: FeatureSet { get }
  public func isSubset(of other: FeatureSet) -> Bool
}
```

Runtime: `.latest` contains all 9 features, all 8 shapes and 8 inks (including `reed`). `colorMaximumLinearExposure == 1.0`, and `.latest == .version1`.

`PaperFeatures.Feature` can mirror the 9 cases one to one. Shape and ink restriction could be exposed later as `PaperFeatures.shapes` / `.inks`.

---

## D. PencilKit (iOS 27 additions)

### D.1 Stroke identity

```swift
extension PKStroke : Identifiable {
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  public var id: UUID { get set }
}
public init(ink: PKInk, path: PKStrokePath, transform: CGAffineTransform = .identity, mask: UIBezierPath? = nil, randomSeed: UInt32 = UInt32.random(in: 0...UInt32.max), id: UUID = UUID(), renderGroupID: UUID? = nil, renderState: PKStroke.RenderState? = nil)

extension PKStrokePath : Identifiable {
  public init<T>(controlPoints: T, creationDate: Date, id: UUID) where T : Sequence, T.Element == PKStrokePoint
  public var id: UUID { get }
}
```

ObjC names: `PKStroke.strokeID` and `PKStrokePath.strokePathID`. The two IDs are independent (tested). Use `PKStroke.id`.

Also new: `PKStroke.renderGroupID`, `renderState`, `substroke(range:)`, `PKStrokePoint.lateralJitter`, `PKContentVersion.version5`, and `PKCanvasView.selection: Set<UUID>` (`selectedStrokeIDs`).

### D.2 PKStrokeRecognizer

```swift
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
final public actor PKStrokeRecognizer {
  public struct SearchResult {
    public let strokes: Set<UUID>
    public let bounds: CGRect
  }
  public static var supportedLanguages: Set<Locale.Language> { get }
  public static var recognitionVersion: Int { get }
  public init(preferredLanguages: [Locale.Language]? = nil)
  final public var drawing: PKDrawing { get }
  final public func updateDrawing(_ drawing: PKDrawing) async
  final public var languages: [Locale.Language] { get }
  final public var indexableContent: String? { get async }
  final public func recognizedText(strokeIDs: Set<UUID>? = nil) async -> String?
  final public func search(_ query: String, fullWordsOnly: Bool = false, caseMatchingOnly: Bool = false) async -> [SearchResult]
}
```

`SearchResult.bounds` maps directly onto `PaperTextMatch.bounds`. `search` returns no matched text, so `PaperTextMatch.text` is the query.

### D.3 Erasing

```swift
extension PKDrawing {
  @available(iOS 27.0, visionOS 27.0, *)   // also present in the macOS 27 interface
  public mutating func erasePath(_ eraserPath: PKStrokePath, mask: UIBezierPath? = nil, transform: CGAffineTransform = .identity)
  public func erasingPath(_ eraserPath: PKStrokePath, mask: UIBezierPath? = nil, transform: CGAffineTransform = .identity) -> PKDrawing
}
```

The eraser is a `PKStrokePath`, and its width comes from the point sizes. A cut stroke becomes new strokes with new IDs, recorded as `maskedPathRanges` on the pieces (tested). There is no `PaperMarkup` equivalent.

### D.4 Bézier conversion

```swift
extension PKStrokePath {
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
  public init(bezierPath: CGPath, creationDate: Date, pointProvider: (_ convertedPoint: ConvertedBezierPoint) -> PKStrokePoint)
  public struct ConvertedBezierPoint { index, pointCount, location: CGPoint, bezierSegmentIndex }
  public var bezierRepresentation: CGPath { get }
  public subscript(range: ClosedRange<CGFloat>) -> PKStrokePath { get }
}
```

`PaperStroke.path` is `bezierRepresentation` with `transform` applied. `erase(along: CGPath, width:)` builds its eraser with `init(bezierPath:creationDate:pointProvider:)`, setting `size` to `width`.

### D.5 Tool picker

There are no iOS 27 additions to `PKToolPicker`. Existing API:

```objc
@property (nonatomic, strong, nullable) UIBarButtonItem *accessoryItem API_AVAILABLE(ios(18.0), visionos(2.0));
- (instancetype)initWithToolItems:(NSArray<PKToolPickerItem *> *)items API_AVAILABLE(ios(18.0), visionos(2.0));
@property (nonatomic, copy) NSString *selectedToolItemIdentifier API_AVAILABLE(ios(18.0), visionos(2.0));
@property (class, nonatomic, nonnull, readonly) NSArray<PKToolPickerItem *> *defaultToolItems API_AVAILABLE(ios(26.0), visionos(26.0));
@property (nonatomic, assign) CGFloat colorMaximumLinearExposure API_AVAILABLE(ios(26.0), visionos(26.0));
```

```swift
extension PKToolPickerCustomItem {
  public struct Configuration {
    public var identifier: String
    public var name: String
    public var imageProvider: ((PKToolPickerCustomItem) -> UIImage)?
    public var viewControllerProvider: ((PKToolPickerCustomItem) -> UIViewController)?
    public var defaultWidth: CGFloat
    public var widthVariants: [CGFloat : UIImage]
    public var defaultColor: UIColor
    public var allowsColorSelection: Bool
    public var toolAttributeControls: ControlOptions    // none, width, opacity
    public init(identifier: String, name: String)
  }
}
```

`PKToolPickerItem.tool: (any PKTool)?` (iOS 26) helps map the selected item back to `PaperTool`. `PKToolPicker.colorMaximumLinearExposure` must match `FeatureSet.colorMaximumLinearExposure`.
