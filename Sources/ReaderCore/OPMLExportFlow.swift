import Foundation
import Observation

/// File ▸ 「OPMLを書き出す…」 (decision 0063): choose where to save, write the subscriptions as OPML, and show an error when the file
/// could not be written. The save panel and the write are injected for tests. Cancelling the panel is not an error.
@Observable @MainActor public final class OPMLExportFlow {
    /// The reason the last export failed; nil when there is nothing to tell.
    public private(set) var failure: String?
    /// True while the save panel is open: a second request is ignored instead of opening another panel.
    public private(set) var choosing = false
    private let store: ReaderStore
    private let chooseDestination: @MainActor (String) async -> URL?
    private let write: (Data, URL) throws -> Void
    private let now: () -> Date

    public init(store: ReaderStore, chooseDestination: @escaping @MainActor (String) async -> URL?,
                write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                now: @escaping () -> Date = { .now }) {
        self.store = store; self.chooseDestination = chooseDestination; self.write = write; self.now = now
    }

    /// Returns true when a file was written.
    @discardableResult public func start() async -> Bool {
        guard !choosing else { return false }
        choosing = true
        let date = now()
        let url = await chooseDestination(OPMLWriter.fileName(at: date))
        choosing = false
        guard let url else { return false }
        do {
            try write(OPMLWriter.data(feeds: store.opmlFeeds(), createdAt: date), url)
            return true
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    public func dismissFailure() { failure = nil }
}
