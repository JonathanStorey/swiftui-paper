import CoreGraphics
import SwiftUI

// MARK: - Setting types

/// The editor's view of the page. Delivered by `onPaperGeometryChange`.
public struct PaperGeometry: Equatable, Sendable {
    /// 1 is the content mode's resting scale.
    public var zoomScale: CGFloat
    /// Page coordinates.
    public var visibleRect: CGRect
    /// The page's size on screen at the current zoom, in points.
    public var contentSize: CGSize
}

/// Scroll and zoom requests for an editor, and where it is now. Bind it with `.paperScrollPosition(_:)`.
///
/// Call the methods on the value; the editor carries out the latest request and writes back `visibleRect`.
public struct PaperScrollPosition: Hashable, Sendable {
    public init() {}

    /// The page rectangle the editor shows, in page coordinates. `nil` until the editor reports.
    public internal(set) var visibleRect: CGRect?

    var request: Request?

    struct Request: Hashable, Sendable {
        enum Target: Hashable, Sendable {
            case rect(CGRect, anchor: UnitPoint?, zoom: Bool)
            case match(Paper.TextMatch)
            case selection(Paper.Selection)
            case fit
        }
        let id = UUID()
        let target: Target
    }

    /// Scrolls `rect` into view. With `zoom`, it fills the view; without, the zoom stays and the
    /// anchor (default center) decides which part of `rect` lines up with the same part of the view.
    public mutating func scrollTo(rect: CGRect, anchor: UnitPoint? = nil, zoom: Bool = true) {
        request = Request(target: .rect(rect, anchor: anchor, zoom: zoom))
    }

    /// Reveals a search match at the current zoom.
    public mutating func scrollTo(match: Paper.TextMatch) {
        request = Request(target: .match(match))
    }

    /// Fits the selected elements in view.
    public mutating func scrollTo(selection: Paper.Selection) {
        request = Request(target: .selection(selection))
    }

    /// Returns to the content mode's resting placement.
    public mutating func zoomToFit() {
        request = Request(target: .fit)
    }
}

/// What a finger or pointer does on the canvas. Set with `.paperInput(direct:pointer:)`.
public enum PaperTouchMode: Hashable, Sendable {
    /// Finger: follow the system "Only Draw with Apple Pencil" setting. Pointer: PaperKit's default.
    case automatic
    /// Touches draw with the current tool.
    case draw
    /// Touches select and scroll; only Apple Pencil draws.
    case select
}

/// An app badge placed on the page, such as a comment marker. Bind a list with `.paperAdornments(_:onTap:)`.
public struct PaperAdornment: Identifiable, Hashable, Sendable {
    public enum Image: Hashable, Sendable {
        case `default`
        case systemImage(String)
        case image(CGImage)
    }

    /// Where people can drag the adornment.
    public enum DragRegion: Hashable, Sendable {
        /// Not draggable.
        case fixed
        /// Anywhere on the page. Drags write back `location`.
        case canvas
    }

    public let id: UUID
    /// Page coordinates.
    public var location: CGPoint
    public var image: Image
    public var dragRegion: DragRegion
    /// Whether the badge grows and shrinks with the page.
    public var scalesWithZoom: Bool

    public init(id: UUID = UUID(), location: CGPoint, image: Image = .default, dragRegion: DragRegion = .fixed, scalesWithZoom: Bool = false) {
        self.id = id
        self.location = location
        self.image = image
        self.dragRegion = dragRegion
        self.scalesWithZoom = scalesWithZoom
    }
}

// MARK: - Modifiers

extension View {
    /// The editor's selection, fully two-way. Locked elements are never selected.
    public func paperSelection(_ selection: Binding<Paper.Selection>) -> some View {
        environment(\.paperSelection, selection)
    }

    /// Scroll and zoom requests, and the visible rect written back.
    public func paperScrollPosition(_ position: Binding<PaperScrollPosition>) -> some View {
        environment(\.paperScrollPosition, position)
    }

    /// Apple's menu for inserting shapes, text, images, and signatures (iOS and visionOS).
    /// Dismissing it, or inserting something, writes back `false`. macOS has these in the markup toolbar.
    public func paperInsertionMenu(isPresented: Binding<Bool>) -> some View {
        environment(\.paperInsertionMenuIsPresented, isPresented)
    }

    /// App badges on the page. Dragging writes back positions; tapping calls `action`.
    public func paperAdornments(_ adornments: Binding<[PaperAdornment]>, onTap action: @escaping (_ id: PaperAdornment.ID) -> Void = { _ in }) -> some View {
        environment(\.paperAdornments, PaperAdornmentsConfiguration(adornments: adornments, onTap: action))
    }

    /// What finger and pointer touches do. Direct-touch settings don't exist on macOS and are ignored there.
    public func paperInput(direct: PaperTouchMode = .automatic, pointer: PaperTouchMode = .select) -> some View {
        environment(\.paperInput, PaperInputConfiguration(direct: direct, pointer: pointer))
    }

    /// Shows PencilKit's ruler on the canvas (iOS only; visionOS and macOS have no ruler).
    public func paperRulerActive(_ isActive: Bool) -> some View {
        environment(\.paperRulerActive, isActive)
    }

    /// A button at the end of the system tool picker (iOS and visionOS).
    public func paperToolPickerAccessory(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        environment(\.paperToolPickerAccessory, PaperToolPickerAccessory(title: title, systemImage: systemImage, action: action))
    }

    /// Fires when the transformed geometry changes, with the old and new values. Not called for the
    /// first report, which sets the starting value.
    public func onPaperGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (PaperGeometry) -> T,
        action: @escaping (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        modifier(GeometryChangeModifier(transform: transform, action: action))
    }

    /// Fires when the selection changes, with the selected content as its own `Paper`, ready to copy or share.
    public func onPaperSelectionChange(perform action: @escaping (_ selection: Paper.Selection, _ selectedContent: Paper) -> Void) -> some View {
        transformEnvironment(\.paperEvents) { $0.selection.append(action) }
    }

    /// Fires when a stroke starts.
    public func onPaperDrawingBegan(perform action: @escaping () -> Void) -> some View {
        transformEnvironment(\.paperEvents) { $0.drawingBegan.append(action) }
    }
}

// MARK: - Environment

struct PaperInputConfiguration: Hashable, Sendable {
    var direct: PaperTouchMode
    var pointer: PaperTouchMode
}

/// Closures from the app. The editor calls them on the main actor only.
struct PaperAdornmentsConfiguration: @unchecked Sendable {
    var adornments: Binding<[PaperAdornment]>
    var onTap: (PaperAdornment.ID) -> Void
}

struct PaperToolPickerAccessory: @unchecked Sendable {
    var title: LocalizedStringKey
    var systemImage: String
    var action: () -> Void
}

/// Event handlers from every `onPaper…` modifier above an editor. Called on the main actor only.
struct PaperEvents: @unchecked Sendable {
    var geometry: [(PaperGeometry) -> Void] = []
    var selection: [(Paper.Selection, Paper) -> Void] = []
    var drawingBegan: [() -> Void] = []
}

extension EnvironmentValues {
    @Entry var paperSelection: Binding<Paper.Selection>? = nil
    @Entry var paperScrollPosition: Binding<PaperScrollPosition>? = nil
    @Entry var paperInsertionMenuIsPresented: Binding<Bool>? = nil
    @Entry var paperAdornments: PaperAdornmentsConfiguration? = nil
    @Entry var paperInput = PaperInputConfiguration(direct: .automatic, pointer: .select)
    @Entry var paperRulerActive = false
    @Entry var paperToolPickerAccessory: PaperToolPickerAccessory? = nil
    @Entry var paperEvents = PaperEvents()
}

/// Keeps the last transformed value per modifier, so `action` fires only on change.
private struct GeometryChangeModifier<T: Equatable>: ViewModifier {
    let transform: (PaperGeometry) -> T
    let action: (T, T) -> Void
    @State private var last = LastValue()

    final class LastValue {
        var value: Any?
    }

    func body(content: Content) -> some View {
        content.transformEnvironment(\.paperEvents) { [last, transform, action] events in
            events.geometry.append { geometry in
                let new = transform(geometry)
                let old = last.value as? T
                last.value = new
                if let old, old != new { action(old, new) }
            }
        }
    }
}
