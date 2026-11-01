import CoreGraphics
import Foundation
import PaperKit
import PDFKit
import PencilKit
import SwiftUI
import Testing
@testable import PaperUI

struct ElementTests {
    /// MarkupOrderedSet lists every non-ink element before every stroke, whatever the insertion
    /// order (SDK-FINDINGS E.2). `elements` reports that order unchanged.
    @Test func elementsListShapesThenStrokes() {
        var paper = Paper.sample
        paper.withMarkup {
            $0.insertNewShape(configuration: ShapeConfiguration(type: .ellipse), frame: CGRect(x: 0, y: 0, width: 50, height: 50))
            $0.insertNewTextbox(attributedText: AttributedString("Hi"), frame: CGRect(x: 0, y: 100, width: 80, height: 30))
        }
        let kinds = paper.elements.map(\.kind)
        #expect(kinds.count == 4)
        #expect(kinds[0] == .shape(.ellipse))
        #expect(kinds[1] == .text)
        #expect(kinds[2] == .stroke(paper.strokes[0].id))
        #expect(paper.elements.allSatisfy { !$0.isLocked })
    }

    @Test func strokesReadInkPointsAndPath() throws {
        let stroke = try #require(Paper.sample.strokes.first)
        #expect(stroke.ink.kind == .pen)
        #expect(stroke.points.first?.location == CGPoint(x: 72, y: 72))
        #expect(!stroke.path.isEmpty)
        #expect(!Path(stroke).isEmpty)
    }

    @Test func strokeCodableRoundTrip() throws {
        let stroke = try #require(Paper.sample.strokes.first)
        let decoded = try JSONDecoder().decode(Paper.Stroke.self, from: JSONEncoder().encode(stroke))
        #expect(decoded == stroke)
        #expect(decoded.path.boundingBoxOfPath == stroke.path.boundingBoxOfPath)
    }

    @Test func projectionsAreReplacedOnMutation() {
        var paper = Paper.sample
        #expect(paper.elements.count == 2)
        paper.append(Paper.sample)
        #expect(paper.elements.count == 4)
    }

    @Test func idsSurviveSaving() async throws {
        let paper = Paper.sample
        let restored = try Paper(dataRepresentation: await paper.dataRepresentation())
        #expect(restored.elements.map(\.id) == paper.elements.map(\.id))
    }
}

struct LockingTests {
    @Test func lockAndUnlockByID() async throws {
        var paper = Paper.sample
        let first = paper.elements[0].id
        paper.lock([first])
        #expect(paper.elements.map(\.isLocked) == [true, false])
        let restored = try Paper(dataRepresentation: await paper.dataRepresentation())
        #expect(restored.elements.map(\.isLocked) == [true, false])

        paper.unlock([first])
        #expect(paper.elements.map(\.isLocked) == [false, false])
    }

    @Test func lockAllKeepsIDsAndOrder() {
        var paper = Paper.sample
        let ids = paper.elements.map(\.id)
        paper.lockAll()
        #expect(paper.elements.allSatisfy { $0.isLocked })
        #expect(paper.elements.map(\.id) == ids)
        paper.unlockAll()
        #expect(paper.elements.allSatisfy { !$0.isLocked })
    }

    @Test func lockingNothingDoesNotMutate() {
        var paper = Paper.sample
        let token = paper.token
        paper.lock([Paper.Element.ID]())
        #expect(paper.token == token)
    }
}

struct RotationTests {
    /// One short stroke near the top-left corner of a letter page.
    var marked: Paper {
        var paper = Paper(size: .letter)
        paper.withMarkup { $0.subelements.append(PKStroke.sample(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 100, y: 50))) }
        return paper
    }

    @Test func clockwiseMovesTopLeftToTopRight() throws {
        var paper = marked
        let id = paper.strokes[0].id
        paper.rotate(.clockwise)
        #expect(paper.size.size == CGSize(width: 792, height: 612))
        #expect(paper.strokes[0].id == id)
        let bounds = paper.contentBounds
        #expect(bounds.minX > 600, "content should now sit near the right edge: \(bounds)")
        #expect(bounds.minY < 150, "and near the top: \(bounds)")
    }

    @Test func counterclockwiseMovesTopLeftToBottomLeft() {
        var paper = marked
        paper.rotate(.counterclockwise)
        let bounds = paper.contentBounds
        #expect(bounds.minX < 100, "\(bounds)")
        #expect(bounds.maxY > 450, "\(bounds)")
    }

    @Test func fourQuarterTurnsAreIdentity() {
        var paper = marked
        let before = paper.contentBounds
        for _ in 0..<4 { paper.rotate(.clockwise) }
        #expect(paper.size == .letter)
        #expect(abs(paper.contentBounds.minX - before.minX) < 0.5)
        #expect(abs(paper.contentBounds.minY - before.minY) < 0.5)
    }

    @Test func halfTurnKeepsSize() {
        var paper = marked
        paper.rotate(.halfTurn)
        #expect(paper.size == .letter)
        #expect(paper.contentBounds.minX > 450)
        #expect(paper.contentBounds.minY > 650)
    }

    @Test func pdfBackgroundGetsPageRotation() throws {
        var paper = Paper.samplePDF
        paper.rotate(.clockwise)
        guard case .pdfPage(let data) = paper.background else { Issue.record("no background"); return }
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
        #expect(page.rotation == 90)
        #expect(Paper.Size(page) == paper.size)
    }

    @Test func imageBackgroundTurnsByWholePixels() throws {
        let context = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        var paper = Paper(image: image, size: .letter)
        paper.rotate(.clockwise)
        guard case .image(let data) = paper.background,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let rotated = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { Issue.record("no image background"); return }
        #expect(rotated.width == 2)
        #expect(rotated.height == 4)
    }

    @Test func resizeScalingContent() {
        var paper = marked
        let before = paper.contentBounds
        paper.resize(to: Paper.Size(CGSize(width: 1224, height: 1584)), scalingContent: true)
        #expect(abs(paper.contentBounds.midX - before.midX * 2) < 2)
        var unscaled = marked
        unscaled.resize(to: .legal, scalingContent: false)
        #expect(unscaled.size == .legal)
        #expect(unscaled.contentBounds == before)
    }

    @Test func appendKeepsIDsOnTop() {
        var bottom = Paper.sample
        let top = marked
        let expected = bottom.elements.map(\.id) + top.elements.map(\.id)
        bottom.append(top)
        #expect(bottom.elements.map(\.id) == expected)
    }
}
