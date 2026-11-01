import Foundation
import Testing
@testable import PaperModel

struct PaperSizeTests {
    @Test func letterIsPoints() {
        #expect(PaperSize.letter.size == CGSize(width: 612, height: 792))
    }

    @Test func a4RoundsToKnownPoints() {
        #expect(abs(PaperSize.a4.size.width - 595.28) < 0.01)
        #expect(abs(PaperSize.a4.size.height - 841.89) < 0.01)
    }

    @Test func landscapeSwapsLongSide() {
        #expect(PaperSize.letter.landscape.size == CGSize(width: 792, height: 612))
    }
}

struct PaperToolTests {
    @Test func codableRoundTrip() throws {
        let tools: [PaperTool] = [.pen(.red, width: 5), .eraser, .eraser(.bitmap(width: 10)), .lasso, .custom(id: "x")]
        let data = try JSONEncoder().encode(tools)
        #expect(try JSONDecoder().decode([PaperTool].self, from: data) == tools)
    }

    @Test func unknownInkKindDecodesAsPen() throws {
        let data = Data(#"["reed", "pencil"]"#.utf8)
        #expect(try JSONDecoder().decode([InkKind].self, from: data) == [.pen, .pencil])
    }
}
