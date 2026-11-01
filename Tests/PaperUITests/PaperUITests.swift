import Testing
import PaperUI

struct PaperUITests {
    @Test func reexportsCoreTypes() {
        #expect(Markup(paperSize: .a4).paperSize == .a4)
    }
}
