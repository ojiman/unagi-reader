import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Writing the subscriptions as an OPML file (decision 0063, #130).
@Suite(EnglishLanguage()) @MainActor struct OPMLExportTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func library(_ feeds: [OPMLFeed]) throws -> (TestLibrary, ReaderStore) {
        let library = try TestLibrary()
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importSubscriptions(feeds)
        return (library, store)
    }

    @Test func foldersHoldTheirSubscriptionsAndUnfiledOnesAreTopLevel() throws {
        let (library, store) = try library([
            OPMLFeed(title: "Alone", url: URL(string: "https://alone.example/feed")!, siteURL: URL(string: "https://alone.example/"), folder: ""),
            OPMLFeed(title: "Swift", url: URL(string: "https://swift.example/rss")!, siteURL: nil, folder: "Tech"),
            OPMLFeed(title: "Atom", url: URL(string: "https://atom.example/atom")!, siteURL: nil, folder: "Tech"),
        ])
        defer { library.cleanup() }
        let text = String(decoding: try OPMLWriter.data(feeds: store.opmlFeeds(), createdAt: start), as: UTF8.self)
        #expect(text.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#) && text.contains(#"<opml version="2.0">"#))
        #expect(text.contains(#"<outline text="Tech" title="Tech">"#))
        #expect(text.contains(#"<outline type="rss" text="Alone" title="Alone" xmlUrl="https://alone.example/feed" htmlUrl="https://alone.example/"/>"#))
        #expect(text.contains(#"<outline type="rss" text="Swift" title="Swift" xmlUrl="https://swift.example/rss"/>"#))
        // The unfiled subscription comes after the folder, at the top level (four spaces, not six).
        #expect(text.contains("\n    <outline type=\"rss\" text=\"Alone\""))
        let document = try OPMLParser.parse(Data(text.utf8))
        #expect(document.feeds.map(\.folder) == ["Tech", "Tech", ""])
    }

    @Test func specialCharactersAndJapaneseAreEscapedAndReadBack() throws {
        let name = #"A & B <"quoted"> 'x' 日本語の購読"#
        let feeds = [OPMLFeed(title: name, url: URL(string: "https://q.example/rss?a=1&b=2")!, siteURL: nil, folder: "技術 & 設計")]
        let data = OPMLWriter.data(feeds: feeds, createdAt: start)
        #expect(String(data: data, encoding: .utf8) != nil)
        let document = try OPMLParser.parse(data)
        #expect(document.feeds == feeds)
        #expect(OPMLWriter.escape("a\u{1}b\tc") == "ab&#9;c")
    }

    /// The exported file brings back the same subscriptions and folders in an empty library.
    @Test func anExportedFileImportsToTheSameSubscriptionsAndFolders() throws {
        let original: [OPMLFeed] = [
            OPMLFeed(title: "Alone", url: URL(string: "https://alone.example/feed")!, siteURL: URL(string: "https://alone.example/"), folder: ""),
            OPMLFeed(title: "Swift", url: URL(string: "https://swift.example/rss")!, siteURL: nil, folder: "Tech"),
            OPMLFeed(title: "ニュース", url: URL(string: "https://news.example/atom")!, siteURL: nil, folder: "日本語"),
        ]
        let (first, store) = try library(original)
        defer { first.cleanup() }
        let data = try OPMLWriter.data(feeds: store.opmlFeeds(), createdAt: start)
        let (second, empty) = try library([])
        defer { second.cleanup() }
        _ = try empty.importSubscriptions(OPMLParser.parse(data).feeds)
        func summary(_ store: ReaderStore) -> Set<String> {
            Set(store.feeds.map { "\($0.title)|\($0.sourceURL ?? "")|\($0.siteURL ?? "")|\($0.folder)" })
        }
        #expect(summary(empty) == summary(store) && empty.feeds.count == 3)
    }

    @Test func theFileNameHasTheDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(OPMLWriter.fileName(at: start, calendar: calendar) == "Unagi Reader Subscriptions 1970-01-12.opml")
    }

    @Test func aFailedWriteIsShownAndACancelIsNot() async throws {
        let (library, store) = try library([OPMLFeed(title: "A", url: URL(string: "https://a.example/f")!, siteURL: nil, folder: "")])
        defer { library.cleanup() }
        struct Refused: LocalizedError { var errorDescription: String? { "The disk refused." } }
        var suggested: String?
        let failing = OPMLExportFlow(store: store, chooseDestination: { suggested = $0; return URL(fileURLWithPath: "/dev/null/x.opml") },
                                     write: { _, _ in throw Refused() }, now: { self.start })
        #expect(await failing.start() == false)
        #expect(failing.failure == "The disk refused." && suggested?.hasSuffix(".opml") == true)
        failing.dismissFailure()
        #expect(failing.failure == nil)
        let cancelled = OPMLExportFlow(store: store, chooseDestination: { _ in nil }, write: { _, _ in Issue.record("written after a cancel") })
        #expect(await cancelled.start() == false && cancelled.failure == nil)
        var written: Data?
        let working = OPMLExportFlow(store: store, chooseDestination: { _ in URL(fileURLWithPath: "/tmp/x.opml") }, write: { data, _ in written = data })
        #expect(await working.start() == true && working.failure == nil)
        #expect(try OPMLParser.parse(try #require(written)).feeds.map(\.title) == ["A"])
    }

    private final class ReloadSwitch: @unchecked Sendable { nonisolated(unsafe) var failing = false }

    /// From Codex's review of this PR: a library that saved but failed to load again is loaded before the export reads it.
    @Test(arguments: [true, false]) func aSavedImportIsReloadedBeforeExport(recoverySucceeds: Bool) async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let reload = ReloadSwitch()
        let store = try ReaderStore(container: container, reloadHook: { if reload.failing { throw CocoaError(.fileReadUnknown) } })
        reload.failing = true
        let result = try store.importSubscriptions([OPMLFeed(title: "Saved", url: URL(string: "https://saved.example/feed")!, siteURL: nil, folder: "Tech")])
        #expect(result.listRefreshFailed && result.addedFeedIDs.count == 1)
        reload.failing = !recoverySucceeds
        var written: Data?
        let flow = OPMLExportFlow(store: store, chooseDestination: { _ in library.directory.appending(path: "out.opml") }, write: { data, _ in written = data })
        #expect(await flow.start() == recoverySucceeds)
        if recoverySucceeds {
            let feeds = try OPMLParser.parse(try #require(written)).feeds
            #expect(feeds.map(\.title) == ["Saved"] && feeds.map(\.folder) == ["Tech"])
            #expect(flow.failure == nil)
        } else {
            #expect(written == nil && flow.failure != nil)
        }
    }
}
