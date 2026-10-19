import Foundation
import SwiftData
import Testing
@testable import ReaderCore

@MainActor
struct ReaderStoreTests {
    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "unagi-reader-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Reader.store")
    }

    @Test func seedingTwiceDoesNotDuplicateArticlesOrFeeds() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try ReaderStore(url: url, seedDemo: true)
        let ids = store.articles.map(\.id)
        try store.seedIfEmpty()
        #expect(store.articles.map(\.id) == ids)
        #expect(store.articles.count == 6)
        #expect(store.feeds.count == 3)
    }

    @Test func keyboardSelectionClampsToVisibleList() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(ReaderNavigation.move(nil, by: 1, in: ids) == ids[0])
        #expect(ReaderNavigation.move(ids[0], by: -1, in: ids) == ids[0])
        #expect(ReaderNavigation.move(ids[2], by: 1, in: ids) == ids[2])
        #expect(ReaderNavigation.move(ids[0], by: 1, in: ids) == ids[1])
        #expect(ReaderNavigation.move(nil, by: 1, in: []) == nil)
    }

    @Test func failedSaveCanRetryWithPreviouslySelectedModels() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let at = Date(timeIntervalSince1970: 1_000_000)
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: url, cloudKitDatabase: .none)])
        let fail = TestBox(false)
        let store = try ReaderStore(container: container, now: at, saveHook: {
            if fail.value { throw CocoaError(.fileWriteUnknown) }
        })
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!)
        let feed = try store.importFeed(parsed, receivedAt: at)
        let article = try #require(store.articles.first)
        fail.value = true
        #expect(throws: (any Error).self) { try store.setRead(article, true) }
        #expect(store.article(id: article.id)?.isRead == false)
        fail.value = false
        try store.setRead(article, true)
        try store.updateSubscription(feed, title: "再試行した購読", folder: "技術")
        #expect(store.article(id: article.id)?.isRead == true)
        #expect(store.feed(id: feed.id)?.title == "再試行した購読")
        try store.recordFetch(feed, etag: "v1", lastModified: "old", at: at)
        #expect(store.feed(id: feed.id)?.etag == "v1")
        let fetchedAt = at.addingTimeInterval(60)
        try store.applyRefresh(.notModified, to: feed, at: fetchedAt)
        #expect(store.feed(id: feed.id)?.etag == "v1" && store.feed(id: feed.id)?.lastFetchedAt == fetchedAt)
        try store.applyRefresh(.modified(parsed, etag: "v2", lastModified: "new"), to: feed, at: fetchedAt)
        #expect(store.feed(id: feed.id)?.etag == "v2")
        let reopened = try ReaderStore(url: url, now: at)
        #expect(reopened.article(id: article.id)?.isRead == true)
        #expect(reopened.feed(id: feed.id)?.folder == "技術")
        #expect(reopened.feed(id: feed.id)?.etag == "v2" && reopened.feed(id: feed.id)?.lastModified == "new")
        try store.unsubscribe(feed)
        #expect(store.feeds.isEmpty && store.article(id: article.id)?.isRead == true)
    }

    @Test func failedRecoveryBlocksChangesUntilReloadSucceeds() throws {
        let url = try temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let at = Date(timeIntervalSince1970: 1_000_000)
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: url, cloudKitDatabase: .none)])
        let failSave = TestBox(false), failReload = TestBox(false), saveAttempts = TestBox(0)
        let store = try ReaderStore(container: container, now: at, saveHook: {
            saveAttempts.value += 1
            if failSave.value { throw CocoaError(.fileWriteUnknown) }
        }, reloadHook: {
            if failReload.value { throw CocoaError(.fileReadUnknown) }
        })
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!)
        let feed = try store.importFeed(parsed, receivedAt: at)
        let article = try #require(store.articles.first)
        try store.saveNote(text: "# 保存済み\n", at: at)
        failSave.value = true; failReload.value = true
        #expect(throws: (any Error).self) { try store.setRead(article, true) }
        failSave.value = false
        let attempts = saveAttempts.value
        #expect(throws: (any Error).self) { try store.setRead(article, true) }
        try #require(saveAttempts.value == attempts)
        let changes: [() throws -> Void] = [
            { try store.setRead(article, true) },
            { try store.setStar(articleID: article.id, isStarred: true, at: at) },
            { try store.updateSubscription(feed, title: "変更", folder: "変更") },
            { try store.unsubscribe(feed) },
            { try store.recordFetch(feed, etag: "変更", lastModified: nil, at: at) },
            { try store.applyRefresh(.notModified, to: feed, at: at) },
            { try store.moveFeed(id: feed.id, toFolder: "変更") },
            { try store.renameFolder(from: "", to: "変更") },
            { _ = try store.importFeed(parsed, receivedAt: at) },
            { try store.saveNote(text: "捨ててはいけない変更", at: at) },
            { try store.applyRetention(days: 7, at: at) },
            { try store.deleteContent(articleIDs: [article.id], at: at) },
            { try store.markDisplayed(articleID: article.id, at: at) }
        ]
        for change in changes { #expect(throws: (any Error).self) { try change() } }
        #expect(saveAttempts.value == attempts)
        failReload.value = false
        try store.setRead(article, true)
        try store.saveNote(text: "再試行したノート", at: at)
        let reopened = try ReaderStore(url: url, now: at)
        #expect(reopened.article(id: article.id)?.isRead == true)
        #expect(reopened.feed(id: feed.id)?.title == parsed.title && reopened.feed(id: feed.id)?.folder == "")
        #expect(reopened.retentionDays == 30 && reopened.article(id: article.id)?.starredAt == nil)
        #expect(reopened.notes.count == 1 && reopened.note?.text == "再試行したノート")
    }
}
