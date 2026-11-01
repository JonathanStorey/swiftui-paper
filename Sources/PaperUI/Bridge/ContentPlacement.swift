import CoreGraphics
import SwiftUI

/// Content-mode math (PLAN 5.1). Pure functions, so they are unit tested without a view.
extension PaperContentPlacement {
    /// View points per page point when nothing is zoomed.
    func restingScale(view: CGSize, page: CGSize) -> CGFloat {
        guard view.width > 0, view.height > 0, page.width > 0, page.height > 0 else { return 1 }
        let sx = view.width / page.width
        let sy = view.height / page.height
        return switch mode {
        case .fit: min(sx, sy)
        case .fill: max(sx, sy)
        case .fitWidth: sx
        case .fitHeight: sy
        }
    }

    /// The page rectangle visible at rest, in page coordinates.
    ///
    /// In `.fit` the rectangle is larger than the page on the letterboxed axis, and the anchor
    /// decides where the extra space goes. In overflowing modes the anchor picks the scroll position.
    func restingVisibleRect(view: CGSize, page: CGSize, layoutDirection: LayoutDirection = .leftToRight) -> CGRect {
        visibleRect(view: view, page: page, scale: restingScale(view: view, page: page), layoutDirection: layoutDirection)
    }

    /// The rectangle seen at `scale` view points per page point, placed by the anchor.
    func visibleRect(view: CGSize, page: CGSize, scale: CGFloat, layoutDirection: LayoutDirection = .leftToRight) -> CGRect {
        let size = CGSize(width: view.width / scale, height: view.height / scale)
        var anchorX = anchor.x
        if layoutDirection == .rightToLeft { anchorX = 1 - anchorX }
        // Positive slack means the page overflows on that axis; negative means letterboxing.
        let slack = CGSize(width: page.width - size.width, height: page.height - size.height)
        return CGRect(x: slack.width * anchorX, y: slack.height * anchor.y, width: size.width, height: size.height)
    }

    /// Keeps `center` in view at `relativeZoom` times the resting scale for a new view size.
    func visibleRect(view: CGSize, page: CGSize, center: CGPoint, relativeZoom: CGFloat) -> CGRect {
        let scale = restingScale(view: view, page: page) * relativeZoom
        let size = CGSize(width: view.width / scale, height: view.height / scale)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
