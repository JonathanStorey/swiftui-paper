import CoreGraphics
import Foundation
import PaperKit
import PencilKit
import SwiftUI

extension Paper {
    /// How a shape is stroked and filled. Always explicit: PaperKit's own default is a black fill,
    /// no stroke, and width 0, which is rarely what an app wants.
    public struct ShapeStyle: Codable, Hashable, Sendable {
        public var stroke: Paper.Color?
        public var fill: Paper.Color?
        public var lineWidth: CGFloat
        public var opacity: Double

        public init(stroke: Paper.Color? = .black, fill: Paper.Color? = nil, lineWidth: CGFloat = 2, opacity: Double = 1) {
            self.stroke = stroke
            self.fill = fill
            self.lineWidth = lineWidth
            self.opacity = opacity
        }

        /// A 2 pt black outline with no fill.
        public static let outline = ShapeStyle()

        /// Filled with `color`, no outline.
        public static func filled(_ color: Paper.Color) -> ShapeStyle {
            ShapeStyle(stroke: nil, fill: color, lineWidth: 0)
        }
    }

    /// The current selection in an editor. Bind it with `.paperSelection(_:)`.
    public struct Selection: Hashable, Sendable {
        public var ids: Set<Paper.Element.ID>

        public init() {
            ids = []
        }

        public init(_ ids: some Collection<Paper.Element.ID>) {
            self.ids = Set(ids)
        }

        public var isEmpty: Bool { ids.isEmpty }

        public mutating func clear() {
            ids.removeAll()
        }
    }

    // MARK: Inserting

    /// Adds a shape. New shapes stack above other shapes but below all ink: PaperKit always lists
    /// strokes last (SDK-FINDINGS F.2). `.line` draws corner to corner of `frame`; prefer `insertLine`.
    public mutating func insertShape(_ shape: Paper.Shape, style: Paper.ShapeStyle, in frame: CGRect, rotation: Angle = .zero) {
        let kitShape: ShapeMarkup.Shape = switch shape {
        case .rectangle: .rectangle
        case .roundedRectangle(let radius): .roundedRectangle(cornerRadius: radius)
        case .ellipse: .ellipse
        case .regularPolygon(let sides): .regularPolygon(sides: sides)
        case .star: .star
        case .chatBubble: ShapeMarkup.Shape(configurationType: .chatBubble)
        case .arrow: ShapeMarkup.Shape(configurationType: .arrowShape)
        case .line: .line(start: .zero, end: CGPoint(x: frame.width, y: frame.height))
        }
        var element = ShapeMarkup(
            shape: .rectangle, frame: frame, rotation: rotation.radians,
            fillColor: style.fill?.cgColor, strokeColor: style.stroke?.cgColor,
            lineWidth: style.lineWidth, opacity: style.opacity
        )
        // `shape` is in units of the frame's shorter side; `shapeScaled` is in points (SDK-FINDINGS G).
        element.shapeScaled = kitShape
        markup.subelements.append(element)
    }

    /// Adds a straight line, with optional arrowheads. Only the style's stroke color, width, and opacity apply.
    public mutating func insertLine(from start: CGPoint, to end: CGPoint, style: Paper.ShapeStyle, startArrow: Bool = false, endArrow: Bool = false) {
        var updated = markup
        let before = Set(updated.subelements.ids)
        // PaperKit's own line insertion handles the frame-relative endpoint encoding.
        updated.insertNewLine(
            configuration: ShapeConfiguration(type: .line, fillColor: nil, strokeColor: (style.stroke ?? .black).cgColor, lineWidth: style.lineWidth),
            from: start, to: end, startMarker: startArrow, endMarker: endArrow
        )
        if style.opacity != 1, let id = updated.subelements.ids.first(where: { !before.contains($0) }),
           var line = updated.subelements[id] as? ShapeMarkup {
            line.opacity = style.opacity
            updated.subelements[id] = line
        }
        markup = updated
    }

    /// Adds a text box: a rectangle shape holding attributed text.
    public mutating func insertText(_ text: AttributedString, in frame: CGRect, rotation: Angle = .zero) {
        markup.insertNewTextbox(attributedText: text, frame: frame, rotation: rotation.radians)
    }

    /// Adds an image, stretched to `frame`.
    public mutating func insertImage(_ image: CGImage, in frame: CGRect, rotation: Angle = .zero) {
        markup.insertNewImage(image, frame: frame, rotation: rotation.radians)
    }

    // MARK: Removing

    /// Removes elements, including locked ones. Missing IDs are ignored.
    public mutating func remove(_ ids: some Collection<Paper.Element.ID>) {
        let ids = Set(ids.map(\.raw))
        guard !ids.isEmpty else { return }
        var updated = markup
        for id in ids {
            // `removeAll(where:)` skips strokes (SDK-FINDINGS F.3); `removeStroke(for:)` is the stroke API.
            if case .stroke(let uuid) = id {
                updated.subelements.removeStroke(for: uuid)
            } else {
                updated.subelements.removeElement(for: id)
            }
        }
        markup = updated
    }

    // MARK: Text matches

    /// Where text came from. Recognition arrives in Phase 4; the types are here for `scrollTo(match:)`.
    public enum TextSource: Hashable, Sendable {
        /// Editable ink.
        case handwriting
        /// Editable text boxes.
        case typed
        /// Any locked element.
        case locked
        /// The PDF text layer or OCR of the background.
        case background

        public struct Set: OptionSet, Hashable, Sendable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }

            public static let handwriting = Set(rawValue: 1 << 0)
            public static let typed = Set(rawValue: 1 << 1)
            public static let locked = Set(rawValue: 1 << 2)
            public static let background = Set(rawValue: 1 << 3)
            public static let editable: Set = [.handwriting, .typed]
            public static let all: Set = [.handwriting, .typed, .locked, .background]
        }
    }

    /// A search hit, in page coordinates.
    public struct TextMatch: Hashable, Sendable {
        public let text: String
        public let bounds: CGRect
        public let source: TextSource
        /// Empty for background matches.
        public let elementIDs: [Paper.Element.ID]

        init(text: String, bounds: CGRect, source: TextSource, elementIDs: [Paper.Element.ID] = []) {
            self.text = text
            self.bounds = bounds
            self.source = source
            self.elementIDs = elementIDs
        }
    }
}
