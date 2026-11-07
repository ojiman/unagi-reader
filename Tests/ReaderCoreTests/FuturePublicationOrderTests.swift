import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Specification 3.0, list order: a publication time later than the first receipt orders as that receipt (#464).
@MainActor
struct FuturePublicationOrderTests {
    private func rss(_ items: [(id: String, date: String)]) -> String {
        let body = items.map {
            "<item><guid>\($0.id)</guid><title>\($0.id)</title><link>https://publisher.example/\($0.id)</link><pubDate>\($0.date)</pubDate></item>"
        }.joined()
        return "<rss version=\"2.0\"><channel><title>Synthetic</title>\(body)</channel></rss>"
    }

    @Test func aFutureDateDoesNotHoldTheTopOfTheList() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "unagi-reader-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Reader.store")
        let source = URL(string: "https://feed.example/rss")!
        let receivedAt = try #require(ISO8601DateFormatter().date(from: "2026-11-08T00:00:00Z"))
        let store = try ReaderStore(url: url, now: receivedAt)
        // Received at 00:00: "future" claims the next day, "past" one hour earlier.
        let first = try FeedParser.parse(Data(rss([("future", "Mon, 09 Nov 2026 00:00:00 +0000"),
                                                   ("past", "Sat, 07 Nov 2026 23:00:00 +0000")]).utf8), sourceURL: source)
        let feed = try store.importFeed(first, receivedAt: receivedAt, folder: "Engineering")
        // A refresh one hour later brings "newer", published at 00:30: after the receipt of "future", so it goes above it.
        let refreshedAt = receivedAt.addingTimeInterval(3600)
        let second = try FeedParser.parse(Data(rss([("newer", "Sun, 08 Nov 2026 00:30:00 +0000"),
                                                    ("future", "Mon, 09 Nov 2026 00:00:00 +0000"),
                                                    ("past", "Sat, 07 Nov 2026 23:00:00 +0000")]).utf8), sourceURL: source)
        let failed = store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source.absoluteString,
                                                       result: .modified(second, etag: nil, lastModified: nil))], at: refreshedAt)
        #expect(failed.isEmpty)

        func titles(_ ids: [UUID], in store: ReaderStore) -> [String] { ids.compactMap { store.article(id: $0)?.title } }
        let expected = ["newer", "future", "past"]
        #expect(titles(store.articleIDs, in: store) == expected)                                              // a refresh
        #expect(titles(store.visibleArticleIDs(feedID: feed.id, unreadOnly: false, keeping: nil), in: store) == expected)
        #expect(titles(store.folderIndex["Engineering"] ?? [], in: store) == expected)
        let reopened = try ReaderStore(url: url, now: refreshedAt)                                           // a launch
        #expect(titles(reopened.articleIDs, in: reopened) == expected)
        #expect(reopened.articles.map(\.title) == expected)
        #expect(titles(reopened.visibleArticleIDs(feedID: feed.id, unreadOnly: false, keeping: nil), in: reopened) == expected)
        // The shown date is still the feed's.
        let future = try #require(reopened.articles.first { $0.title == "future" })
        #expect(future.publishedAt == ISO8601DateFormatter().date(from: "2026-11-09T00:00:00Z"))
    }
}
