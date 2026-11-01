import CoreGraphics
import Foundation
import PDFKit

extension Paper {
    /// The size of a sheet of paper, in points (72 per inch).
    public struct Size: Codable, Hashable, Sendable {
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

        /// The size of a PDF page's media box.
        public init(_ page: PDFPage) {
            let box = page.bounds(for: .mediaBox)
            let quarterTurn = (page.rotation / 90) % 2 != 0
            self.size = quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
        }

        public static let letter = Size.inches(8.5, 11)
        public static let legal = Size.inches(8.5, 14)
        public static let a4 = Size.millimeters(210, 297)
        public static let a5 = Size.millimeters(148, 210)
        public static let square = Size(CGSize(width: 612, height: 612))

        public static func inches(_ width: Double, _ height: Double) -> Size {
            Size(width: .init(value: width, unit: .inches), height: .init(value: height, unit: .inches))
        }

        public static func millimeters(_ width: Double, _ height: Double) -> Size {
            Size(width: .init(value: width, unit: .millimeters), height: .init(value: height, unit: .millimeters))
        }

        /// The same paper with width and height arranged so width is the longer side.
        public var landscape: Size {
            Size(CGSize(width: max(size.width, size.height), height: min(size.width, size.height)))
        }
    }

    /// What sits behind the elements. Stored inside the `Paper`.
    public enum Background: Codable, Hashable, Sendable {
        /// Encoded PNG, JPEG, or HEIC, stretched to the page.
        case image(Data)
        /// A single-page PDF extracted from the source document.
        case pdfPage(Data)
    }
}
