import Foundation
import PaperKit
import PencilKit
import Testing
@testable import PaperUI

/// Behavior the SDK interface can't state. Each test pins an answer recorded in docs/SDK-FINDINGS.md.
struct PaperKitBehaviorTests {
    @Test func strokesAreReadableAfterAppendingDrawing() {
        let drawing = PKDrawing.sample
        var paper = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        paper.append(contentsOf: drawing)

        let ids = paper.subelements.strokes.map(\.id)
        print("PROBE append(PKDrawing) keeps stroke ids:", ids == drawing.strokes.map(\.id))
        #expect(ids.count == 2)
        #expect(paper.subelements.ids.allSatisfy { if case .stroke = $0 { true } else { false } })
    }

    @Test func strokeIDsSurviveDataRepresentation() async throws {
        var paper = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        paper.subelements.append(PKStroke.sample(from: .init(x: 10, y: 10), to: .init(x: 200, y: 50)))
        paper.subelements.append(PKStroke.sample(from: .init(x: 10, y: 80), to: .init(x: 200, y: 120)))
        let ids = paper.subelements.strokes.map(\.id)

        let restored = try PaperMarkup(dataRepresentation: await paper.dataRepresentation())

        #expect(restored.subelements.strokes.map(\.id) == ids)
        #expect(restored.bounds == paper.bounds)
        #expect(restored == paper)
    }

    @Test func appendingMarkupKeepsIDsAndOrder() {
        var bottom = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        bottom.subelements.append(PKStroke.sample(from: .init(x: 10, y: 10), to: .init(x: 200, y: 50)))
        var top = PaperMarkup(bounds: bottom.bounds)
        top.subelements.append(PKStroke.sample(from: .init(x: 10, y: 80), to: .init(x: 200, y: 120)))

        let expected = Array(bottom.subelements.ids) + Array(top.subelements.ids)
        bottom.append(contentsOf: top)

        let actual = Array(bottom.subelements.ids)
        print("PROBE append(PaperMarkup) keeps ids and order:", actual == expected, actual.count)
        #expect(actual == expected)
    }

    @Test func elementsCanBeRemovedByID() {
        var paper = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        paper.append(contentsOf: PKDrawing.sample)
        paper.insertNewShape(configuration: ShapeConfiguration(type: .rectangle), frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(paper.subelements.count == 3)

        let shapeID = paper.subelements.ids.first { if case .shape = $0 { true } else { false } }
        #expect(shapeID != nil)
        if let shapeID { paper.subelements.removeElement(for: shapeID) }
        let strokeID = paper.subelements.strokes[0].id
        paper.subelements.removeStroke(for: strokeID)

        #expect(paper.subelements.count == 1)
    }

    @Test func textboxElementKind() {
        var paper = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        paper.insertNewTextbox(attributedText: AttributedString("Hello"), frame: CGRect(x: 10, y: 10, width: 200, height: 40))

        #expect(paper.subelements.count == 1)
        let element = paper.subelements[0]
        print("PROBE textbox element type:", type(of: element), "id:", element.elementID)
        #expect(element is ShapeMarkup)
        if let shape = element as? ShapeMarkup {
            print("PROBE textbox shape:", shape.shape, "text:", String(shape.attributedText.characters))
            #expect(String(shape.attributedText.characters) == "Hello")
        }
    }

    @Test func insertedShapeKinds() {
        var paper = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        for (i, kind) in ShapeConfiguration.Shape.allCases.enumerated() where kind != .line {
            paper.insertNewShape(configuration: ShapeConfiguration(type: kind), frame: CGRect(x: 0, y: CGFloat(i) * 60, width: 50, height: 50))
        }
        paper.insertNewLine(configuration: ShapeConfiguration(type: .line, strokeColor: CGColor(gray: 0, alpha: 1), lineWidth: 2), from: .zero, to: CGPoint(x: 100, y: 100), endMarker: true)
        for element in paper.subelements {
            if let shape = element as? ShapeMarkup {
                print("PROBE shape:", shape.shape.configurationType, "end marker:", shape.endLineMarker)
            }
        }
        print("PROBE ShapeConfiguration.Shape.allCases:", ShapeConfiguration.Shape.allCases)
        #expect(paper.subelements.count == ShapeConfiguration.Shape.allCases.count)
    }

    @Test func erasingSplitsStrokes() {
        let stroke = PKStroke.sample(from: .init(x: 0, y: 100), to: .init(x: 400, y: 100))
        let eraser = PKStroke.sample(from: .init(x: 200, y: 0), to: .init(x: 200, y: 200)).path
        let erased = PKDrawing(strokes: [stroke]).erasingPath(eraser)

        print("PROBE erase result count:", erased.strokes.count,
              "keeps original id:", erased.strokes.map(\.id).contains(stroke.id),
              "masked ranges:", erased.strokes.map(\.maskedPathRanges))
        #expect(erased != PKDrawing(strokes: [stroke]))
    }

    @Test func bezierRepresentationIsNonEmpty() {
        let stroke = PKStroke.sample(from: .init(x: 0, y: 0), to: .init(x: 100, y: 100))
        #expect(!stroke.path.bezierRepresentation.isEmpty)
        print("PROBE PKStrokePath.id == PKStroke.id:", stroke.path.id == stroke.id)
    }

    @Test func featureSetLatest() {
        let latest = FeatureSet.latest
        print("PROBE FeatureSet.latest features:", latest.features.sorted { "\($0)" < "\($1)" },
              "shapes:", latest.shapes.count, "inks:", latest.inks.map(\.rawValue).sorted(),
              "maxExposure:", latest.colorMaximumLinearExposure, "== version1:", latest == .version1)
        #expect(latest.contains(.drawing))
    }
}
