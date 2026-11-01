import PaperKit
import PencilKit

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

// MARK: - Tools

extension Paper.Tool {
    /// The PencilKit tool, or `nil` for a custom tool, which the picker supplies.
    var pkTool: (any PKTool)? {
        switch self {
        case .ink(let ink, let width):
            PKInkingTool(ink.kind.inkType, color: ink.color.platformColor, width: width)
        case .eraser(.vector):
            PKEraserTool(.vector)
        case .eraser(.bitmap(width: nil)):
            PKEraserTool(.bitmap)
        case .eraser(.bitmap(width: let width?)):
            PKEraserTool(.bitmap, width: width)
        case .lasso:
            PKLassoTool()
        case .custom:
            nil
        }
    }

    init?(_ tool: any PKTool) {
        switch tool {
        case let inking as PKInkingTool:
            guard let color = Paper.Color(inking.color.cgColor) else { return nil }
            self = .ink(Paper.Ink(kind: Paper.Ink.Kind(inking.inkType), color: color), width: inking.width)
        case let eraser as PKEraserTool:
            switch eraser.eraserType {
            case .vector: self = .eraser(.vector)
            case .bitmap: self = .eraser(.bitmap(width: nil))
            default: self = .eraser(.bitmap(width: eraser.width))   // .fixedWidthBitmap
            }
        case is PKLassoTool:
            self = .lasso
        default:
            return nil
        }
    }
}

extension Paper.Ink.Kind {
    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: .pen
        case .pencil: .pencil
        case .marker: .marker
        case .monoline: .monoline
        case .fountainPen: .fountainPen
        case .watercolor: .watercolor
        case .crayon: .crayon
        case .reed: .reed
        }
    }

    init(_ inkType: PKInkingTool.InkType) {
        self = switch inkType {
        case .pencil: .pencil
        case .marker: .marker
        case .monoline: .monoline
        case .fountainPen: .fountainPen
        case .watercolor: .watercolor
        case .crayon: .crayon
        case .reed: .reed
        default: .pen
        }
    }
}

extension Paper.Color {
    var platformColor: PlatformColor {
        #if os(macOS)
        NSColor(cgColor: cgColor) ?? .black
        #else
        UIColor(cgColor: cgColor)
        #endif
    }
}

// MARK: - Features

extension Paper.Features {
    var featureSet: FeatureSet {
        var set = FeatureSet.latest
        for feature in Feature.allCases where !contains(feature) {
            set.remove(feature.paperKitFeature)
        }
        set.inks = Set(inks.map(\.inkType))
        set.colorMaximumLinearExposure = maximumHDRExposure
        return set
    }
}

extension Paper.Features.Feature {
    var paperKitFeature: FeatureSet.Feature {
        switch self {
        case .drawing: .drawing
        case .text: .text
        case .images: .images
        case .stickers: .stickers
        case .shapeFills: .shapeFills
        case .shapeStrokes: .shapeStrokes
        case .shapeOpacity: .shapeOpacity
        case .links: .links
        case .loupes: .loupes
        }
    }
}
