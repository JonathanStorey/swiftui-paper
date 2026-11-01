import PencilKit

/// An item in the system tool picker. Pass a list to `.paperToolPicker(isPresented:items:)`.
public enum PaperToolPickerItem: Hashable, Sendable {
    case ink(Paper.Ink.Kind)
    case eraser(Paper.Eraser)
    case lasso
    /// Not available on visionOS, where it is left out of the picker.
    case ruler
    /// An app tool. Selecting it sets the tool binding to `.custom(id:)`.
    case custom(id: String, name: String, systemImage: String)

    /// The picker PencilKit shows by default: every ink, the eraser, the lasso, and the ruler.
    public static let standard: [PaperToolPickerItem] =
        Paper.Ink.Kind.allCases.map(PaperToolPickerItem.ink) + [.eraser(.vector), .lasso, .ruler]
}

#if !os(macOS)
import UIKit

extension PaperToolPickerItem {
    /// `nil` for the ruler on visionOS, which has no ruler.
    var pkItem: PKToolPickerItem? {
        switch self {
        case .ink(let kind):
            PKToolPickerInkingItem(type: kind.inkType)
        case .eraser(.vector):
            PKToolPickerEraserItem(type: .vector)
        case .eraser(.bitmap(width: nil)):
            PKToolPickerEraserItem(type: .bitmap)
        case .eraser(.bitmap(width: let width?)):
            PKToolPickerEraserItem(type: .bitmap, width: width)
        case .lasso:
            PKToolPickerLassoItem()
        case .ruler:
            #if os(visionOS)
            nil
            #else
            PKToolPickerRulerItem()
            #endif
        case .custom(let id, let name, let systemImage):
            {
                var configuration = PKToolPickerCustomItem.Configuration(identifier: id, name: name)
                configuration.imageProvider = { _ in UIImage(systemName: systemImage) ?? UIImage() }
                return PKToolPickerCustomItem(configuration: configuration)
            }()
        }
    }
}
#endif
