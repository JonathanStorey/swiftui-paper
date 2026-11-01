import Foundation

/// The on-disk form of a `Paper`: a versioned binary property list.
///
/// The PaperKit blob is stored exactly as Apple produced it, so PaperKit handles its own versioning.
struct PaperFile: Codable {
    static let currentVersion = 1

    var version = PaperFile.currentVersion
    var markup: Data
    var background: Paper.Background?

    init(markup: Data, background: Paper.Background?) {
        self.markup = markup
        self.background = background
    }

    init(data: Data) throws {
        let header: Header
        do {
            header = try PropertyListDecoder().decode(Header.self, from: data)
        } catch {
            throw PaperFileError.incorrectFormat
        }
        guard header.version <= Self.currentVersion else { throw PaperFileError.formatTooNew(header.version) }
        self = try PropertyListDecoder().decode(PaperFile.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    private struct Header: Decodable {
        var version: Int
    }
}

enum PaperFileError: Error, Equatable {
    case incorrectFormat
    case formatTooNew(Int)
    case snapshotUnavailable
}
