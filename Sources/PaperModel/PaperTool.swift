import CoreGraphics

/// The tool the editor draws with.
public enum PaperTool: Codable, Hashable, Sendable {
    case inking(InkingTool)
    case eraser(EraserMode)
    case lasso
    case custom(id: String)

    public static func pen(_ color: PaperColor, width: CGFloat = 3) -> PaperTool { .ink(.pen, color, width) }
    public static func pencil(_ color: PaperColor, width: CGFloat = 2) -> PaperTool { .ink(.pencil, color, width) }
    public static func marker(_ color: PaperColor, width: CGFloat = 12) -> PaperTool { .ink(.marker, color, width) }
    public static func monoline(_ color: PaperColor, width: CGFloat = 3) -> PaperTool { .ink(.monoline, color, width) }
    public static func fountainPen(_ color: PaperColor, width: CGFloat = 4) -> PaperTool { .ink(.fountainPen, color, width) }
    public static func watercolor(_ color: PaperColor, width: CGFloat = 20) -> PaperTool { .ink(.watercolor, color, width) }
    public static func crayon(_ color: PaperColor, width: CGFloat = 12) -> PaperTool { .ink(.crayon, color, width) }
    public static let eraser: PaperTool = .eraser(.vector)

    private static func ink(_ kind: InkKind, _ color: PaperColor, _ width: CGFloat) -> PaperTool {
        .inking(InkingTool(ink: PaperInk(kind: kind, color: color), width: width))
    }
}

public struct InkingTool: Codable, Hashable, Sendable {
    public var ink: PaperInk
    public var width: CGFloat

    public init(ink: PaperInk, width: CGFloat) {
        self.ink = ink
        self.width = width
    }
}

public struct PaperInk: Codable, Hashable, Sendable {
    public var kind: InkKind
    public var color: PaperColor

    public init(kind: InkKind, color: PaperColor) {
        self.kind = kind
        self.color = color
    }
}

public enum InkKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon

    /// Unknown kinds from newer files decode as `.pen` rather than failing.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InkKind(rawValue: raw) ?? .pen
    }
}

public enum EraserMode: Codable, Hashable, Sendable {
    case vector
    case bitmap(width: CGFloat?)
}
