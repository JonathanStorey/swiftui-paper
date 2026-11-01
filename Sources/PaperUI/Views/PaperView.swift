import PDFKit
import SwiftUI

/// A read-only rendering of a `Paper`, also used for thumbnails.
///
/// It renders a bitmap at its laid-out size times `\.displayScale`, so a 120 pt thumbnail costs a
/// 120 pt render. Its ideal size is the paper size and it keeps the page's aspect ratio, so
/// `.frame(width: 120)` gives a correctly shaped thumbnail. Rendering is asynchronous like
/// `AsyncImage`; the paper color shows until it finishes.
///
/// For a zoomable read-only page, use `PaperEditor(...).disabled(true)`. `ImageRenderer` can't
/// capture the async render; use `paper.image(scale:)` instead.
public struct PaperView<Background: View>: View {
    private let paper: Paper
    private let background: Background?

    /// A paper over any SwiftUI view, stretched to the page.
    public init(_ paper: Paper, @ViewBuilder on background: () -> Background) {
        self.paper = paper
        self.background = background()
    }

    private init(paper: Paper, background: Background?) {
        self.paper = paper
        self.background = background
    }

    public var body: some View {
        PaperRendering(paper: paper, includesStoredBackground: background == nil) {
            if let background { background }
        }
    }
}

extension PaperView where Background == PaperBackgroundView {
    /// A paper with its stored background, if any.
    public init(_ paper: Paper) {
        self.init(paper: paper, background: nil)
    }
}

extension PaperView where Background == Image {
    public init(_ paper: Paper, on image: Image) {
        self.init(paper: paper, background: image.resizable())
    }
}

extension PaperView where Background == PDFPageView {
    public init(_ paper: Paper, on page: PDFPage) {
        self.init(paper: paper, background: PDFPageView(page))
    }
}

/// Lays out the page and runs the render.
private struct PaperRendering<Underlay: View>: View {
    let paper: Paper
    let includesStoredBackground: Bool
    @ViewBuilder let underlay: Underlay

    @Environment(\.displayScale) private var displayScale
    @State private var size: CGSize = .zero
    @State private var rendered: (key: RenderKey, image: CGImage)?

    var body: some View {
        let pageSize = paper.size.size
        let key = RenderKey(token: paper.token, size: size, scale: displayScale, includesBackground: includesStoredBackground)
        ZStack {
            (paper.color ?? .white).color
            underlay
            if let rendered {
                Image(decorative: rendered.image, scale: displayScale).resizable()
            }
        }
        .aspectRatio(pageSize, contentMode: .fit)
        .frame(idealWidth: pageSize.width, idealHeight: pageSize.height)
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .task(id: key) {
            guard key.size.width > 0, key.size.height > 0 else { return }
            if let cached = RenderCache.shared.image(for: key) {
                rendered = (key, cached)
                return
            }
            let box = CGSize(width: key.size.width * key.scale, height: key.size.height * key.scale)
            guard let image = try? await paper.render(scale: paper.scale(fitting: box), includeBackground: key.includesBackground),
                  !Task.isCancelled
            else { return }
            RenderCache.shared.insert(image, for: key)
            rendered = (key, image)
        }
    }
}

struct RenderKey: Hashable, Sendable {
    let token: UUID
    let size: CGSize
    let scale: CGFloat
    let includesBackground: Bool
}

/// Process-wide cache of `PaperView` renders, so scrolling a grid of thumbnails doesn't re-render.
final class RenderCache: Sendable {
    static let shared = RenderCache()

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private final class Key: NSObject {
        let key: RenderKey
        init(_ key: RenderKey) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? Key)?.key == key }
    }

    /// NSCache is thread-safe.
    nonisolated(unsafe) private let cache: NSCache<Key, Entry> = {
        let cache = NSCache<Key, Entry>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func image(for key: RenderKey) -> CGImage? {
        cache.object(forKey: Key(key))?.image
    }

    func insert(_ image: CGImage, for key: RenderKey) {
        cache.setObject(Entry(image), forKey: Key(key), cost: image.bytesPerRow * image.height)
    }
}
