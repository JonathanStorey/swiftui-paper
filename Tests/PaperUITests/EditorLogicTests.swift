import CoreGraphics
import PencilKit
import SwiftUI
import Testing
@testable import PaperUI

struct ContentPlacementTests {
    let page = CGSize(width: 612, height: 792)
    let portrait = CGSize(width: 834, height: 1194)
    let landscape = CGSize(width: 1194, height: 834)

    @Test func restingScales() {
        #expect(PaperContentPlacement(mode: .fit, anchor: .center).restingScale(view: landscape, page: page) == 834.0 / 792)
        #expect(PaperContentPlacement(mode: .fill, anchor: .center).restingScale(view: landscape, page: page) == 1194.0 / 612)
        #expect(PaperContentPlacement(mode: .fitWidth, anchor: .top).restingScale(view: landscape, page: page) == 1194.0 / 612)
        #expect(PaperContentPlacement(mode: .fitHeight, anchor: .leading).restingScale(view: portrait, page: page) == 1194.0 / 792)
    }

    @Test func fitWidthTopStartsAtTheTop() {
        let rect = PaperContentPlacement(mode: .fitWidth, anchor: .top).restingVisibleRect(view: landscape, page: page)
        #expect(rect.minX == 0)
        #expect(rect.minY == 0)
        #expect(abs(rect.width - 612) < 0.001)
        #expect(rect.height < page.height)
    }

    @Test func fitCenterSplitsTheLetterbox() {
        let rect = PaperContentPlacement(mode: .fit, anchor: .center).restingVisibleRect(view: landscape, page: page)
        #expect(abs(rect.height - 792) < 0.001)
        #expect(abs(rect.midX - 306) < 0.001)
    }

    @Test func leadingFlipsInRightToLeft() {
        let placement = PaperContentPlacement(mode: .fitHeight, anchor: .leading)
        let ltr = placement.restingVisibleRect(view: portrait, page: CGSize(width: 2000, height: 792))
        let rtl = placement.restingVisibleRect(view: portrait, page: CGSize(width: 2000, height: 792), layoutDirection: .rightToLeft)
        #expect(ltr.minX == 0)
        #expect(abs(rtl.maxX - 2000) < 0.001)
    }

    @Test func rotationKeepsCenterAndRelativeZoom() {
        let placement = PaperContentPlacement(mode: .fit, anchor: .center)
        let rect = placement.visibleRect(view: landscape, page: page, center: CGPoint(x: 100, y: 200), relativeZoom: 2)
        #expect(abs(rect.midX - 100) < 0.001)
        #expect(abs(rect.midY - 200) < 0.001)
        #expect(abs(landscape.width / rect.width - 2 * placement.restingScale(view: landscape, page: page)) < 0.001)
    }
}

struct ToolConversionTests {
    @Test(arguments: [Paper.Tool.pen(.red, width: 5), .pencil(.blue), .marker(.yellow), .reed(.black), .eraser, .eraser(.bitmap(width: 12)), .lasso])
    func roundTripsThroughPencilKit(tool: Paper.Tool) throws {
        let pkTool = try #require(tool.pkTool)
        let back = try #require(Paper.Tool(pkTool))
        switch (tool, back) {
        case (.ink(let a, _), .ink(let b, _)):
            #expect(a.kind == b.kind)
            #expect(abs(a.color.red - b.color.red) < 0.001 && abs(a.color.blue - b.color.blue) < 0.001)
        case (.eraser(.bitmap(width: .some)), .eraser(.bitmap(width: .some))):
            break   // PencilKit clamps the width
        default:
            #expect(back == tool)
        }
        // PencilKit clamps widths (a pencil is at least 2.4 pt), so the read-back value is a fixed point.
        // The editor relies on this to stop a tool write-back loop.
        #expect(Paper.Tool(try #require(back.pkTool)) == back)
    }

    @Test func customHasNoPencilKitTool() {
        #expect(Paper.Tool.custom(id: "stamp").pkTool == nil)
    }

    @Test func featuresMapToFeatureSet() {
        let set = Paper.Features.latest.removing(.text).featureSet
        #expect(!set.contains(.text))
        #expect(set.contains(.drawing))
        #expect(set.inks.count == Paper.Ink.Kind.allCases.count)
    }
}
