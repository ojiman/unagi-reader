import Foundation
import Observation
import Testing
@testable import ReaderCore

@MainActor struct RefreshIndexTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private func entry(_ source: String, _ path: String, _ time: Double, title: String = "Article") -> ParsedEntry {
        ParsedEntry(sourceID: source, title: title, url: URL(string: "https://article.example/" + path),
                    summary: title, body: title, coverage: .feedProvided, publishedAt: Date(timeIntervalSince1970: time))
    }
    private func apply(_ store: ReaderStore, _ feed: Feed, _ entries: [ParsedEntry], title: String = "Feed") async throws {
        let source = try #require(feed.sourceURL)
        let parsed = ParsedFeed(title: title, sourceURL: try #require(URL(string: source)), entries: entries, skippedEntries: 0)
        #expect(await store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source,
                                                result: .modified(parsed, etag: "v1", lastModified: nil))], at: at).isEmpty)
    }

    /// #303: a refresh batch is written through a small context, so its save does not walk the whole library or commit anything else.
    @Test func aBatchDoesNotCommitAnUnrelatedPendingChange() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1), entry("b", "b", 2)], skippedEntries: 0), receivedAt: at)
        let other = try #require(store.articles.first { $0.originalURL == "https://article.example/b" })
        let otherID = other.id
        other.isRead = true                                                         // unsaved, and not part of the refresh
        try await apply(store, feed, [entry("a", "a", 1, title: "Changed"), entry("c", "c", 3)])
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.article(id: otherID)?.isRead == false)
        #expect(reopened.articles.count == 3 && reopened.articles.contains { $0.title == "Changed" })
    }

    /// The library context's instances take the batch's saved values (the shown article and feed are the same objects), and it is left
    /// with no unsaved change.
    @Test func aBatchShowsItsValuesWithoutLeavingChanges() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1)], skippedEntries: 0), receivedAt: at)
        let article = try #require(store.articles.first)
        let source = try #require(feed.sourceURL)
        let parsed = ParsedFeed(title: "Renamed", sourceURL: try #require(URL(string: source)), entries: [entry("a", "a", 1, title: "Changed")],
                                skippedEntries: 0, iconURL: URL(string: "https://feed.example/icon.png"))
        #expect(await store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source, result: .modified(parsed, etag: "v2", lastModified: nil))], at: at).isEmpty)
        #expect(store.article(id: article.id) === article && article.title == "Changed")
        #expect(store.feed(id: feed.id) === feed && feed.title == "Renamed" && feed.iconURL == "https://feed.example/icon.png" && feed.etag == "v2")
        #expect(feed.lastFetchedAt == at && !store.context.hasChanges)
    }

    @Test func notModifiedKeepsTheDisplayedArticleLists() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1)], skippedEntries: 0), receivedAt: at)
        let changes = Recorder<Bool>()
        withObservationTracking {
            _ = store.articleIDs; _ = store.contentRevision; _ = store.unreadCount; _ = store.feeds
        } onChange: { changes.add(true) }
        let later = at.addingTimeInterval(60)
        #expect(await store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: feed.sourceURL!, result: .notModified)], at: later).isEmpty)
        #expect(feed.lastFetchedAt == later)
        #expect(changes.values.isEmpty)
    }

    // Checks PRD-01, PRD-04 and PRD-09: every committed batch is fully visible without losing reading history or Stars.
    @Test func committedBatchesMatchFullReloadAfterSharedAndMovedEntries() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let ids = try store.importSubscriptions([
            OPMLFeed(title: "A", url: URL(string: "https://a.example/rss")!, siteURL: nil, folder: "Work"),
            OPMLFeed(title: "B", url: URL(string: "https://b.example/rss")!, siteURL: nil, folder: "Work")
        ]).addedFeedIDs
        let a = try #require(store.feed(id: ids[0])), b = try #require(store.feed(id: ids[1]))
        try await apply(store, a, [entry("a", "shared", 20), entry("b", "b", 10)], title: "Z")
        let shared = try #require(store.articles.first { $0.originalURL == "https://article.example/shared" })
        try store.markDisplayed(articleID: shared.id, at: at)
        try store.setStar(articleID: shared.id, isStarred: true, at: at)
        try store.saveNote(text: "Keep this note", at: at)
        #expect(store.filteredIDs(store.articleIDs, matching: "Changed").isEmpty)
        let feedChanges = Recorder<Bool>(), folderChanges = Recorder<Bool>()
        withObservationTracking {
            _ = store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil)
        } onChange: { feedChanges.add(true) }
        withObservationTracking {
            _ = store.folderArticleIDs(folder: "Work", keeping: nil)
        } onChange: { folderChanges.add(true) }
        try await apply(store, b, [entry("shared-in-b", "shared", 20), entry("c", "c", 30)], title: "A")
        #expect(feedChanges.values == [true] && folderChanges.values == [true])
        try await apply(store, a, [entry("a", "moved", 40, title: "Changed")], title: "Z")
        #expect(store.articles.count == 3 && store.memberships.count == 4)
        #expect(store.articleIDs.first == shared.id && store.articles.map(\.id) == store.articleIDs)
        #expect(store.filteredIDs(store.articleIDs, matching: "Changed") == [shared.id])
        #expect(store.unreadCount == 2 && store.feedUnreadCounts[a.id] == 1 && store.feedUnreadCounts[b.id] == 1)
        #expect(store.folderUnreadCount(folder: "Work") == 2 && store.folderArticleIDs(folder: "Work", keeping: nil).count == 3)
        #expect(store.starredArticleIDs(keeping: nil) == [shared.id] && shared.firstReadAt == at && shared.starredAt == at)
        #expect(store.note?.text == "Keep this note")
        #expect(store.feeds.map(\.title) == ["A", "Z"])
        let ordered = store.articleIDs
        let perFeed = ids.map { store.visibleArticleIDs(feedID: $0, unreadOnly: false, keeping: nil) }
        let folder = store.folderArticleIDs(folder: "Work", keeping: nil)
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.articleIDs == ordered)
        #expect(ids.map { reopened.visibleArticleIDs(feedID: $0, unreadOnly: false, keeping: nil) } == perFeed)
        #expect(reopened.folderArticleIDs(folder: "Work", keeping: nil) == folder)
        #expect(reopened.feedUnreadCounts == store.feedUnreadCounts && reopened.folderUnreadCounts == store.folderUnreadCounts)
    }

    @Test func aNewMembershipNotifiesScopedListsWithoutMovingTheGlobalList() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let ids = try store.importSubscriptions([
            OPMLFeed(title: "A", url: URL(string: "https://a.example/rss")!, siteURL: nil, folder: "Work"),
            OPMLFeed(title: "B", url: URL(string: "https://b.example/rss")!, siteURL: nil, folder: "Other")
        ]).addedFeedIDs
        let a = try #require(store.feed(id: ids[0])), b = try #require(store.feed(id: ids[1]))
        try await apply(store, a, [entry("a", "shared", 20)], title: "A")
        let id = try #require(store.articleIDs.first)
        let globalChanges = Recorder<Bool>(), feedChanges = Recorder<Bool>(), folderChanges = Recorder<Bool>()
        withObservationTracking { _ = store.articleIDs } onChange: { globalChanges.add(true) }
        withObservationTracking {
            _ = store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil)
        } onChange: { feedChanges.add(true) }
        withObservationTracking {
            _ = store.folderArticleIDs(folder: "Other", keeping: nil)
        } onChange: { folderChanges.add(true) }
        try await apply(store, b, [entry("b", "shared", 20)], title: "B")
        #expect(globalChanges.values.isEmpty && feedChanges.values == [true] && folderChanges.values == [true])
        #expect(store.articleIDs == [id] && store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil) == [id])
        #expect(store.folderArticleIDs(folder: "Other", keeping: nil) == [id])
        #expect(store.unreadCount == 1 && store.feedUnreadCounts == [a.id: 1, b.id: 1])
        #expect(store.folderUnreadCounts == ["Work": 1, "Other": 1])
    }

    @Test func subscriptionChangesInvalidateMembershipLookups() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let source = URL(string: "https://a.example/rss")!
        let id = try #require(store.importSubscriptions([OPMLFeed(title: "A", url: source, siteURL: nil, folder: "Old")]).addedFeedIDs.first)
        let feed = try #require(store.feed(id: id))
        try await apply(store, feed, [entry("a", "a", 1)])
        try store.moveFeed(id: id, toFolder: "New")
        try await apply(store, feed, [entry("b", "b", 2)])
        #expect(store.folderArticleIDs(folder: "Old", keeping: nil).isEmpty)
        #expect(store.folderUnreadCount(folder: "New") == 2)
        try store.unsubscribe(feed)
        let newID = try #require(store.importSubscriptions([OPMLFeed(title: "A", url: source, siteURL: nil, folder: "Again")]).addedFeedIDs.first)
        try await apply(store, try #require(store.feed(id: newID)), [entry("a", "a", 1)])
        #expect(store.articles.count == 2 && store.memberships.count == 1)
        #expect(store.feedUnreadCounts[newID] == 1 && store.folderUnreadCount(folder: "Again") == 1)
    }
}
