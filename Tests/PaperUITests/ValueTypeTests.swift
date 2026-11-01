import CoreGraphics
import Foundation
import Testing
@testable import PaperUI

struct PaperSizeTests {
    @Test func letterIsPoints() {
        #expect(Paper.Size.letter.size == CGSize(width: 612, height: 792))
    }

    @Test func a4RoundsToKnownPoints() {
        #expect(abs(Paper.Size.a4.size.width - 595.28) < 0.01)
        #expect(abs(Paper.Size.a4.size.height - 841.89) < 0.01)
    }

    @Test func landscapeSwapsLongSide() {
        #expect(Paper.Size.letter.landscape.size == CGSize(width: 792, height: 612))
    }
}

struct PaperToolTests {
    @Test func codableRoundTrip() throws {
        let tools: [Paper.Tool] = [.pen(.red, width: 5), .reed(.blue), .eraser, .eraser(.bitmap(width: 10)), .lasso, .custom(id: "x")]
        let data = try JSONEncoder().encode(tools)
        #expect(try JSONDecoder().decode([Paper.Tool].self, from: data) == tools)
    }

    @Test func unknownInkKindDecodesAsPen() throws {
        let data = Data(#"["quill", "pencil", "reed"]"#.utf8)
        #expect(try JSONDecoder().decode([Paper.Ink.Kind].self, from: data) == [.pen, .pencil, .reed])
    }
}

struct PaperColorTests {
    @Test func cgColorRoundTrip() throws {
        let color = Paper.Color(red: 0.25, green: 0.5, blue: 1.5, opacity: 0.75)
        let back = try #require(Paper.Color(color.cgColor))
        #expect(abs(back.blue - 1.5) < 0.001)
        #expect(abs(back.opacity - 0.75) < 0.001)
    }

    @Test func srgbIsConvertedToLinear() throws {
        let gray = try #require(Paper.Color(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
        #expect(abs(gray.red - 0.214) < 0.01)
    }
}

struct PaperFeaturesTests {
    @Test func latestHasEverything() {
        #expect(Paper.Features.latest.inks.count == Paper.Ink.Kind.allCases.count)
        #expect(Paper.Features.Feature.allCases.allSatisfy(Paper.Features.latest.contains))
    }

    @Test func removingAndInserting() {
        let noText = Paper.Features.latest.removing(.text)
        #expect(!noText.contains(.text))
        #expect(noText.inserting(.text) == .latest)
    }
}
