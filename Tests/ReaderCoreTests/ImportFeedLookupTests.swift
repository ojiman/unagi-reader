import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// How `importFeed` finds the articles and memberships an entry belongs to (#131). The first refresh after a large OPML import
/// called it once per feed on a library that kept growing, and every entry scanned all articles and memberships.
@MainActor struct ImportFeedLookupTests {
    private let received = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ id: String, url: String?, title: String = "Title") -> ParsedEntry {
        ParsedEntry(sourceID: id, title: title, url: url.flatMap { URL(string: $0) }, summary: "summary", body: "", coverage: .feedProvided,
                    publishedAt: Date(timeIntervalSince1970: 1_000))
    }
    private func feed(_ address: String, _ entries: [ParsedEntry]) -> ParsedFeed {
        ParsedFeed(title: "合成購読", sourceURL: URL(string: address)!, entries: entries, skippedEntries: 0)
    }

    @Test func theSameEntryTwiceInOneFeedIsOneArticleWithOneMembership() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        try store.importFeed(feed("https://a.example/rss", [entry("1", url: "https://a.example/p"), entry("2", url: "https://a.example/p")]), receivedAt: received)
        #expect(store.articles.count == 1 && store.memberships.count == 1)
    }
    @Test func aRefreshWithTheSameEntriesAddsNothing() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let parsed = feed("https://a.example/rss", [entry("1", url: "https://a.example/1"), entry("2", url: nil)])
        try store.importFeed(parsed, receivedAt: received)
        try store.importFeed(parsed, receivedAt: received)
        #expect(store.articles.count == 2 && store.memberships.count == 2)
    }
    @Test func anEntryThatMovedToANewAddressKeepsItsArticleThroughItsSourceID() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        try store.importFeed(feed("https://a.example/rss", [entry("1", url: "https://a.example/old")]), receivedAt: received)
        let before = try #require(store.articles.first)
        try store.importFeed(feed("https://a.example/rss", [entry("1", url: "https://a.example/new", title: "Moved")]), receivedAt: received)
        #expect(store.articles.count == 1 && store.memberships.count == 1)
        #expect(store.articles.first?.id == before.id && store.articles.first?.originalURL == "https://a.example/new" && store.articles.first?.title == "Moved")
        // The old address no longer names the article: an entry that carries it is a new article.
        try store.importFeed(feed("https://a.example/rss", [entry("2", url: "https://a.example/old")]), receivedAt: received)
        #expect(store.articles.count == 2)
    }
    @Test func twoEntriesWithTheSameSourceIDInOneFeedAreOneArticle() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        try store.importFeed(feed("https://a.example/rss", [entry("1", url: "https://a.example/x"), entry("1", url: "https://a.example/y")]), receivedAt: received)
        #expect(store.articles.count == 1 && store.memberships.count == 1)
    }
    @Test func anAddressThatAnotherFeedHasIsAnArticleOfItsOwn() throws {         // decision 0067
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        try store.importFeed(feed("https://a.example/rss", [entry("1", url: "https://shared.example/p")]), receivedAt: received)
        try store.importFeed(feed("https://b.example/rss", [entry("9", url: "https://shared.example/p")]), receivedAt: received)
        #expect(store.articles.count == 2 && store.memberships.count == 2 && store.feeds.count == 2)
        #expect(Set(store.articles.map(\.feedID)) == Set(store.feeds.map(\.id)))
    }

    /// The first refresh after an OPML import adds feed after feed to a library that grows. One feed of 150 entries on 4,000
    /// articles took about 2.6 s (Debug, local) when every entry scanned all of them; with lookups it takes about 0.2 s. The limit is far from both.
    @Test func aFeedIsAddedQuicklyToALargeLibrary() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let configuration = ModelConfiguration("Reader", schema: ReaderStore.schema, url: library.url, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: ReaderStore.schema, configurations: [configuration])); context.autosaveEnabled = false
        let seed = Feed(title: "合成購読", symbol: "dot.radiowaves.left.and.right"); context.insert(seed)
        for index in 0..<4_000 {
            let article = Article(feedID: seed.id, title: "合成記事 \(index)", summary: "合成要約", publisher: "seed.example",
                                  publishedAt: Date(timeIntervalSince1970: Double(index)), receivedAt: received)
            article.identityKey = "https://seed.example/\(index)"
            context.insert(article)
            context.insert(FeedMembership(feedID: seed.id, articleID: article.id, sourceID: String(index)))
        }
        try context.save()
        let store = try ReaderStore(url: library.url)
        let entries = (0..<150).map { entry("n\($0)", url: "https://new.example/\($0)") }
        let start = ContinuousClock.now
        try store.importFeed(feed("https://new.example/rss", entries), receivedAt: received)
        let elapsed = ContinuousClock.now - start
        print("150 entries added to 4,000 articles: \(elapsed)")
        #expect(store.articles.count == 4_150)
        #expect(elapsed < .milliseconds(1_500), "took \(elapsed)")
    }
}
