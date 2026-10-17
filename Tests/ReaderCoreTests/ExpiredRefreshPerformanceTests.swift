import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Opt-in Release replay for #287. Fixture setup is outside both timers.
@MainActor struct ExpiredRefreshPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNAGI_READER_EXPIRED_REFRESH_BENCHMARK"] == "1"))
    func removedEntriesDoNotScanTheLibraryAgain() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let at = start.addingTimeInterval(31 * 86_400)
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let context = ModelContext(container); context.autosaveEnabled = false
        var expiredIDs: [UUID] = []
        var expiredFeeds: [ParsedFeed] = []
        for f in 0..<200 {
            let url = URL(string: "https://f\(f).example/feed")!
            let feed = Feed(title: "F\(f)", symbol: "dot.radiowaves.left.and.right")
            feed.sourceURL = url.absoluteString; context.insert(feed)
            var entries: [ParsedEntry] = []
            for e in 0..<25 {
                let link = URL(string: "https://f\(f).example/a\(e)")!
                let expired = f.isMultiple(of: 2)
                let article = Article(feedID: feed.id, title: "A\(e)", summary: expired ? "" : "Summary", publisher: "example", publishedAt: start, receivedAt: expired ? start : at)
                article.identityKey = link.absoluteString; article.originalURL = link.absoluteString
                if expired { article.contentDeletedAt = at; expiredIDs.append(article.id) }
                context.insert(article)
                context.insert(FeedMembership(feedID: feed.id, articleID: article.id, sourceID: "\(e)"))
                if !expired { context.insert(ContentSnapshot(articleID: article.id, text: String(repeating: "Synthetic body. ", count: 140))) }
                entries.append(ParsedEntry(sourceID: "\(e)", title: "A\(e)", url: link, summary: "Must not return", body: "Must not return", coverage: .feedProvided, publishedAt: start))
            }
            if f.isMultiple(of: 2) { expiredFeeds.append(ParsedFeed(title: feed.title, sourceURL: url, entries: entries, skippedEntries: 0)) }
        }
        try context.save()
        let store = try ReaderStore(container: container, now: at)
        let clock = ContinuousClock()
        // The same removeContent calls made by one refresh's 2,500 expired entries.
        let removalStart = clock.now
        for id in expiredIDs { #expect(try !store.removeContent(articleIDs: [id], at: at)) }
        let removal = removalStart.duration(to: clock.now)
        let index = EntryIndex(articles: store.articles, memberships: store.memberships)
        var longest = Duration.zero
        let mergeStart = clock.now
        for feed in expiredFeeds {
            let began = clock.now
            _ = try store.merge(feed, receivedAt: at, folder: nil, index: index)
            longest = max(longest, began.duration(to: clock.now))
        }
        let merge = mergeStart.duration(to: clock.now)
        print("EXPIRED_REFRESH articles=5000 feeds=200 expired=2500 removal=\(removal) merges=\(merge) longestMerge=\(longest)")
        #expect(longest <= .milliseconds(100), "One feed's merge alone exceeds W2 before any batch save or reload")
        #expect(store.articles.count == 5_000)
        #expect(try store.context.fetchCount(FetchDescriptor<ContentSnapshot>()) == 2_500)
        #expect(store.articles.filter { $0.contentDeletedAt != nil }.allSatisfy { $0.summary.isEmpty && $0.imageURL == nil })
    }
}
