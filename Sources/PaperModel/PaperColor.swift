/// A color in linear extended sRGB. Components may exceed 1.0 for HDR ink.
public struct PaperColor: Codable, Hashable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var opacity: Float

    public init(red: Float, green: Float, blue: Float, opacity: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let black = PaperColor(red: 0, green: 0, blue: 0)
    public static let white = PaperColor(red: 1, green: 1, blue: 1)
    public static let red = PaperColor(red: 1, green: 0, blue: 0)
    public static let green = PaperColor(red: 0, green: 1, blue: 0)
    public static let blue = PaperColor(red: 0, green: 0, blue: 1)
    public static let yellow = PaperColor(red: 1, green: 1, blue: 0)
}
