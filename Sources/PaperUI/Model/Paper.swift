import CoreGraphics
import Foundation
import PaperKit
import PDFKit

/// One sheet of paper: ink, shapes, text boxes, and images over an optional background.
///
/// `Paper` is a value. Bind it to a `PaperEditor` the way you bind a `String` to a `TextEditor`.
public struct Paper: Sendable {
    /// The live PaperKit value: the single source of truth for content, size, and paper color.
    var markup: PaperMarkup {
        didSet { didMutate() }
    }

    public var background: Paper.Background? {
        didSet { didMutate() }
    }

    /// Regenerated on every mutation so equality checks are usually O(1).
    private(set) var token = UUID()

    /// The serialized markup that `Codable` writes. Refreshed in the background after each mutation.
    private(set) var snapshot: Snapshot

    /// `elements` and `strokes`, computed once per state.
    private(set) var projections = Projections()

    // MARK: Creating

    public init(size: Paper.Size = .letter, background: Paper.Background? = nil) {
        self.init(markup: PaperMarkup(bounds: CGRect(origin: .zero, size: size.size)), background: background)
    }

    /// A paper the size of `pdfPage`'s media box, with the page as its background.
    public init(pdfPage: PDFPage) {
        let document = PDFDocument()
        if let copy = pdfPage.copy() as? PDFPage {
            document.insert(copy, at: 0)
        }
        self.init(size: Paper.Size(pdfPage), background: document.dataRepresentation().map(Background.pdfPage))
    }

    /// A paper with `image` stretched to fill it.
    public init(image: CGImage, size: Paper.Size) {
        self.init(size: size, background: Self.pngData(image).map(Background.image))
    }

    public init(dataRepresentation data: Data) throws {
        let file = try PaperFile(data: data)
        self.init(markup: try PaperMarkup(dataRepresentation: file.markup), background: file.background, snapshot: file.markup)
    }

    init(markup: PaperMarkup, background: Paper.Background? = nil, snapshot: Data? = nil) {
        self.markup = markup
        self.background = background
        self.snapshot = Snapshot(markup: markup, token: token, previous: snapshot)
    }

    // MARK: Page

    /// Setting the size extends or crops the page from the bottom right. Content stays put.
    public var size: Paper.Size {
        get { Paper.Size(markup.bounds.size) }
        set { markup.bounds = CGRect(origin: .zero, size: newValue.size) }
    }

    /// The paper color. `nil` is PaperKit's default (white).
    public var color: Paper.Color? {
        get { markup.backgroundColor.flatMap(Paper.Color.init) }
        set { markup.backgroundColor = newValue?.cgColor }
    }

    public var isEmpty: Bool { markup.subelements.isEmpty }

    /// The rectangle, in page coordinates, that the content draws into.
    public var contentBounds: CGRect { markup.contentsRenderFrame }

    // MARK: Saving

    /// A versioned file holding the PaperKit content exactly as Apple produced it, plus the background bytes.
    public func dataRepresentation() async throws -> Data {
        let markupData = try await markup.dataRepresentation()
        snapshot.store(markupData, for: token)
        return try PaperFile(markup: markupData, background: background).encoded()
    }

    // MARK: Internal

    /// Replaces the content with what the editor produced, keeping the background.
    mutating func replaceMarkup(_ newMarkup: PaperMarkup) {
        markup = newMarkup
    }

    /// Escape hatch for module internals and tests.
    mutating func withMarkup<R>(_ body: (inout PaperMarkup) throws -> R) rethrows -> R {
        try body(&markup)
    }

    private mutating func didMutate() {
        token = UUID()
        snapshot = Snapshot(markup: markup, token: token, previous: snapshot.latest)
        projections = Projections()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - Equatable, Hashable

extension Paper: Hashable {
    public static func == (lhs: Paper, rhs: Paper) -> Bool {
        lhs.token == rhs.token || (lhs.markup == rhs.markup && lhs.background == rhs.background)
    }

    /// Hashes the size only, so hashing never walks the content.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(size)
    }
}

// MARK: - Codable

extension Paper: Codable {
    /// Writes the latest background-refreshed snapshot, which can trail the newest stroke briefly.
    /// Use `dataRepresentation()` when freshness matters.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(PaperFile(markup: try snapshot.latestOrWait(), background: background).encoded())
    }

    public init(from decoder: any Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        try self.init(dataRepresentation: data)
    }
}
