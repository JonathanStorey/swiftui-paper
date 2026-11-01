import SwiftUI

extension Paper {
    /// A color in linear extended sRGB. Components may exceed 1.0 for HDR ink.
    public struct Color: Codable, Hashable, Sendable {
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

        public static let black = Color(red: 0, green: 0, blue: 0)
        public static let white = Color(red: 1, green: 1, blue: 1)
        public static let red = Color(red: 1, green: 0, blue: 0)
        public static let green = Color(red: 0, green: 1, blue: 0)
        public static let blue = Color(red: 0, green: 0, blue: 1)
        public static let yellow = Color(red: 1, green: 1, blue: 0)
    }
}

// MARK: - SwiftUI bridge

extension Paper.Color {
    public init(_ resolved: SwiftUI.Color.Resolved) {
        self.init(red: resolved.linearRed, green: resolved.linearGreen, blue: resolved.linearBlue, opacity: resolved.opacity)
    }

    public init(_ color: SwiftUI.Color, in environment: EnvironmentValues) {
        self.init(color.resolve(in: environment))
    }

    public var color: SwiftUI.Color {
        SwiftUI.Color(.sRGBLinear, red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(opacity))
    }
}

// MARK: - CoreGraphics bridge

extension Paper.Color {
    static let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    init?(_ cgColor: CGColor) {
        guard let converted = cgColor.converted(to: Self.colorSpace, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4
        else { return nil }
        self.init(red: Float(c[0]), green: Float(c[1]), blue: Float(c[2]), opacity: Float(c[3]))
    }

    var cgColor: CGColor {
        CGColor(colorSpace: Self.colorSpace, components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(opacity)])!
    }
}
