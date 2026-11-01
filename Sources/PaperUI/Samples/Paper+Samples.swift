#if DEBUG
import CoreGraphics
import Foundation
import PDFKit
import PencilKit

extension Paper {
    /// A letter page with two crossing pen strokes. For previews and tests.
    public static var sample: Paper {
        var paper = Paper(size: .letter)
        paper.withMarkup { markup in
            markup.subelements.append(PKStroke.sample(from: CGPoint(x: 72, y: 72), to: CGPoint(x: 300, y: 300)))
            markup.subelements.append(PKStroke.sample(from: CGPoint(x: 300, y: 72), to: CGPoint(x: 72, y: 300)))
        }
        return paper
    }

    /// A letter page whose background is a ruled worksheet PDF, with no elements. For previews and tests.
    public static var samplePDF: Paper {
        Paper(pdfPage: PDFDocument(data: samplePDFData)!.page(at: 0)!)
    }

    /// A one-page ruled worksheet, drawn with Core Graphics so it needs no bundled resource.
    static var samplePDFData: Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: Paper.Size.letter.size)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        context.beginPDFPage(nil)
        context.setStrokeColor(CGColor(red: 0.6, green: 0.75, blue: 0.9, alpha: 1))
        context.setLineWidth(0.75)
        for y in stride(from: 108.0, to: box.height - 36, by: 28) {
            context.move(to: CGPoint(x: 54, y: y))
            context.addLine(to: CGPoint(x: box.width - 54, y: y))
        }
        context.strokePath()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

extension PKStroke {
    /// A straight pen stroke between two points, sampled every 10 pt.
    static func sample(from start: CGPoint, to end: CGPoint, id: UUID = UUID()) -> PKStroke {
        let steps = max(2, Int(hypot(end.x - start.x, end.y - start.y) / 10))
        let points = (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(t) * 0.2,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, id: id)
    }
}

extension PKDrawing {
    /// Two crossing strokes on a letter page.
    static var sample: PKDrawing {
        PKDrawing(strokes: [
            .sample(from: CGPoint(x: 72, y: 72), to: CGPoint(x: 300, y: 300)),
            .sample(from: CGPoint(x: 300, y: 72), to: CGPoint(x: 72, y: 300)),
        ])
    }
}
#endif
