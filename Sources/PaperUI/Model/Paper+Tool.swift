import CoreGraphics

extension Paper {
    /// The tool the editor draws with.
    public enum Tool: Codable, Hashable, Sendable {
        case ink(Paper.Ink, width: CGFloat)
        case eraser(Paper.Eraser)
        case lasso
        case custom(id: String)

        public static func pen(_ color: Paper.Color, width: CGFloat = 3) -> Tool { .ink(Ink(kind: .pen, color: color), width: width) }
        public static func pencil(_ color: Paper.Color, width: CGFloat = 2) -> Tool { .ink(Ink(kind: .pencil, color: color), width: width) }
        public static func marker(_ color: Paper.Color, width: CGFloat = 12) -> Tool { .ink(Ink(kind: .marker, color: color), width: width) }
        public static func monoline(_ color: Paper.Color, width: CGFloat = 3) -> Tool { .ink(Ink(kind: .monoline, color: color), width: width) }
        public static func fountainPen(_ color: Paper.Color, width: CGFloat = 4) -> Tool { .ink(Ink(kind: .fountainPen, color: color), width: width) }
        public static func watercolor(_ color: Paper.Color, width: CGFloat = 20) -> Tool { .ink(Ink(kind: .watercolor, color: color), width: width) }
        public static func crayon(_ color: Paper.Color, width: CGFloat = 12) -> Tool { .ink(Ink(kind: .crayon, color: color), width: width) }
        public static func reed(_ color: Paper.Color, width: CGFloat = 6) -> Tool { .ink(Ink(kind: .reed, color: color), width: width) }
        public static let eraser: Tool = .eraser(.vector)
    }

    public struct Ink: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
            case pen, pencil, marker, monoline, fountainPen, watercolor, crayon, reed

            /// Unknown kinds from newer files decode as `.pen` rather than failing.
            public init(from decoder: any Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .pen
            }
        }

        public var kind: Kind
        public var color: Paper.Color

        public init(kind: Kind, color: Paper.Color) {
            self.kind = kind
            self.color = color
        }
    }

    public enum Eraser: Codable, Hashable, Sendable {
        case vector
        case bitmap(width: CGFloat?)
    }
}
