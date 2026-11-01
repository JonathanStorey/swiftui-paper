import CoreGraphics
import Foundation

/// The size of a sheet of paper, in points (72 per inch).
public struct PaperSize: Codable, Hashable, Sendable {
    public var size: CGSize

    public init(_ size: CGSize) {
        self.size = size
    }

    public init(width: Measurement<UnitLength>, height: Measurement<UnitLength>) {
        self.size = CGSize(
            width: width.converted(to: .inches).value * 72,
            height: height.converted(to: .inches).value * 72
        )
    }

    public static let letter = PaperSize.inches(8.5, 11)
    public static let legal = PaperSize.inches(8.5, 14)
    public static let a4 = PaperSize.millimeters(210, 297)
    public static let a5 = PaperSize.millimeters(148, 210)
    public static let square = PaperSize(CGSize(width: 612, height: 612))

    public static func inches(_ width: Double, _ height: Double) -> PaperSize {
        PaperSize(width: .init(value: width, unit: .inches), height: .init(value: height, unit: .inches))
    }

    public static func millimeters(_ width: Double, _ height: Double) -> PaperSize {
        PaperSize(width: .init(value: width, unit: .millimeters), height: .init(value: height, unit: .millimeters))
    }

    /// The same paper with width and height arranged so width is the longer side.
    public var landscape: PaperSize {
        PaperSize(CGSize(width: max(size.width, size.height), height: min(size.width, size.height)))
    }
}
