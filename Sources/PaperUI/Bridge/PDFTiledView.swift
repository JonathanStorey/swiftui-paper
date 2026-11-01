import PDFKit
import QuartzCore
import SwiftUI

/// Draws a PDF page stretched to its bounds, tile by tile, so it stays sharp at every zoom.
///
/// The drawing lives in a `CATiledLayer` subclass rather than the view, because tiles draw on
/// background threads and the view is main-actor isolated.
final class PDFTiledLayer: CATiledLayer {
    /// Set once on the main thread before the first draw, then only read.
    nonisolated(unsafe) var page: CGPDFPage? {
        didSet { setNeedsDisplay() }
    }

    override class func fadeDuration() -> CFTimeInterval { 0 }

    override init() {
        super.init()
        tileSize = CGSize(width: 512, height: 512)
        levelsOfDetail = 1
        levelsOfDetailBias = 5   // sharp up to 32x
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        page = (layer as? PDFTiledLayer)?.page
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(in context: CGContext) {
        guard let page else { return }
        #if !os(macOS)
        // UIKit layers are y-down; the PDF drawing below expects y-up.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        #endif
        page.drawStretched(in: context, to: bounds.size)
    }
}

extension CGPDFPage {
    /// Draws the page, honoring its /Rotate, stretched to `size` in a y-up context.
    func drawStretched(in context: CGContext, to size: CGSize) {
        let box = getBoxRect(.mediaBox)
        let quarterTurn = (rotationAngle / 90) % 2 != 0
        let displayed = quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
        guard displayed.width > 0, displayed.height > 0 else { return }
        context.saveGState()
        context.scaleBy(x: size.width / displayed.width, y: size.height / displayed.height)
        context.concatenate(getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: displayed), rotate: 0, preserveAspectRatio: false))
        context.drawPDFPage(self)
        context.restoreGState()
    }
}

#if os(macOS)
final class PDFTiledView: NSView {
    init(page: CGPDFPage?) {
        super.init(frame: .zero)
        wantsLayer = true
        tiledLayer.page = page
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer { PDFTiledLayer() }
    override var isFlipped: Bool { true }
    var tiledLayer: PDFTiledLayer { layer as! PDFTiledLayer }
}
#else
final class PDFTiledView: UIView {
    init(page: CGPDFPage?) {
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        tiledLayer.page = page
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override class var layerClass: AnyClass { PDFTiledLayer.self }
    var tiledLayer: PDFTiledLayer { layer as! PDFTiledLayer }
}
#endif

// MARK: - SwiftUI

/// A PDF page drawn with tiles, so it is sharp at every size. Keeps the page's aspect ratio.
///
/// This is the view `PaperEditor(paper:on:)` uses for a PDF page, usable on its own.
public struct PDFPageView: View {
    let page: PDFPage

    public init(_ page: PDFPage) {
        self.page = page
    }

    public var body: some View {
        PDFTiledRepresentable(page: page)
            .aspectRatio(Paper.Size(page).size, contentMode: .fit)
    }
}

#if os(macOS)
private struct PDFTiledRepresentable: NSViewRepresentable {
    let page: PDFPage
    func makeNSView(context: Context) -> PDFTiledView { PDFTiledView(page: page.pageRef) }
    func updateNSView(_ view: PDFTiledView, context: Context) {
        if view.tiledLayer.page !== page.pageRef { view.tiledLayer.page = page.pageRef }
    }
}
#else
private struct PDFTiledRepresentable: UIViewRepresentable {
    let page: PDFPage
    func makeUIView(context: Context) -> PDFTiledView { PDFTiledView(page: page.pageRef) }
    func updateUIView(_ view: PDFTiledView, context: Context) {
        if view.tiledLayer.page !== page.pageRef { view.tiledLayer.page = page.pageRef }
    }
}
#endif

/// The background a `Paper` stores: an image stretched to the page, or a PDF page.
public struct PaperBackgroundView: View {
    let background: Paper.Background?

    init(_ background: Paper.Background?) {
        self.background = background
    }

    public var body: some View {
        switch background {
        case .image(let data):
            if let image = CGImage.decoded(from: data) {
                Image(decorative: image, scale: 1).resizable()
            }
        case .pdfPage(let data):
            if let page = PDFDocument(data: data)?.page(at: 0) {
                PDFTiledRepresentable(page: page)
            }
        case nil:
            EmptyView()
        }
    }
}

extension CGImage {
    static func decoded(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
