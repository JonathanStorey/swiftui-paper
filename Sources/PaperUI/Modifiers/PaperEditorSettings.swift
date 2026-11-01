import SwiftUI

/// How the editor places the page in its frame when nothing is zoomed.
public enum PaperContentMode: Hashable, Sendable {
    /// The whole page is visible, letterboxed.
    case fit
    /// The page fills the frame and overflows along its relatively longer axis.
    case fill
    /// The page's width matches the frame. Scrolls vertically.
    case fitWidth
    /// The page's height matches the frame. Scrolls horizontally.
    case fitHeight
}

extension View {
    /// The tool the editor draws with. Picking a tool in the system picker writes back.
    public func paperTool(_ tool: Binding<Paper.Tool>) -> some View {
        environment(\.paperTool, tool)
    }

    /// Shows the system tool picker on iOS and visionOS, or the markup toolbar on macOS.
    /// Hiding the picker from the system UI writes back `false`.
    public func paperToolPicker(isPresented: Binding<Bool>) -> some View {
        environment(\.paperToolPickerIsPresented, isPresented)
    }

    /// What people can create in editors below this view. The default is `.latest`.
    public func paperFeatures(_ features: Paper.Features) -> some View {
        environment(\.paperFeatures, features)
    }

    /// How editors below this view place the page. The default is `.fit`, `.center`.
    ///
    /// The anchor sets the initial scroll position in overflowing modes, and where the letterbox space goes in `.fit`.
    public func paperContentMode(_ mode: PaperContentMode, anchor: UnitPoint = .center) -> some View {
        environment(\.paperContentPlacement, PaperContentPlacement(mode: mode, anchor: anchor))
    }

    /// How far people can zoom. `1` is the content mode's resting scale. The default is `1...4`.
    public func paperZoomRange(_ range: ClosedRange<CGFloat>) -> some View {
        environment(\.paperZoomRange, range)
    }
}

struct PaperContentPlacement: Hashable, Sendable {
    var mode: PaperContentMode
    var anchor: UnitPoint
}

extension EnvironmentValues {
    @Entry var paperTool: Binding<Paper.Tool>? = nil
    @Entry var paperToolPickerIsPresented: Binding<Bool>? = nil
    @Entry var paperFeatures: Paper.Features = .latest
    @Entry var paperContentPlacement = PaperContentPlacement(mode: .fit, anchor: .center)
    @Entry var paperZoomRange: ClosedRange<CGFloat> = 1...4
}
