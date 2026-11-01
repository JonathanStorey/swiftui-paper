import CoreGraphics
import Foundation
import PaperKit
@_exported import PaperModel

/// The content layer of a sheet: a value wrapper around `PaperMarkup`.
public struct Markup: Hashable, Sendable {
    /// The live PaperKit value, the single source of truth.
    package private(set) var paperMarkup: PaperMarkup {
        didSet { token = UUID() }
    }

    /// Regenerated on every mutation so equality checks are usually O(1).
    package private(set) var token = UUID()

    public init(paperSize: PaperSize = .letter) {
        self.paperMarkup = PaperMarkup(bounds: CGRect(origin: .zero, size: paperSize.size))
    }

    public init(dataRepresentation data: Data) throws {
        self.paperMarkup = try PaperMarkup(dataRepresentation: data)
    }

    package init(_ paperMarkup: PaperMarkup) {
        self.paperMarkup = paperMarkup
    }

    /// The page size. Reads and writes `PaperMarkup.bounds`, which is settable.
    public var paperSize: PaperSize {
        get { PaperSize(paperMarkup.bounds.size) }
        set { paperMarkup.bounds = CGRect(origin: .zero, size: newValue.size) }
    }

    public var isEmpty: Bool { paperMarkup.subelements.isEmpty }

    public func dataRepresentation() async throws -> Data {
        try await paperMarkup.dataRepresentation()
    }

    /// Escape hatch for PaperCore internals and tests.
    package mutating func withPaperMarkup<R>(_ body: (inout PaperMarkup) throws -> R) rethrows -> R {
        try body(&paperMarkup)
    }

    public static func == (lhs: Markup, rhs: Markup) -> Bool {
        lhs.token == rhs.token || lhs.paperMarkup == rhs.paperMarkup
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(paperSize)
    }
}
