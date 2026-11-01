import CoreGraphics
import Foundation
@testable import PaperUI
import PencilKit

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
