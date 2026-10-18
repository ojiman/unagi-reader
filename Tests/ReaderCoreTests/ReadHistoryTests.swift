import Foundation
import SwiftData
import Testing
@testable import ReaderCore

struct TestLibrary {
    let directory: URL
    var url: URL { directory.appending(path: "Reader.store") }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "unagi-reader-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

// Checks PRD-02 (specification 7).
@MainActor struct ReadHistoryTests {
    let received = Date(timeIntervalSince1970: 1_000_000)
    let displayed = Date(timeIntervalSince1970: 1_000_100)
    private func parsed() throws -> ParsedFeed {
        try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!)
    }

    @Test func selectionAndContentLookupDoNotMarkRead() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: displayed)
        _ = try store.importFeed(parsed(), receivedAt: received)
        let article = try #require(store.articles.first)
        _ = ReaderNavigation.move(nil, by: 1, in: store.articles.map(\.id))
        let content = try #require(try store.content(articleID: article.id, at: displayed))
        #expect(!content.text.isEmpty)
        #expect(!article.isRead && article.firstReadAt == nil)
    }

    @Test func firstDisplayIsRecordedOnce() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: displayed)
        _ = try store.importFeed(parsed(), receivedAt: received)
        let article = try #require(store.articles.first)
        try store.markDisplayed(articleID: article.id, at: displayed)
        #expect(article.isRead && article.firstReadAt == displayed)
        try store.setRead(article, false)
        try store.markDisplayed(articleID: article.id, at: displayed.addingTimeInterval(100))
        _ = try store.importFeed(parsed(), receivedAt: received.addingTimeInterval(500))
        #expect(article.firstReadAt == displayed)
        #expect(article.firstReceivedAt == received)
    }

    /// #249: the read mark is written through a small context, so it does not walk the whole library and does not commit anything else.
    @Test func aReadMarkDoesNotCommitAnUnrelatedPendingChange() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, seedDemo: true, now: displayed)
        let read = try #require(store.articles.first), other = try #require(store.articles.last)
        let otherID = other.id, originalTitle = other.title
        other.title = "An unrelated, unsaved change"
        try store.markDisplayed(articleID: read.id, at: displayed)
        let reopened = try ReaderStore(url: library.url, now: displayed)
        #expect(reopened.article(id: read.id)?.firstReadAt == displayed)
        #expect(reopened.article(id: otherID)?.title == originalTitle)
    }

    /// The shown article takes the saved values, and the store's read revision tells the views (a refetch does not notify the model).
    @Test func aReadMarkUpdatesTheShownArticleAndTheReadRevision() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: displayed)
        _ = try store.importFeed(parsed(), receivedAt: received)
        let article = try #require(store.articles.first)
        let revision = store.readRevision, unread = store.unreadCount
        try store.markDisplayed(articleID: article.id, at: displayed)
        #expect(article.isRead && article.firstReadAt == displayed)
        #expect(store.unreadCount == unread - 1 && store.readRevision == revision + 1)
        #expect(!store.context.hasChanges)
    }

    final class SaveGate { var failNext = false }

    /// A failed read mark is not shown as read and is not saved; the next one works.
    @Test func aFailedReadMarkIsNotShownAndCanBeRetried() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let gate = SaveGate()
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, now: displayed, saveHook: {
            if gate.failNext { gate.failNext = false; throw CocoaError(.fileWriteUnknown) }
        })
        _ = try store.importFeed(parsed(), receivedAt: received)
        let id = try #require(store.articles.first?.id)
        let unread = store.unreadCount
        gate.failNext = true
        #expect(throws: (any Error).self) { try store.markDisplayed(articleID: id, at: displayed) }
        #expect(store.article(id: id)?.isRead == false && store.article(id: id)?.firstReadAt == nil && store.unreadCount == unread)
        #expect(try ReaderStore(url: library.url, now: displayed).article(id: id)?.firstReadAt == nil)
        try store.markDisplayed(articleID: id, at: displayed)
        #expect(store.article(id: id)?.firstReadAt == displayed && store.unreadCount == unread - 1)
        #expect(try ReaderStore(url: library.url, now: displayed).article(id: id)?.firstReadAt == displayed)
    }

    @Test func unavailableContentDoesNotMarkRead() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: displayed)
        let xml = "<rss><channel><title>Empty</title><item><guid>empty</guid><title>Empty article</title></item></channel></rss>"
        _ = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://feed.example/empty")!), receivedAt: received)
        let article = try #require(store.articles.first)
        #expect(try store.content(articleID: article.id, at: displayed) == nil)
        try store.markDisplayed(articleID: article.id, at: displayed)
        #expect(!article.isRead && article.firstReadAt == nil)
    }

    @Test func readHistorySurvivesReopen() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let id = try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: displayed)
            _ = try store.importFeed(parsed(), receivedAt: received)
            let article = try #require(store.articles.first)
            try store.markDisplayed(articleID: article.id, at: displayed)
            return article.id
        }
        let reopened = try ReaderStore(url: library.url, now: displayed)
        let article = try #require(reopened.articles.first)
        #expect(article.id == id && article.firstReadAt == displayed && article.firstReceivedAt == received)
        #expect(reopened.feeds.count == 1 && reopened.memberships.count == 1)
        #expect(try reopened.content(articleID: id, at: displayed)?.text.contains("本文 & 補足") == true)
    }

    @Test func emptyLibraryRemainsEmptyAfterReopen() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: displayed)
            #expect(store.articles.isEmpty && store.feeds.isEmpty)
        }
        let reopened = try ReaderStore(url: library.url, now: displayed)
        #expect(reopened.articles.isEmpty && reopened.feeds.isEmpty)
    }

    @Test func failedOpenDoesNotResetStore() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let invalid = Data("not a database — synthetic".utf8)
        try invalid.write(to: library.url)
        #expect(throws: (any Error).self) { _ = try ReaderStore(url: library.url, now: displayed) }
        #expect(try Data(contentsOf: library.url) == invalid)
    }
}
