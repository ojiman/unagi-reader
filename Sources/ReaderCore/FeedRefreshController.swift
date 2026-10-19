import Foundation
import SwiftData
import Observation

@Observable @MainActor public final class FeedRefreshController {
    public private(set) var refreshing = false
    public private(set) var errors: [UUID: String] = [:]
    private let store: ReaderStore
    private let client: FeedClient
    private let batchDelay: Duration
    /// Tests pass a long `batchDelay` so that only the batch size and the end of the fetches decide the batches.
    public init(store: ReaderStore, client: FeedClient = FeedClient(), batchDelay: Duration = .milliseconds(500)) {
        self.store = store; self.client = client; self.batchDelay = batchDelay
    }
    private struct Request: Sendable { let id: UUID; let url: URL; let etag: String?; let modified: String? }
    private enum Event: Sendable { case fetched(Request, Result<FeedFetchResult, any Error>), due }
    /// Fetched feeds are applied together (one save, one list reload) when this many are in, or when the first of them
    /// has waited this long, or when the last fetch ends (#131). A slow feed does not hold back the others.
    nonisolated static let batchSize = 4
    public func refresh(feedIDs: [UUID]? = nil, at: Date = .now) async {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        let requested = feedIDs.map(Set.init)
        let feeds = store.feeds.compactMap { feed -> Request? in
            guard requested == nil || requested!.contains(feed.id), let source = feed.sourceURL,
                  let url = ArticleURL.validated(source) else { return nil }
            return Request(id: feed.id, url: url, etag: feed.etag, modified: feed.lastModified)
        }
        await withTaskGroup(of: Event.self) { group in
            var iterator = feeds.makeIterator()
            var fetching = 0, waiting = false
            var pending: [FetchedFeed] = []
            func enqueue(_ request: Request) {
                let client = self.client
                fetching += 1
                group.addTask { .fetched(request, await Result { try await client.fetch(url: request.url, etag: request.etag, lastModified: request.modified) }) }
            }
            var applied = false
            let writer = RefreshWriter(container: store.container, saveHook: store.saveHook)
            @MainActor func applyPending() async {
                guard !pending.isEmpty, !Task.isCancelled else { return }
                let batch = pending
                pending = []
                let failed = await store.applyRefreshes(batch, at: at, writer: writer)
                for item in batch { errors[item.feedID] = failed[item.feedID]?.localizedDescription }
                applied = true
            }
            for _ in 0..<3 { if let request = iterator.next() { enqueue(request) } }
            while let event = await group.next() {
                switch event {
                case .fetched(let request, let result):
                    fetching -= 1
                    guard !Task.isCancelled else { break }
                    switch result {
                    case .success(let fetched):
                        pending.append(FetchedFeed(feedID: request.id, sourceURL: request.url.absoluteString, result: fetched))
                    case .failure(let error):
                        if store.feeds.contains(where: { $0.id == request.id && $0.sourceURL == request.url.absoluteString }) { errors[request.id] = error.localizedDescription }
                    }
                    if let next = iterator.next() { enqueue(next) }
                    if pending.count >= Self.batchSize { await applyPending() }
                    else if !pending.isEmpty && !waiting {
                        waiting = true
                        let delay = batchDelay
                        group.addTask { try? await Task.sleep(for: delay); return .due }
                    }
                case .due:
                    waiting = false
                    await applyPending()
                }
                if fetching == 0 { await applyPending(); group.cancelAll() }          // the last fetch ended: no need to wait
                // A finished fetch makes `next()` return without suspending; after a batch, let the window have a turn.
                if applied { applied = false; await Task.yield() }
            }
        }
        errors = errors.filter { id, _ in store.feeds.contains { $0.id == id } }
    }
}

private extension Result where Failure == any Error {
    init(_ body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

/// A feed's answer, kept until its batch is applied. The address is the one fetched: a subscription whose address changed meanwhile is skipped.
struct FetchedFeed: Sendable { let feedID: UUID; let sourceURL: String; let result: FeedFetchResult }

extension ReaderStore {
    /// Applies several fetched feeds with one save and one committed list update (#131, #303). `writer` merges and saves them off the main
    /// thread (plan "Refresh merge off the main thread"); the main actor then refetches what it wrote and publishes it. Returns the feeds
    /// that could not be applied.
    /// `afterWrite` lets a test change the library while the batch is written.
    func applyRefreshes(_ fetched: [FetchedFeed], at: Date, writer: RefreshWriter? = nil, afterWrite: (() -> Void)? = nil) async -> [UUID: any Error] {
        do { try reloadIfNeeded() } catch { return Dictionary(fetched.map { ($0.feedID, error) }, uniquingKeysWith: { first, _ in first }) }
        // A subscription removed, or given another address, since its fetch is skipped; the writer checks again when it writes.
        let items = fetched.filter { feed(id: $0.feedID)?.sourceURL == $0.sourceURL }
        guard !items.isEmpty else { return [:] }
        let writer = writer ?? RefreshWriter(container: container, saveHook: saveHook)
        let generation = libraryGeneration
        let result = await writer.apply(items, at: at, retentionDays: retentionDays, generation: generation)
        afterWrite?()
        do {
            if libraryGeneration != generation || needsReload {
                // The library changed while the batch was written (or must be reloaded anyway): its result may not fit the shown
                // state, so everything is loaded from the store, including what the batch saved.
                try reload()
            } else {
                try publish(result)
            }
        } catch {
            // Saved, but not shown. Report it, then recover from the committed store.
            rollback()
            return Dictionary(items.map { ($0.feedID, error) }, uniquingKeysWith: { first, _ in first })
        }
        return result.errors
    }
    /// The library context fetches the batch's feeds, changed articles and new memberships again, once each, so its instances take the
    /// saved values and the new ones are registered; then the lists and counts are updated from them.
    private func publish(_ result: BatchResult) throws {
        let feedIDs = result.feedIDs, ids = result.changedArticleIDs, keys = result.newMembershipKeys
        if !feedIDs.isEmpty { _ = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { feedIDs.contains($0.id) })) }
        let changed = ids.isEmpty ? [] : try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) }))
        let joined = keys.isEmpty ? [] : try context.fetch(FetchDescriptor<FeedMembership>(predicate: #Predicate { keys.contains($0.key) }))
        guard changed.count == Set(ids).count, joined.count == Set(keys).count else { throw CocoaError(.fileReadUnknown) }
        try publishRefresh(changedArticles: Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) }), newMemberships: joined,
                           titlesChanged: result.titlesChanged)
    }
    public func applyRefresh(_ result: FeedFetchResult, to feed: Feed, at: Date) throws {
        try reloadIfNeeded()
        guard let feed = self.feed(id: feed.id) else { return }
        switch result {
        case .notModified: break
        case .modified(let parsed, let etag, let modified):
            guard parsed.sourceURL.absoluteString == feed.sourceURL else { return }
            _ = try importFeed(parsed, receivedAt: at)
            feed.etag = etag; feed.lastModified = modified
        }
        try recordFetch(feed, etag: feed.etag, lastModified: feed.lastModified, at: at)
    }
    public func recordFetch(_ feed: Feed, etag: String?, lastModified: String?, at: Date) throws {
        try reloadIfNeeded()
        guard let feed = self.feed(id: feed.id) else { return }
        feed.etag = etag; feed.lastModified = lastModified; feed.lastFetchedAt = at
        try save(); try reload()
    }
}
