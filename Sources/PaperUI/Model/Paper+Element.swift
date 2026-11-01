import CoreGraphics
import Foundation
import PaperKit
import PencilKit
import SwiftUI

extension Paper {
    /// A snapshot of one element on the page. Edit elements through `Paper`.
    public struct Element: Identifiable, Hashable, Sendable {
        /// Wraps PaperKit's `MarkupOrderedSet.ElementID`. Stable through saving and `append(_:)`.
        public struct ID: Hashable, Codable, Sendable {
            let raw: MarkupOrderedSet.ElementID
        }

        public enum Kind: Hashable, Sendable {
            case stroke(Paper.Stroke.ID)
            case shape(Paper.Shape)
            /// A rectangle shape holding attributed text.
            case text
            case image
            case link
            case loupe
        }

        public let id: ID
        public let kind: Kind
        public let frame: CGRect
        /// True when the element's `allowedInteractions` is `.readOnly`.
        public let isLocked: Bool
    }

    /// A snapshot of one ink stroke. Hashes by `id`; equality compares every field.
    public struct Stroke: Identifiable, Codable, Hashable, Sendable {
        /// Wraps `PKStroke.id`, the value PaperKit uses in `ElementID.stroke(_:)`.
        public struct ID: Hashable, Codable, Sendable {
            let uuid: UUID
        }

        public struct Point: Codable, Hashable, Sendable {
            public let location: CGPoint
            public let timeOffset: TimeInterval
            public let size: CGSize
            public let opacity: CGFloat
            public let force: CGFloat
            public let azimuth: CGFloat
            public let altitude: CGFloat
        }

        public let id: ID
        public let ink: Paper.Ink
        public let points: [Point]
        public let transform: CGAffineTransform
        /// An immutable copy, so sharing it across threads is safe.
        nonisolated(unsafe) public let mask: CGPath?
        public let randomSeed: UInt32

        /// The stroke's spine as Bézier curves, in page coordinates (`PKStrokePath.bezierRepresentation`).
        public var path: CGPath {
            Self.bezierPath(points, transform: transform)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public static func == (lhs: Stroke, rhs: Stroke) -> Bool {
            lhs.id == rhs.id && lhs.ink == rhs.ink && lhs.points == rhs.points && lhs.transform == rhs.transform
                && lhs.randomSeed == rhs.randomSeed && lhs.mask == rhs.mask
        }

        private enum CodingKeys: String, CodingKey { case id, ink, points, transform, randomSeed }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(ID.self, forKey: .id)
            ink = try c.decode(Paper.Ink.self, forKey: .ink)
            points = try c.decode([Point].self, forKey: .points)
            transform = try c.decode(CGAffineTransform.self, forKey: .transform)
            randomSeed = try c.decode(UInt32.self, forKey: .randomSeed)
            mask = nil
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(ink, forKey: .ink)
            try c.encode(points, forKey: .points)
            try c.encode(transform, forKey: .transform)
            try c.encode(randomSeed, forKey: .randomSeed)
        }

        /// The same Bézier conversion PencilKit uses, rebuilt from the decoded points.
        static func bezierPath(_ points: [Point], transform: CGAffineTransform) -> CGPath {
            let strokePoints = points.map {
                PKStrokePoint(location: $0.location, timeOffset: $0.timeOffset, size: $0.size, opacity: $0.opacity,
                              force: $0.force, azimuth: $0.azimuth, altitude: $0.altitude)
            }
            let path = CGMutablePath()
            path.addPath(PKStrokePath(controlPoints: strokePoints, creationDate: .distantPast).bezierRepresentation, transform: transform)
            return path
        }
    }

    /// The shapes PaperKit can draw.
    public enum Shape: Codable, Hashable, Sendable {
        case rectangle
        case roundedRectangle(cornerRadius: CGFloat)
        case ellipse
        /// 3 sides for a triangle.
        case regularPolygon(sides: Int)
        case star
        case chatBubble
        case arrow
        /// Reported for lines. Create lines with `insertLine(from:to:style:startArrow:endArrow:)`.
        case line
    }
}

// MARK: - PaperKit bridge

extension Paper.Element {
    init(_ element: any PaperKit.Markup) {
        let id = element.elementID
        self.id = ID(raw: id)
        self.frame = element.frame
        self.isLocked = element.allowedInteractions == .readOnly
        switch id {
        case .stroke(let uuid):
            kind = .stroke(Paper.Stroke.ID(uuid: uuid))
        case .shape:
            if let shape = element as? ShapeMarkup {
                kind = shape.attributedText.characters.isEmpty ? .shape(Paper.Shape(shape.shapeScaled)) : .text
            } else {
                kind = .shape(.rectangle)
            }
        case .image: kind = .image
        case .link: kind = .link
        case .loupe: kind = .loupe
        @unknown default: kind = .shape(.rectangle)
        }
    }
}

extension Paper.Shape {
    init(_ shape: ShapeMarkup.Shape) {
        switch shape {
        case .rectangle(let rectangle):
            if let radius = rectangle.cornerRadius, radius > 0 {
                // shapeScaled multiplies by the frame's short side, which adds float noise.
                self = .roundedRectangle(cornerRadius: (radius * 1000).rounded() / 1000)
            } else {
                self = .rectangle
            }
        case .ellipse: self = .ellipse
        case .regularPolygon(let polygon): self = .regularPolygon(sides: polygon.sides)
        case .star: self = .star
        case .chatBubble: self = .chatBubble
        case .arrowShape: self = .arrow
        case .line: self = .line
        @unknown default: self = .rectangle
        }
    }
}

extension Paper.Stroke {
    init(_ stroke: PKStroke) {
        self.id = ID(uuid: stroke.id)
        self.ink = Paper.Ink(
            kind: Paper.Ink.Kind(stroke.ink.inkType),
            color: Paper.Color(stroke.ink.color.cgColor) ?? .black
        )
        self.points = stroke.path.map {
            Point(location: $0.location, timeOffset: $0.timeOffset, size: $0.size, opacity: $0.opacity,
                  force: $0.force, azimuth: $0.azimuth, altitude: $0.altitude)
        }
        self.transform = stroke.transform
        self.mask = stroke.mask?.cgPath.copy()
        self.randomSeed = stroke.randomSeed
    }
}

extension Path {
    /// The stroke's Bézier spine in page coordinates.
    public init(_ stroke: Paper.Stroke) {
        self.init(stroke.path)
    }
}
