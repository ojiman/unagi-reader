import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// The refresh applies fetched feeds in batches: one save and one committed list update for several feeds, not two of each per feed (#131).
@MainActor struct RefreshBatchTests {
    private final class Counter: @unchecked Sendable {
        nonisolated(unsafe) var saves = 0, publications = 0
        nonisolated(unsafe) var failingSaves = 0, failingReloads = 0
    }
    private struct Library {
        let directory: URL
        let store: ReaderStore
        let ids: [UUID]
    }
    private func library(feeds count: Int, counter: Counter) throws -> Library {
        let directory = FileManager.default.temporaryDirectory.appending(path: "refresh-batch-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: directory.appending(path: "Reader.store"), cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, now: .now, saveHook: {
            counter.saves += 1
            if counter.failingSaves > 0 { counter.failingSaves -= 1; throw CocoaError(.fileWriteUnknown) }
        }, reloadHook: {
            counter.publications += 1
            if counter.failingReloads > 0 { counter.failingReloads -= 1; throw CocoaError(.fileReadUnknown) }
        })
        let list = (0..<count).map { OPMLFeed(title: "F\($0)", url: URL(string: "https://f\($0).example/feed")!, siteURL: nil, folder: "") }
        let ids = try store.importSubscriptions(list).addedFeedIDs
        return Library(directory: directory, store: store, ids: ids)
    }

    /// Long enough that no batch is applied by its delay, so the batches do not depend on how busy the main actor is
    /// (other main-actor tests of the same run can hold it for seconds).
    private let longDelay = Duration.seconds(600)
    /// Full batches and the rest when the last fetch ends.
    private func batches(_ feeds: Int) -> Int { (feeds + FeedRefreshController.batchSize - 1) / FeedRefreshController.batchSize }

    @Test func manyFeedsAreSavedAndPublishedOncePerBatch() async throws {
        let counter = Counter()
        let library = try library(feeds: 25, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds()), batchDelay: longDelay)
        counter.saves = 0; counter.publications = 0
        await refresh.refresh(feedIDs: library.ids)
        #expect(library.store.articles.count == 25 * 3 && refresh.errors.isEmpty)
        #expect(library.store.feeds.allSatisfy { $0.lastFetchedAt != nil && $0.etag == "v1" && $0.title == "Feed \($0.sourceURL ?? "")" })
        // Before batching: two saves and two publications for every feed (50 each).
        #expect(counter.saves == batches(25) && counter.publications == batches(25), "saves \(counter.saves), publications \(counter.publications)")
    }
    @Test func unchangedFeedsAreRecordedInBatchesToo() async throws {
        let counter = Counter()
        let library = try library(feeds: 25, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds()), batchDelay: longDelay)
        await refresh.refresh(feedIDs: library.ids)
        let first = Dictionary(uniqueKeysWithValues: library.store.feeds.map { ($0.id, $0.lastFetchedAt) })
        counter.saves = 0; counter.publications = 0
        await refresh.refresh(feedIDs: library.ids, at: .now.addingTimeInterval(60))     // every feed answers 304
        #expect(library.store.feeds.allSatisfy { $0.lastFetchedAt != first[$0.id] } && library.store.articles.count == 75)
        #expect(counter.saves == batches(25) && counter.publications == batches(25), "saves \(counter.saves), publications \(counter.publications)")   // was 25 each
    }
    @Test func anArticleTwoFeedsCarryInOneBatchIsOneArticleInBoth() async throws {
        let counter = Counter()
        let library = try library(feeds: 2, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds(shared: true)), batchDelay: longDelay)
        await refresh.refresh(feedIDs: library.ids)
        #expect(library.store.articles.count == 2 * 3 + 1)
        let shared = try #require(library.store.articles.first { $0.originalURL == "https://shared.example/p" })
        #expect(library.store.memberships.filter { $0.articleID == shared.id }.count == 2)
    }
    @Test func aBatchWhoseSaveFailsIsAppliedOneFeedAtATime() async throws {
        let counter = Counter()
        let library = try library(feeds: 4, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds()), batchDelay: longDelay)
        counter.failingSaves = 1
        await refresh.refresh(feedIDs: library.ids)
        #expect(library.store.articles.count == 4 * 3 && refresh.errors.isEmpty)
        #expect(library.store.feeds.allSatisfy { $0.lastFetchedAt != nil })
    }
    @Test func aFeedThatCannotBeSavedAloneIsTheOnlyOneWithAnError() async throws {
        let counter = Counter()
        let library = try library(feeds: 3, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds()), batchDelay: longDelay)
        counter.failingSaves = 2                                                   // the batch, then the first feed on its own
        await refresh.refresh(feedIDs: library.ids)
        #expect(refresh.errors.count == 1 && library.store.articles.count == 2 * 3)
    }
    @Test func aBatchSavedButNotPublishedShowsItsErrorAndTheNextRefreshWorks() async throws {
        let counter = Counter()
        let library = try library(feeds: 3, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds()), batchDelay: longDelay)
        counter.failingReloads = 1
        await refresh.refresh(feedIDs: library.ids)
        #expect(refresh.errors.count == 3)                                          // never reported as done
        #expect(library.store.articles.count == 3 * 3)                              // they were saved; the rollback loads them
        await refresh.refresh(feedIDs: library.ids, at: .now.addingTimeInterval(60))
        #expect(refresh.errors.isEmpty && library.store.articles.count == 3 * 3)
    }
    @Test func aFetchFailureMarksOnlyItsFeed() async throws {
        let counter = Counter()
        let library = try library(feeds: 3, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: StubFeeds(failing: "f1.example")))
        await refresh.refresh(feedIDs: library.ids)
        let failed = try #require(library.store.feeds.first { $0.sourceURL == "https://f1.example/feed" })
        #expect(Set(refresh.errors.keys) == [failed.id] && library.store.articles.count == 2 * 3)
    }
    @Test(.timeLimit(.minutes(5))) func aSlowFeedDoesNotHoldBackTheArticlesOfAFastOne() async throws {
        let counter = Counter()
        let library = try library(feeds: 2, counter: counter); defer { try? FileManager.default.removeItem(at: library.directory) }
        let stub = StubFeeds(held: "f1.example")
        let refresh = FeedRefreshController(store: library.store, client: FeedClient(http: stub))
        let running = Task { await refresh.refresh(feedIDs: library.ids) }
        // f1 waits until it is released, so f0's articles can only come from a batch applied without it. No wall-clock budget:
        // other main-actor tests of the same run hold the main actor (in CI the hosted UI tests delayed small suites by 85 s);
        // the time limit only ends a run that hangs.
        while library.store.articles.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(library.store.articles.count == 3 && refresh.refreshing)
        await stub.release()
        await running.value
        #expect(library.store.articles.count == 6)
    }
}

/// Every feed has three entries of its own (and one shared address when asked), answers 304 once it has given an etag,
/// and can fail or wait for its host.
private actor StubFeeds: HTTPFetching {
    let shared: Bool, failing: String?, held: String?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
    init(shared: Bool = false, failing: String? = nil, held: String? = nil) { self.shared = shared; self.failing = failing; self.held = held }
    func release() { released = true; waiting.forEach { $0.resume() }; waiting = [] }
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
        let host = url.host ?? ""
        if host == held && !released { await withCheckedContinuation { waiting.append($0) } }
        if host == failing { return HTTPResponse(data: Data(), finalURL: url, statusCode: 500, headers: [:]) }
        if headers["If-None-Match"] == "v1" { return HTTPResponse(data: Data(), finalURL: url, statusCode: 304, headers: [:]) }
        var items = (0..<3).map { "<item><guid>\(host)-\($0)</guid><title>\(host) \($0)</title><link>https://\(host)/a\($0)</link><description>s</description></item>" }
        if shared { items.append("<item><guid>shared-\(host)</guid><title>Shared</title><link>https://shared.example/p</link><description>s</description></item>") }
        let xml = "<rss version=\"2.0\"><channel><title>Feed \(url.absoluteString)</title>\(items.joined())</channel></rss>"
        return HTTPResponse(data: Data(xml.utf8), finalURL: url, statusCode: 200, headers: ["etag": "v1"])
    }
}
