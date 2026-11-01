import CoreGraphics
import PaperKit
import SwiftUI
import Testing
@testable import PaperUI

struct ScrollPositionTests {
    @Test func eachRequestIsNew() {
        var position = PaperScrollPosition()
        #expect(position.visibleRect == nil)
        position.zoomToFit()
        let first = position.request
        position.zoomToFit()
        #expect(position.request != first, "the same request twice must still run twice")
        position.scrollTo(rect: CGRect(x: 0, y: 0, width: 10, height: 10), zoom: false)
        guard case .rect(_, nil, false) = position.request?.target else { Issue.record("expected a rect request"); return }
    }

    @Test @MainActor func alignWithoutZoomKeepsSizeAndCenters() {
        let visible = CGRect(x: 0, y: 0, width: 300, height: 400)
        let rect = PaperEditorController.rect(keepingSizeOf: visible, aligning: CGRect(x: 500, y: 600, width: 20, height: 20), anchor: .center)
        #expect(rect.size == visible.size)
        #expect(rect.midX == 510 && rect.midY == 610)
        let top = PaperEditorController.rect(keepingSizeOf: visible, aligning: CGRect(x: 500, y: 600, width: 20, height: 20), anchor: .top)
        #expect(top.minY == 600)
    }
}

struct AdornmentTests {
    @Test func mapsToMarkupAdornment() throws {
        let adornment = PaperAdornment(location: CGPoint(x: 40, y: 50), image: .systemImage("star.fill"), dragRegion: .canvas, scalesWithZoom: true)
        let markup = adornment.markupAdornment
        #expect(markup.id == adornment.id)
        #expect(markup.dragRegion == .canvas)
        #expect(markup.scalesWithZoom)
        #expect(markup.anchor.location(in: PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))) == CGPoint(x: 40, y: 50))
        #expect(PaperAdornment(location: .zero).markupAdornment.dragRegion == .fixed)
    }
}
