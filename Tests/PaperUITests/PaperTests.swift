import Foundation
import PaperKit
import PDFKit
import PencilKit
import Testing
@testable import PaperUI

struct PaperTests {
    @Test func emptyRoundTripKeepsSize() async throws {
        let paper = Paper(size: .a4)
        let restored = try Paper(dataRepresentation: await paper.dataRepresentation())
        #expect(restored.size == .a4)
        #expect(restored.isEmpty)
        #expect(restored == paper)
    }

    @Test func roundTripKeepsStrokesColorAndBackground() async throws {
        var paper = Paper.samplePDF
        paper.withMarkup { $0.append(contentsOf: Paper.sample.markup) }
        paper.color = .yellow
        let ids = paper.markup.subelements.strokes.map(\.id)

        let restored = try Paper(dataRepresentation: await paper.dataRepresentation())

        #expect(restored.markup.subelements.strokes.map(\.id) == ids)
        #expect(restored.background == paper.background)
        #expect(restored.color.map { abs($0.green - 1) < 0.001 } == true)
        #expect(restored == paper)
    }

    @Test func sizeIsSettableAndKeepsContent() {
        var paper = Paper.sample
        let before = paper.markup.subelements.strokes.map(\.id)
        paper.size = .legal
        #expect(paper.size == .legal)
        #expect(paper.markup.subelements.strokes.map(\.id) == before)
    }

    @Test func colorDefaultsToNilAndIsSettable() {
        var paper = Paper()
        #expect(paper.color == nil)
        paper.color = .blue
        #expect(paper.color.map { abs($0.blue - 1) < 0.001 } == true)
        paper.color = nil
        #expect(paper.color == nil)
    }

    @Test func mutationChangesToken() {
        var paper = Paper()
        let token = paper.token
        paper.size = .a5
        #expect(paper.token != token)
        let afterSize = paper.token
        paper.background = .image(Data([1, 2, 3]))
        #expect(paper.token != afterSize)
    }

    @Test func equalityFallsBackToPaperMarkup() async throws {
        let a = Paper.sample
        let restored = try Paper(dataRepresentation: await a.dataRepresentation())
        #expect(a.token != restored.token)
        #expect(a == restored)

        var withBackground = restored
        withBackground.background = .image(Data([1]))
        #expect(withBackground != a)
    }

    /// PaperMarkup's `==` tracks edit history: the same edit made separately to two copies
    /// gives unequal values. Paper inherits this. It is conservative, never a false "equal".
    @Test func separateIdenticalEditsAreNotEqual() {
        var a = Paper.sample
        var b = a
        a.size = .legal
        b.size = .legal
        #expect(a != b)
    }

    @Test func hashUsesSizeOnly() {
        #expect(Paper.sample.hashValue == Paper(size: .letter).hashValue)
    }

    @Test func pdfPageInitTakesMediaBox() throws {
        let page = try #require(PDFDocument(data: Paper.samplePDFData)?.page(at: 0))
        let paper = Paper(pdfPage: page)
        #expect(paper.size == .letter)
        guard case .pdfPage(let data) = paper.background else { Issue.record("no PDF background"); return }
        #expect(PDFDocument(data: data)?.pageCount == 1)
    }

    @Test func lockAllSetsReadOnlyAndSurvivesSaving() async throws {
        var paper = Paper.sample
        paper.withMarkup { $0.insertNewShape(configuration: ShapeConfiguration(type: .rectangle), frame: CGRect(x: 0, y: 0, width: 50, height: 50)) }
        let ids = Array(paper.markup.subelements.ids)

        paper.lockAll()
        #expect(paper.markup.subelements.allSatisfy { $0.allowedInteractions == .readOnly })
        #expect(Array(paper.markup.subelements.ids) == ids)

        let restored = try Paper(dataRepresentation: await paper.dataRepresentation())
        #expect(restored.markup.subelements.allSatisfy { $0.allowedInteractions == .readOnly })

        paper.unlockAll()
        #expect(paper.markup.subelements.allSatisfy { $0.allowedInteractions == .all })
        #expect(Array(paper.markup.subelements.ids) == ids)
    }

    @Test func rejectsNewerFormat() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        var file = PaperFile(markup: Data(), background: nil)
        file.version = 99
        #expect(throws: PaperFileError.formatTooNew(99)) { try Paper(dataRepresentation: try file.encoded()) }
        #expect(throws: PaperFileError.incorrectFormat) { try Paper(dataRepresentation: Data("nope".utf8)) }
    }
}

struct PaperCodableTests {
    @Test func codableRoundTripAfterSnapshotRefresh() async throws {
        let paper = Paper.sample
        await paper.snapshot.waitUntilFresh()
        let decoded = try JSONDecoder().decode(Paper.self, from: JSONEncoder().encode(paper))
        #expect(decoded == paper)
    }

    @Test func codableTrailsByDesignThenCatchesUp() async throws {
        var paper = Paper()
        await paper.snapshot.waitUntilFresh()
        paper.withMarkup { $0.append(contentsOf: Paper.sample.markup) }

        // Encoding at once may write the previous (empty) snapshot. It never fails.
        _ = try JSONEncoder().encode(paper)

        await paper.snapshot.waitUntilFresh()
        let decoded = try JSONDecoder().decode(Paper.self, from: JSONEncoder().encode(paper))
        #expect(decoded.markup.subelements.count == 2)
    }

    @Test @MainActor func encodingANeverSerializedPaperWaitsOnTheMainActor() throws {
        let decoded = try JSONDecoder().decode(Paper.self, from: JSONEncoder().encode(Paper(size: .a5)))
        #expect(decoded.size == .a5)
    }

    @Test func burstOfMutationsSerializesTheLastState() async throws {
        var paper = Paper()
        for i in 0..<50 {
            paper.withMarkup { $0.subelements.append(PKStroke.sample(from: .init(x: 10, y: Double(i) * 10), to: .init(x: 200, y: Double(i) * 10))) }
        }
        await paper.snapshot.waitUntilFresh()
        let decoded = try JSONDecoder().decode(Paper.self, from: JSONEncoder().encode(paper))
        #expect(decoded.markup.subelements.strokes.count == 50)
    }
}
