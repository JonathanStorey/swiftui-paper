import CoreGraphics
import Foundation
import PaperKit
import PencilKit
import SwiftUI
import Testing
@testable import PaperUI

struct EditingTests {
    @Test func insertShapeKeepsStyleAndKind() throws {
        var paper = Paper()
        paper.insertShape(.roundedRectangle(cornerRadius: 8), style: .init(stroke: .red, fill: .yellow, lineWidth: 4, opacity: 0.5),
                          in: CGRect(x: 10, y: 20, width: 100, height: 50))
        paper.insertShape(.regularPolygon(sides: 3), style: .filled(.blue), in: CGRect(x: 200, y: 20, width: 60, height: 60))
        #expect(paper.elements.map(\.kind) == [.shape(.roundedRectangle(cornerRadius: 8)), .shape(.regularPolygon(sides: 3))])
        #expect(paper.elements[0].frame == CGRect(x: 10, y: 20, width: 100, height: 50))
        let shape = try #require(paper.markup.subelements[0] as? ShapeMarkup)
        #expect(shape.lineWidth == 4)
        #expect(abs(shape.opacity - 0.5) < 0.001)
        #expect(shape.fillColor != nil && shape.strokeColor != nil)
        let filled = try #require(paper.markup.subelements[1] as? ShapeMarkup)
        #expect(filled.strokeColor == nil)
    }

    @Test(arguments: [Paper.Shape.rectangle, .ellipse, .star, .chatBubble, .arrow])
    func everyShapeReadsBack(shape: Paper.Shape) {
        var paper = Paper()
        paper.insertShape(shape, style: .outline, in: CGRect(x: 0, y: 0, width: 80, height: 80))
        #expect(paper.elements.first?.kind == .shape(shape))
    }

    @Test func insertLineReportsLine() throws {
        var paper = Paper()
        paper.insertLine(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 100), style: .outline, endArrow: true)
        #expect(paper.elements.first?.kind == .shape(.line))
        let line = try #require(paper.markup.subelements[0] as? ShapeMarkup)
        #expect(line.endLineMarker == .arrow)
        #expect(line.startLineMarker == .none)
    }

    @Test func insertTextAndImage() throws {
        var paper = Paper()
        paper.insertText(AttributedString("Name:"), in: CGRect(x: 20, y: 20, width: 200, height: 30))
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        paper.insertImage(try #require(context.makeImage()), in: CGRect(x: 20, y: 80, width: 40, height: 40))
        #expect(paper.elements.map(\.kind) == [.text, .image])
    }

    @Test func removeTakesStrokesAndShapes() {
        var paper = Paper.sample
        paper.insertShape(.ellipse, style: .outline, in: CGRect(x: 0, y: 0, width: 50, height: 50))
        let ellipse = paper.elements.first { $0.kind == .shape(.ellipse) }!.id
        let stroke = paper.elements.first { if case .stroke = $0.kind { true } else { false } }!.id
        paper.remove([ellipse, stroke])
        #expect(paper.elements.count == 1)
        paper.remove(paper.elements.map(\.id))
        #expect(paper.isEmpty)
    }

    /// `removeElement(for:)` does reach strokes; only `removeAll(where:)` skips them.
    @Test func removeElementForStrokeID() {
        var markup = Paper.sample.markup
        markup.subelements.removeElement(for: markup.subelements.ids[0])
        #expect(markup.subelements.count == 1)
    }

    @Test func lineOpacityAndCornerRadiusInPoints() throws {
        var paper = Paper()
        paper.insertLine(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 200, y: 10), style: .init(stroke: .red, lineWidth: 3, opacity: 0.4))
        let line = try #require(paper.markup.subelements[0] as? ShapeMarkup)
        #expect(abs(line.opacity - 0.4) < 0.001)
        paper.insertShape(.roundedRectangle(cornerRadius: 12), style: .outline, in: CGRect(x: 0, y: 100, width: 200, height: 80))
        let rect = try #require(paper.markup.subelements[1] as? ShapeMarkup)
        guard case .rectangle(let r) = rect.shapeScaled else { Issue.record("not a rectangle"); return }
        #expect(abs((r.cornerRadius ?? 0) - 12) < 0.001)
        #expect(paper.elements[1].kind == .shape(.roundedRectangle(cornerRadius: 12)))
    }

    @Test func selectionBasics() {
        var selection = Paper.Selection(Paper.sample.elements.map(\.id))
        #expect(selection.ids.count == 2)
        selection.clear()
        #expect(selection.isEmpty)
        #expect(Paper.Selection() == selection)
    }
}
