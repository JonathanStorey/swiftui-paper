import Foundation
import PaperKit
import Synchronization

extension Paper {
    /// Holds the serialized markup that `Codable` writes.
    ///
    /// Each mutation replaces the snapshot with a new one that starts from the previous data and
    /// refreshes itself in the background. A snapshot that is no longer referenced by any `Paper`
    /// skips the work, so a burst of mutations serializes only the last state.
    final class Snapshot: Sendable {
        private struct State {
            var data: Data?
            var isFresh: Bool
        }

        private let state: Mutex<State>
        let token: UUID

        init(markup: PaperMarkup, token: UUID, previous: Data?) {
            self.token = token
            self.state = Mutex(State(data: previous, isFresh: false))
            Task.detached(priority: .utility) { [weak self] in
                await Task.yield()
                guard self != nil, let data = try? await markup.dataRepresentation() else { return }
                self?.store(data, for: token)
            }
        }

        /// The newest data, which may describe an earlier state.
        var latest: Data? {
            state.withLock { $0.data }
        }

        /// True once the data matches this snapshot's token.
        var isFresh: Bool {
            state.withLock { $0.isFresh }
        }

        func store(_ data: Data, for token: UUID) {
            guard token == self.token else { return }
            state.withLock { $0 = State(data: data, isFresh: true) }
        }

        /// The newest data. Only a paper that has never been serialized waits for the first refresh.
        func latestOrWait(timeout: Duration = .seconds(5)) throws -> Data {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if let data = latest { return data }
                Thread.sleep(forTimeInterval: 0.002)
            }
            throw PaperFileError.snapshotUnavailable
        }

        /// Waits until the background refresh has caught up. For tests and the editor's save path.
        func waitUntilFresh() async {
            while !isFresh { try? await Task.sleep(for: .milliseconds(2)) }
        }
    }
}
