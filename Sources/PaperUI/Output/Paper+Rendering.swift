import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import PaperKit
import UniformTypeIdentifiers

extension Paper {
    // MARK: Images

    /// A bitmap of the page. `scale` is pixels per point: `1.0` on letter gives 612 × 792 px.
    public func image(scale: Double) async throws -> CGImage {
        try await render(scale: scale, includeBackground: true)
    }

    /// The largest image with the page's aspect ratio that fits `box`, in pixels.
    public func image(fitting box: CGSize) async throws -> CGImage {
        try await image(scale: scale(fitting: box))
    }

    func scale(fitting box: CGSize) -> Double {
        let page = size.size
        guard page.width > 0, page.height > 0 else { return 1 }
        return min(box.width / page.width, box.height / page.height)
    }

    /// Renders into a new bitmap. Without the background the paper is transparent, for drawing
    /// over a background the app supplies.
    func render(scale: Double, includeBackground: Bool) async throws -> CGImage {
        let page = size.size
        let width = max(1, Int((page.width * scale).rounded()))
        let height = max(1, Int((page.height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderingError.contextUnavailable }
        context.scaleBy(x: CGFloat(width) / page.width, y: CGFloat(height) / page.height)
        await draw(in: context, includeBackground: includeBackground)
        guard let image = context.makeImage() else { throw RenderingError.contextUnavailable }
        return image
    }

    // MARK: PDF

    /// A one-page PDF of the paper: the background, then every element.
    ///
    /// The background, shapes, and text are vector. PaperKit rasterizes ink in PDF output at about
    /// 144 dpi, so ink is drawn as a 300 dpi image cropped to the ink's bounds (PLAN 5.3 fallback).
    /// Phase 4 adds an invisible text layer so the PDF is searchable.
    public func pdfData() async throws -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size.size)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw RenderingError.contextUnavailable }

        // MarkupOrderedSet lists every non-ink element below every stroke, so drawing the
        // vector layer first and the ink on top keeps PaperKit's stacking order.
        var vectorLayer = self
        // `subelements.removeAll(where:)` leaves strokes in place (SDK-FINDINGS F), so remove them by ID.
        vectorLayer.withMarkup { markup in
            for stroke in markup.subelements.strokes { markup.subelements.removeStroke(for: stroke.id) }
        }
        var inkLayer = self
        inkLayer.withMarkup { $0.subelements.removeAll { !$0.elementID.isStroke } }
        let ink = try await inkLayer.inkImage(dpi: 300)

        context.beginPDFPage(nil)
        await vectorLayer.draw(in: context, includeBackground: true)
        if let ink {
            // `rect` is in top-left page coordinates; the PDF context is y-up.
            context.draw(ink.image, in: CGRect(x: ink.rect.minX, y: box.height - ink.rect.maxY, width: ink.rect.width, height: ink.rect.height))
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// Ink only, transparent, cropped to its render frame.
    private func inkImage(dpi: Double) async throws -> (image: CGImage, rect: CGRect)? {
        let rect = markup.contentsRenderFrame.intersection(CGRect(origin: .zero, size: size.size)).integral
        guard !isEmpty, !rect.isEmpty else { return nil }
        let scale = dpi / 72
        guard let context = CGContext(
            data: nil, width: Int(rect.width * scale), height: Int(rect.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderingError.contextUnavailable }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -(size.size.height - rect.maxY))
        await draw(in: context, includeBackground: false)
        guard let image = context.makeImage() else { throw RenderingError.contextUnavailable }
        return (image, rect)
    }

    // MARK: Drawing

    /// Draws the page into a y-up context whose user space is page points.
    func draw(in context: CGContext, includeBackground: Bool) async {
        let page = CGRect(origin: .zero, size: size.size)
        if includeBackground {
            context.setFillColor((color ?? .white).cgColor)
            context.fill(page)
            background?.draw(in: context, page: page)
        }
        // PaperKit draws in top-left page coordinates.
        context.saveGState()
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        await markup.draw(in: context, frame: page)
        context.restoreGState()
    }

    enum RenderingError: Error {
        case contextUnavailable
    }
}

extension MarkupOrderedSet.ElementID {
    var isStroke: Bool {
        if case .stroke = self { true } else { false }
    }
}

extension Paper.Background {
    /// Draws the background stretched to `page` in a y-up context.
    func draw(in context: CGContext, page: CGRect) {
        switch self {
        case .image(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return }
            context.draw(image, in: page)
        case .pdfPage(let data):
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  let pdfPage = document.page(at: 1)
            else { return }
            context.saveGState()
            // Honors the page's /Rotate, so a rotated paper draws its background upright.
            let box = pdfPage.getBoxRect(.mediaBox)
            let quarterTurn = (pdfPage.rotationAngle / 90) % 2 != 0
            let displayed = quarterTurn ? CGSize(width: box.height, height: box.width) : box.size
            context.scaleBy(x: page.width / displayed.width, y: page.height / displayed.height)
            context.concatenate(pdfPage.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: displayed), rotate: 0, preserveAspectRatio: false))
            context.drawPDFPage(pdfPage)
            context.restoreGState()
        }
    }
}

// MARK: - Transferable

extension UTType {
    /// A saved `Paper` (`dataRepresentation()`), extension `swiftpaper`. Apps that share or open it
    /// declare it under `UTExportedTypeDeclarations` in their Info.plist.
    public static let swiftPaper = UTType(exportedAs: "org.swiftuipaper.paper", conformingTo: .data)
}

extension Paper: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .swiftPaper) { paper in
            try await paper.dataRepresentation()
        } importing: { data in
            try Paper(dataRepresentation: data)
        }
        DataRepresentation(exportedContentType: .pdf) { paper in
            try await paper.pdfData()
        }
        DataRepresentation(exportedContentType: .png) { paper in
            try await paper.pngData(scale: 2)
        }
    }

    func pngData(scale: Double) async throws -> Data {
        guard let png = Paper.pngData(try await image(scale: scale)) else { throw RenderingError.contextUnavailable }
        return png
    }
}
