import Foundation
import Testing
@testable import ReaderCore

// Checks PRD-16 (specification 7).
@MainActor struct SubscriptionTests {
    @Test func selectedFolderIsSavedOnImportAndRetainedOnRefresh() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://synthetic.example/folder-feed")!)
        let feed = try store.importFeed(parsed, folder: " 技術 ")
        let article = try #require(store.articles.first)
        #expect(store.folderArticleIDs(folder: "技術", keeping: nil) == [article.id])
        _ = try store.importFeed(parsed)
        #expect(feed.folder == "技術")
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.feed(id: feed.id)?.folder == "技術")
        _ = try store.importFeed(parsed, folder: "")
        #expect(feed.folder.isEmpty)
        #expect(store.feeds.count == 1 && store.articles.count == 1)
    }

    @Test func aSourceIsRecognizedAsSubscribedByItsAddress() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let url = URL(string: "https://Synthetic.example/subscribed")!
        #expect(!store.isSubscribed(to: url))
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: url)
        let feed = try store.importFeed(parsed, folder: "技術")
        #expect(store.isSubscribed(to: parsed.sourceURL) && store.isSubscribed(to: url))      // the stored form lower-cases the host
        #expect(!store.isSubscribed(to: URL(string: "https://synthetic.example/other")!))
        try store.unsubscribe(feed)
        #expect(!store.isSubscribed(to: url))
    }

    @Test func importUpdateDeduplicateAndUnsubscribePreservesReadHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rss-subscriptions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Reader.store")
        let id: UUID = try autoreleasepool {
            let store = try ReaderStore(url: storeURL, now: Date(timeIntervalSince1970: 123))
            let first = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/a")!)
            let feed = try store.importFeed(first, receivedAt: Date(timeIntervalSince1970: 123))
            let article = try #require(store.articles.first { $0.originalURL != nil })
            let articleID = article.id
            try store.markDisplayed(articleID: article.id, at: Date(timeIntervalSince1970: 123))
            try store.updateSubscription(feed, title: "自分の名前", folder: "Engineering")
            _ = try store.importFeed(first, receivedAt: Date(timeIntervalSince1970: 123))
            #expect(store.articles.count == 1)
            #expect(store.feeds.count == 1)
            #expect(feed.title == "自分の名前")
            let second = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://aggregator.example/rss")!)
            let other = try store.importFeed(second, receivedAt: Date(timeIntervalSince1970: 123))
            // The aggregator's entry with the same link is its own article, unread (decision 0067).
            #expect(store.articles.count == 2)
            let feedID = feed.id, otherID = other.id
            let isMember = { (id: UUID) in store.memberships.contains { $0.feedID == id && $0.articleID == articleID } }
            #expect(isMember(feedID))
            #expect(!isMember(otherID))
            #expect(store.articles.first { $0.feedID == otherID }?.isRead == false)
            #expect(article.publisher == "publisher.example")
            #expect(article.isRead)
            try store.unsubscribe(feed)
            #expect(!isMember(feedID))
            try store.unsubscribe(other)
            #expect(store.articles.contains { $0.id == articleID })
            #expect(article.firstReadAt == Date(timeIntervalSince1970: 123))
            #expect(try store.content(articleID: articleID, at: Date(timeIntervalSince1970: 123))?.text.contains("本文 & 補足") == true)
            return articleID
        }
        let reopened = try ReaderStore(url: storeURL, now: Date(timeIntervalSince1970: 123))
        let article = try #require(reopened.articles.first { $0.id == id })
        #expect(article.firstReadAt == Date(timeIntervalSince1970: 123))
        #expect(reopened.feeds.isEmpty)
        #expect(reopened.memberships.filter { $0.articleID == id }.isEmpty)
    }

    @Test func subscriptionEditsSurviveReopenAndMalformedImportDoesNotMutate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rss-subscriptions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Reader.store")
        let id = try autoreleasepool {
            let store = try ReaderStore(url: url)
            let feed = try store.importFeed(FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!))
            try store.updateSubscription(feed, title: "変更済み", folder: "技術")
            #expect(throws: (any Error).self) {
                try store.importFeed(FeedParser.parse(Data("<rss>".utf8), sourceURL: URL(string: "https://bad.example/rss")!))
            }
            #expect(store.feeds.count == 1)
            return feed.id
        }
        let reopened = try ReaderStore(url: url)
        let feed = try #require(reopened.feeds.first { $0.id == id })
        #expect(feed.title == "変更済み")
        #expect(feed.folder == "技術")
        #expect(reopened.memberships.count == 1)
    }

    @Test func updateFromSameSourceReplacesBodyAndRetainsMissingLink() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rss-subscriptions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReaderStore(url: directory.appending(path: "Reader.store"))
        let source = URL(string: "https://feed.example/rss")!
        _ = try store.importFeed(FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: source))
        let article = try #require(store.articles.first { $0.originalURL != nil })
        let changed = FeedParserTests.rss
            .replacingOccurrences(of: "<link>https://publisher.example/posts/1#top</link>", with: "")
            .replacingOccurrences(of: "<p>本文 &amp; 補足</p><pre>a\n  b</pre>", with: "<p>訂正</p>")
        _ = try store.importFeed(FeedParser.parse(Data(changed.utf8), sourceURL: source))
        #expect(store.articles.count == 1)
        #expect(article.originalURL == "https://publisher.example/posts/1")
        #expect(try store.content(articleID: article.id, at: .now)?.text == "訂正")
    }
}
