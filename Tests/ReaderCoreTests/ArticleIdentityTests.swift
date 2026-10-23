import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// An article belongs to one subscription (decision 0067, #395): the same address in two subscriptions is two articles, each with its
/// own feed's values and its own read state and Star.
@MainActor struct ArticleIdentityTests {
    private let received = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ id: String, title: String, summary: String, image: String, date: Double) -> ParsedEntry {
        ParsedEntry(sourceID: id, title: title, url: URL(string: "https://origin.example/post"), summary: summary, body: summary,
                    coverage: .feedProvided, publishedAt: Date(timeIntervalSince1970: date), imageURL: URL(string: image))
    }
    private var original: ParsedFeed {
        ParsedFeed(title: "Origin", sourceURL: URL(string: "https://origin.example/rss")!,
                   entries: [entry("origin-1", title: "Post", summary: "The full text of the post.", image: "https://origin.example/a.png", date: 1_000)],
                   skippedEntries: 0)
    }
    private var bookmarks: ParsedFeed {
        ParsedFeed(title: "Bookmarks", sourceURL: URL(string: "https://bookmarks.example/rss")!,
                   entries: [entry("https://origin.example/post", title: "Post - Origin", summary: "An excerpt", image: "https://bookmarks.example/b.png",
                                   date: 5_000)],
                   skippedEntries: 0)
    }

    @Test func theSameAddressInTwoSubscriptionsIsTwoArticlesWhateverTheOrder() throws {
        for order in [[original, bookmarks], [bookmarks, original]] {
            let library = try TestLibrary(); defer { library.cleanup() }
            let store = try ReaderStore(url: library.url)
            for _ in 0..<2 { for parsed in order { try store.importFeed(parsed, receivedAt: received) } }
            for _ in 0..<2 { for parsed in order.reversed() { try store.importFeed(parsed, receivedAt: received) } }
            #expect(store.articles.count == 2 && store.memberships.count == 2)
            for parsed in order {
                let feed = try #require(store.feeds.first { $0.sourceURL == parsed.sourceURL.absoluteString })
                let ids = store.visibleArticleIDs(feedID: feed.id, unreadOnly: false, keeping: nil)
                let article = try #require(ids.count == 1 ? store.article(id: ids[0]) : nil)
                let expected = try #require(parsed.entries.first)
                #expect(article.feedID == feed.id && article.title == expected.title && article.summary == expected.summary)
                #expect(article.publishedAt == expected.publishedAt && article.imageURL == expected.imageURL?.absoluteString)
                #expect(try store.content(articleID: article.id, at: received)?.text == expected.body)
            }
        }
    }

    @Test func readAndStarAreNotLinkedBetweenTheTwo() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let origin = try store.importFeed(original, receivedAt: received), bookmark = try store.importFeed(bookmarks, receivedAt: received)
        let read = try #require(store.visibleArticleIDs(feedID: origin.id, unreadOnly: false, keeping: nil).first)
        try store.markDisplayed(articleID: read, at: received)
        try store.setStar(articleID: read, isStarred: true, at: received)
        let other = try #require(store.visibleArticleIDs(feedID: bookmark.id, unreadOnly: false, keeping: nil).first)
        #expect(other != read && store.article(id: other)?.isRead == false && store.article(id: other)?.starredAt == nil)
        #expect(store.unreadCount == 1 && store.feedUnreadCounts == [origin.id: 0, bookmark.id: 1] && store.starCount == 1)
    }

    @Test func subscribingAgainToTheSameAddressFindsItsEarlierArticles() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let first = try store.importFeed(original, receivedAt: received)
        let article = try #require(store.articles.first)
        try store.markDisplayed(articleID: article.id, at: received)
        try store.unsubscribe(first)
        let again = try store.importFeed(original, receivedAt: received)
        #expect(store.articles.count == 1 && store.articles.first?.id == article.id && store.articles.first?.isRead == true)
        #expect(store.articles.first?.feedID == again.id && store.memberships.map(\.feedID) == [again.id])
    }

    /// A library made before decision 0067 can hold one article in several subscriptions. Opening it keeps the article in its own
    /// subscription, with its reading history; the other subscription gets an article of its own at its next refresh.
    @Test func aSharedArticleFromAnEarlierVersionIsSeparatedWhenTheLibraryOpens() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let (originID, bookmarkID, articleID) = try {
            let store = try ReaderStore(url: library.url)
            let origin = try store.importFeed(original, receivedAt: received), bookmark = try store.importFeed(bookmarks, receivedAt: received)
            let kept = try #require(store.visibleArticleIDs(feedID: origin.id, unreadOnly: false, keeping: nil).first)
            let context = ModelContext(store.container)
            for membership in try context.fetch(FetchDescriptor<FeedMembership>()) where membership.feedID == bookmark.id { context.delete(membership) }
            for article in try context.fetch(FetchDescriptor<Article>()) where article.id != kept { context.delete(article) }
            context.insert(FeedMembership(feedID: bookmark.id, articleID: kept, sourceID: "https://origin.example/post"))   // as earlier versions joined it
            let stored = try #require(try context.fetch(FetchDescriptor<Article>()).first)
            stored.identityKey = "https://origin.example/post"; stored.isRead = true; stored.starredAt = received
            try context.save()
            return (origin.id, bookmark.id, kept)
        }()
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.memberships.count == 1 && reopened.memberships.first?.feedID == originID)
        #expect(reopened.article(id: articleID)?.isRead == true && reopened.article(id: articleID)?.starredAt == received)
        #expect(reopened.visibleArticleIDs(feedID: bookmarkID, unreadOnly: false, keeping: nil).isEmpty)
        try reopened.importFeed(bookmarks, receivedAt: received)
        try reopened.importFeed(original, receivedAt: received)
        #expect(reopened.articles.count == 2 && reopened.memberships.count == 2 && reopened.article(id: articleID)?.title == "Post")
        let own = try #require(reopened.visibleArticleIDs(feedID: bookmarkID, unreadOnly: false, keeping: nil).first)
        #expect(own != articleID && reopened.article(id: own)?.isRead == false && reopened.article(id: own)?.title == "Post - Origin")
    }

    /// When the article's own subscription is gone, the subscription that still has it keeps it.
    @Test func aSharedArticleWhoseOwnSubscriptionIsGoneMovesToTheOneThatHasIt() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let (bookmarkID, articleID) = try {
            let store = try ReaderStore(url: library.url)
            let origin = try store.importFeed(original, receivedAt: received), bookmark = try store.importFeed(bookmarks, receivedAt: received)
            let kept = try #require(store.visibleArticleIDs(feedID: origin.id, unreadOnly: false, keeping: nil).first)
            let context = ModelContext(store.container)
            for membership in try context.fetch(FetchDescriptor<FeedMembership>()) { context.delete(membership) }
            for article in try context.fetch(FetchDescriptor<Article>()) where article.id != kept { context.delete(article) }
            for feed in try context.fetch(FetchDescriptor<Feed>()) where feed.id == origin.id { context.delete(feed) }
            context.insert(FeedMembership(feedID: bookmark.id, articleID: kept, sourceID: "https://origin.example/post"))
            try context.save()
            return (bookmark.id, kept)
        }()
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.article(id: articleID)?.feedID == bookmarkID && reopened.memberships.map(\.feedID) == [bookmarkID])
    }
}
