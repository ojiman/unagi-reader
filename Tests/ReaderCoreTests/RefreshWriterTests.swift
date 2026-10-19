import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Plan "Refresh merge off the main thread", step 2: the batch is merged and saved by `RefreshWriter` off the main thread, and the main
/// actor only refetches and publishes, or reloads when the library changed meanwhile.
@MainActor struct RefreshWriterTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private func parsed(_ source: String, _ entries: [(String, String)], title: String = "Feed") -> ParsedFeed {
        ParsedFeed(title: title, sourceURL: URL(string: source)!, entries: entries.map { path, name in
            ParsedEntry(sourceID: path, title: name, url: URL(string: "https://article.example/" + path), summary: name, body: name,
                        coverage: .feedProvided, publishedAt: at)
        }, skippedEntries: 0)
    }
    private func fetched(_ feed: Feed, _ entries: [(String, String)], title: String = "Feed") throws -> FetchedFeed {
        let source = try #require(feed.sourceURL)
        return FetchedFeed(feedID: feed.id, sourceURL: source, result: .modified(parsed(source, entries, title: title), etag: "v2", lastModified: nil))
    }

    @Test func theBatchIsWrittenOffTheMainThread() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let feed = try store.importFeed(parsed("https://feed.example/rss", [("a", "A")]), receivedAt: at)
        let writer = RefreshWriter(container: store.container)
        #expect(await store.applyRefreshes([try fetched(feed, [("a", "A2"), ("b", "B")])], at: at, writer: writer).isEmpty)
        #expect(await writer.lastRunOnMainThread == false)
        #expect(store.articles.count == 2 && store.articles.contains { $0.title == "A2" } && !store.context.hasChanges)
    }

    @Test func aSubscriptionRemovedBeforeItsBatchIsWrittenIsSkipped() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let kept = try store.importFeed(parsed("https://kept.example/rss", [("k", "K")]), receivedAt: at)
        let removed = try store.importFeed(parsed("https://removed.example/rss", [("r", "R")]), receivedAt: at)
        let items = [try fetched(kept, [("k", "K2")]), try fetched(removed, [("r", "R2"), ("r2", "R3")])]
        try store.unsubscribe(removed)
        let writer = RefreshWriter(container: store.container)
        let result = await writer.apply(items, at: at, retentionDays: store.retentionDays, generation: store.libraryGeneration)
        #expect(result.feedIDs == [kept.id] && result.errors.isEmpty)
        #expect(await store.applyRefreshes(items, at: at, writer: writer).isEmpty)
        #expect(!store.articles.contains { $0.title == "R3" } && store.feed(id: removed.id) == nil)
    }

    /// A read mark and a Star saved after the writer built its index are kept when a later batch updates the same article.
    @Test func aReadMarkAndAStarSurviveABatchThatUpdatesTheArticle() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let feed = try store.importFeed(parsed("https://feed.example/rss", [("a", "A"), ("b", "B")]), receivedAt: at)
        let writer = RefreshWriter(container: store.container)
        #expect(await store.applyRefreshes([try fetched(feed, [("a", "A"), ("b", "B")])], at: at, writer: writer).isEmpty)   // builds the index
        let article = try #require(store.articles.first { $0.title == "A" })
        try store.markDisplayed(articleID: article.id, at: at)
        try store.setStar(articleID: article.id, isStarred: true, at: at)
        #expect(await store.applyRefreshes([try fetched(feed, [("a", "A, changed"), ("b", "B")])], at: at.addingTimeInterval(60), writer: writer).isEmpty)
        #expect(article.title == "A, changed" && article.isRead && article.firstReadAt == at && article.starredAt == at)
        let reopened = try ReaderStore(url: library.url, now: at)
        let saved = try #require(reopened.article(id: article.id))
        #expect(saved.title == "A, changed" && saved.isRead && saved.firstReadAt == at && saved.starredAt == at)
    }

    /// The library changes while the batch is written: the store loads everything again instead of publishing the batch's result.
    @Test func aLibraryChangeDuringTheWriteReloadsInsteadOfPublishing() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let feed = try store.importFeed(parsed("https://feed.example/rss", [("a", "A")]), receivedAt: at)
        let other = try store.importFeed(parsed("https://other.example/rss", [("o", "O")]), receivedAt: at)
        let before = store.libraryGeneration
        let failed = await store.applyRefreshes([try fetched(feed, [("a", "A"), ("b", "B")])], at: at, afterWrite: {
            try? store.moveFeed(id: other.id, toFolder: "Moved")
        })
        #expect(failed.isEmpty && store.libraryGeneration > before + 1)          // the move, then the reload instead of the publication
        #expect(store.articles.count == 3 && store.feed(id: other.id)?.folder == "Moved")
        #expect(store.memberships.count == 3 && !store.context.hasChanges)
    }

    /// The writer's index is built again when the library changed between batches, so an article that came in another way is matched.
    @Test func theWriterRebuildsItsIndexAfterALibraryChange() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let feed = try store.importFeed(parsed("https://feed.example/rss", [("a", "A")]), receivedAt: at)
        let writer = RefreshWriter(container: store.container)
        #expect(await store.applyRefreshes([try fetched(feed, [("a", "A")])], at: at, writer: writer).isEmpty)
        // Another subscription brings a new article on the main actor, after the writer built its index: the generation changes.
        _ = try store.importFeed(parsed("https://other.example/rss", [("z", "Z")]), receivedAt: at)
        #expect(await store.applyRefreshes([try fetched(feed, [("a", "A"), ("z", "Z through the first feed")])], at: at, writer: writer).isEmpty)
        #expect(store.articles.filter { $0.originalURL == "https://article.example/z" }.count == 1)   // one article in both feeds, not two
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.articles.filter { $0.originalURL == "https://article.example/z" }.count == 1)
    }
}
