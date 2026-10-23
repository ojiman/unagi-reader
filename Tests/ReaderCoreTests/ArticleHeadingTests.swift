import Foundation
import Testing
@testable import ReaderCore

/// The lines around an article's title name the subscription it came from and when it was published (#394, specification 3.1.4).
@MainActor struct ArticleHeadingTests {
    private let received = Date(timeIntervalSince1970: 1_000_000)
    private var bookmarks: ParsedFeed {
        ParsedFeed(title: "はてなブックマーク - 人気エントリー - テクノロジー", sourceURL: URL(string: "https://bookmarks.example/rss")!,
                   entries: [ParsedEntry(sourceID: "1", title: "Post", url: URL(string: "https://www.nikkei.example/post"), summary: "s", body: "s",
                                         coverage: .feedProvided, publishedAt: Date(timeIntervalSince1970: 1_792_752_967))],
                   skippedEntries: 0)
    }

    @Test func theHeadingIsTheSubscriptionsNameNotTheLinksHost() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(bookmarks, receivedAt: received)
        let article = try #require(store.articles.first)
        #expect(store.sourceName(of: article) == "はてなブックマーク - 人気エントリー - テクノロジー")
        try store.updateSubscription(feed, title: "はてブ", folder: "")
        #expect(store.sourceName(of: article) == "はてブ")
        try store.unsubscribe(feed)
        #expect(store.sourceName(of: article) == "www.nikkei.example")      // no subscription left: the site
    }

    @Test func theDateLineHasTheWeekdayTheDateAndTheTime() {
        let date = Date(timeIntervalSince1970: 1_792_752_967)                // 2026-10-23T10:56:07Z
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(ArticleHeading.date(date, locale: Locale(identifier: "en_US"), timeZone: tokyo) == "Friday, Oct 23, 2026 at 7:56\u{202F}PM")
        #expect(ArticleHeading.date(date, locale: Locale(identifier: "ja_JP"), timeZone: tokyo) == "2026年10月23日 金曜日 19:56")
        #expect(ArticleHeading.date(date, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!) == "Friday, Oct 23, 2026 at 10:56\u{202F}AM")
        #expect(ArticleHeading.date(.distantPast) == String(localized: "Publication date unknown", bundle: ReaderLocalization.bundle))
    }
}
