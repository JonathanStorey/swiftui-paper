import CoreGraphics
import Foundation
import PaperKit
import PDFKit
import PencilKit
import Synchronization

extension Paper {
    // MARK: Reading content

    /// Every element, bottom to top.
    public var elements: [Paper.Element] {
        projections.elements { markup.subelements.map(Paper.Element.init) }
    }

    /// Every ink stroke, bottom to top.
    public var strokes: [Paper.Stroke] {
        projections.strokes { markup.subelements.strokes.map(Paper.Stroke.init) }
    }

    // MARK: Editing content

    /// Adds `other`'s elements on top. Element IDs are kept. `other`'s size and background are ignored.
    public mutating func append(_ other: Paper) {
        markup.append(contentsOf: other.markup)
    }

    // MARK: Locking

    /// Makes elements read-only: they can't be selected, moved, resized, restyled, erased, or deleted.
    public mutating func lock(_ ids: some Collection<Paper.Element.ID>) {
        setInteractions(.readOnly, for: Set(ids.map(\.raw)))
    }

    public mutating func unlock(_ ids: some Collection<Paper.Element.ID>) {
        setInteractions(.all, for: Set(ids.map(\.raw)))
    }

    /// Locks every element, for example to submit or sign off a page. New drawing goes on top as editable elements.
    public mutating func lockAll() {
        setInteractions(.readOnly, for: nil)
    }

    /// Restores full interaction on every element. Locking is lossless.
    public mutating func unlockAll() {
        setInteractions(.all, for: nil)
    }

    /// Rebuilds the element set in order with new interactions. `nil` means every element.
    private mutating func setInteractions(_ interactions: MarkupInteractions, for ids: Set<MarkupOrderedSet.ElementID>?) {
        guard ids.map({ !$0.isEmpty }) ?? true else { return }
        var updated = MarkupOrderedSet()
        updated.append(contentsOf: markup.subelements.map { element in
            var element = element
            if ids?.contains(element.elementID) ?? true {
                element.allowedInteractions = interactions
            }
            return element
        })
        markup.subelements = updated
    }

    // MARK: Size and rotation

    /// Turns the page by a quarter or half turn. Content, IDs, and locks are kept, and the background turns with it.
    public mutating func rotate(_ turn: Paper.Rotation) {
        let old = size.size
        let transform: CGAffineTransform
        let newSize: CGSize
        switch turn {
        case .clockwise:
            // (x, y) → (H − y, x) in top-left page coordinates.
            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: old.height, ty: 0)
            newSize = CGSize(width: old.height, height: old.width)
        case .counterclockwise:
            // (x, y) → (y, W − x)
            transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: old.width)
            newSize = CGSize(width: old.height, height: old.width)
        case .halfTurn:
            transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: old.width, ty: old.height)
            newSize = old
        }
        var updated = markup
        updated.transformContent(transform)
        updated.bounds = CGRect(origin: .zero, size: newSize)
        let rotatedBackground = background.map { $0.rotated(turn) }
        // One mutation per property; markup last so observers see the finished page.
        background = rotatedBackground
        markup = updated
    }

    /// Changes the page size. With `scalingContent`, content scales to the new size; otherwise this is the same as setting `size`.
    public mutating func resize(to newSize: Paper.Size, scalingContent: Bool) {
        guard scalingContent else {
            size = newSize
            return
        }
        let old = size.size
        guard old.width > 0, old.height > 0 else {
            size = newSize
            return
        }
        var updated = markup
        updated.transformContent(CGAffineTransform(scaleX: newSize.size.width / old.width, y: newSize.size.height / old.height))
        updated.bounds = CGRect(origin: .zero, size: newSize.size)
        markup = updated
    }

    public enum Rotation: Hashable, Sendable, CaseIterable {
        case clockwise, counterclockwise, halfTurn
    }
}

// MARK: - Background rotation

extension Paper.Background {
    func rotated(_ turn: Paper.Rotation) -> Paper.Background {
        let degrees = switch turn {
        case .clockwise: 90
        case .counterclockwise: -90
        case .halfTurn: 180
        }
        switch self {
        case .pdfPage(let data):
            guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return self }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
            return document.dataRepresentation().map(Paper.Background.pdfPage) ?? self
        case .image(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let rotated = image.rotated(degrees),
                  let png = Paper.pngData(rotated)
            else { return self }
            return .image(png)
        }
    }
}

extension CGImage {
    /// The image turned clockwise by a multiple of 90 degrees, by whole pixels.
    func rotated(_ degrees: Int) -> CGImage? {
        let quarterTurn = degrees % 180 != 0
        let outWidth = quarterTurn ? height : width
        let outHeight = quarterTurn ? width : height
        guard let context = CGContext(
            data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Core Graphics is y-up, so a clockwise turn on screen is a negative angle here.
        context.translateBy(x: CGFloat(outWidth) / 2, y: CGFloat(outHeight) / 2)
        context.rotate(by: -CGFloat(degrees) * .pi / 180)
        context.draw(self, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }
}

// MARK: - Projection cache

extension Paper {
    /// Lazily computed `elements` and `strokes`. Replaced on every mutation, so it never goes stale,
    /// and guarded by a `Mutex` so `Paper` stays `Sendable`.
    final class Projections: Sendable {
        private struct State {
            var elements: [Paper.Element]?
            var strokes: [Paper.Stroke]?
        }

        private let state = Mutex(State())

        func elements(_ make: () -> [Paper.Element]) -> [Paper.Element] {
            if let cached = state.withLock({ $0.elements }) { return cached }
            let made = make()
            state.withLock { $0.elements = made }
            return made
        }

        func strokes(_ make: () -> [Paper.Stroke]) -> [Paper.Stroke] {
            if let cached = state.withLock({ $0.strokes }) { return cached }
            let made = make()
            state.withLock { $0.strokes = made }
            return made
        }
    }
}
