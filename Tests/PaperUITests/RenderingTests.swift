import CoreGraphics
import CoreTransferable
import Foundation
import PaperKit
import PDFKit
import PencilKit
import Testing
import UniformTypeIdentifiers
@testable import PaperUI

/// Reads one pixel of a CGImage, row 0 at the top.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    var data = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    return (data[0], data[1], data[2], data[3])
}

func isDark(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool { p.a > 128 && p.r < 100 && p.g < 100 && p.b < 100 }

struct RenderingTests {
    /// A thick horizontal stroke 50 pt from the top-left.
    var marked: Paper {
        var paper = Paper(size: .letter)
        paper.withMarkup { $0.subelements.append(PKStroke.sample(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 200, y: 50))) }
        return paper
    }

    @Test func imageScaleSetsPixelSize() async throws {
        let image = try await Paper(size: .letter).image(scale: 1)
        #expect(image.width == 612)
        #expect(image.height == 792)
        let double = try await Paper(size: .letter).image(scale: 2)
        #expect(double.width == 1224)
    }

    @Test func imageFittingKeepsAspectRatio() async throws {
        let image = try await Paper(size: .letter).image(fitting: CGSize(width: 120, height: 400))
        #expect(image.width == 120)
        #expect(image.height == 155)
    }

    @Test func strokesRenderTopLeftUpright() async throws {
        let image = try await marked.image(scale: 1)
        #expect(isDark(pixel(image, 120, 50)), "stroke expected at y = 50 from the top")
        #expect(!isDark(pixel(image, 120, 742)), "nothing near the bottom")
        #expect(pixel(image, 400, 400) == (255, 255, 255, 255), "white paper")
    }

    @Test func paperColorFillsTheBackground() async throws {
        var paper = Paper(size: .square)
        paper.color = .blue
        let p = pixel(try await paper.image(scale: 0.25), 10, 10)
        #expect(p.b > 200 && p.r < 30)
    }

    @Test func pdfBackgroundRendersUnderStrokes() async throws {
        var paper = Paper.samplePDF
        paper.append(marked)
        let image = try await paper.image(scale: 1)
        // The sample worksheet's first rule is at y = 108 from the bottom in PDF space,
        // so 792 − 108 = 684 from the top.
        let rule = pixel(image, 300, 684)
        #expect(rule.b > rule.r, "blue rule from the PDF background: \(rule)")
        #expect(isDark(pixel(image, 120, 50)))
    }

    @Test func rotatedPDFBackgroundStaysWithItsContent() async throws {
        var paper = Paper.samplePDF
        paper.rotate(.clockwise)
        let image = try await paper.image(scale: 1)
        #expect(image.width == 792 && image.height == 612)
        // After a clockwise turn the horizontal rules are vertical. The rule 108 pt from the
        // page bottom ends up 108 pt from the left edge.
        let rule = pixel(image, 108, 300)
        #expect(rule.b > rule.r, "\(rule)")
    }

    @Test func pdfDataIsOnePageOfTheRightSize() async throws {
        let data = try await Paper.samplePDF.pdfData()
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == Paper.Size.letter.size)
    }

    /// PLAN 5.3 vector check. PaperKit's draw(in:) into a PDF context writes shapes and text as
    /// vectors but rasterizes ink at about 144 dpi (SDK-FINDINGS F). pdfData() keeps shapes vector
    /// and draws ink as one 300 dpi image.
    @Test func pdfShapesAreVectorAndInkIs300dpi() async throws {
        var paper = marked
        paper.withMarkup {
            $0.insertNewShape(configuration: ShapeConfiguration(type: .ellipse, fillColor: nil, strokeColor: CGColor(gray: 0, alpha: 1), lineWidth: 2),
                              frame: CGRect(x: 300, y: 300, width: 100, height: 100))
        }
        let data = try await paper.pdfData()
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        let images = imageXObjects(in: page.dictionary)
        #expect(images.count == 1, "one image, the ink: \(images)")
        // The stroke spans x 50–200 (150 pt plus its width), so 300 dpi is at least 625 px wide.
        #expect((images.first?.width ?? 0) >= 625, "\(images)")

        var shapesOnly = Paper(size: .letter)
        shapesOnly.withMarkup {
            $0.insertNewShape(configuration: ShapeConfiguration(type: .ellipse), frame: CGRect(x: 300, y: 300, width: 100, height: 100))
            $0.insertNewTextbox(attributedText: AttributedString("Hello"), frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        }
        let vectorPage = try #require(CGPDFDocument(CGDataProvider(data: try await shapesOnly.pdfData() as CFData)!)?.page(at: 1))
        #expect(imageXObjects(in: vectorPage.dictionary).isEmpty)
    }

    @Test func pdfInkLandsWhereTheStrokeIs() async throws {
        let data = try await marked.pdfData()
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let cg = try #require(image.cgImageForTest)
        #expect(isDark(pixel(cg, 120, 50)), "ink 50 pt from the top")
        #expect(!isDark(pixel(cg, 120, 742)))
    }

    @Test func transferableExportsAllThreeTypes() async throws {
        let paper = Paper.sample
        // An exported type resolves only where an Info.plist declares it, which a test bundle doesn't.
        #expect(UTType.swiftPaper.identifier == "org.swiftuipaper.paper")
        let pdf = try await paper.pdfData()
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let png = try await paper.pngData(scale: 2)
        #expect(png.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    }
}

/// The image XObjects in a page's resources, including inside form XObjects.
func imageXObjects(in dictionary: CGPDFDictionaryRef?) -> [(width: Int, height: Int)] {
    guard let dictionary else { return [] }
    var resources: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return [] }
    var xobjects: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return [] }
    final class Found { var images: [(width: Int, height: Int)] = [] }
    let found = Found()
    CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let streamDict = CGPDFStreamGetDictionary(stream) else { return true }
        var subtype: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype {
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(streamDict, "Width", &width)
                CGPDFDictionaryGetInteger(streamDict, "Height", &height)
                found.images.append((width, height))
            case "Form":
                found.images += imageXObjects(in: streamDict)
            default: break
            }
        }
        return true
    }, nil)
    return found.images
}

#if os(macOS)
import AppKit
extension NSImage {
    var cgImageForTest: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}
#else
import UIKit
extension UIImage {
    var cgImageForTest: CGImage? { cgImage }
}
#endif
