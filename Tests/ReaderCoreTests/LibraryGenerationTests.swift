import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Plan "Refresh merge off the main thread", step 1: the library generation changes with every write that can change what a refresh
/// reads to match its entries (subscriptions, identities, memberships, content), and not with a read mark, a Star or the note.
@MainActor struct LibraryGenerationTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private func parsed(_ source: String, entries: [String]) -> ParsedFeed {
        ParsedFeed(title: "Feed", sourceURL: URL(string: source)!, entries: entries.map { path in
            ParsedEntry(sourceID: path, title: path, url: URL(string: "https://article.example/" + path), summary: path, body: path,
                        coverage: .feedProvided, publishedAt: at)
        }, skippedEntries: 0)
    }

    @Test func everyLibraryWriteChangesTheGeneration() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        func changes(_ name: String, _ write: () throws -> Void) rethrows {
            let before = store.libraryGeneration
            try write()
            #expect(store.libraryGeneration > before, "\(name) did not change the generation")
        }
        var feed: Feed!
        try changes("importFeed") { feed = try store.importFeed(parsed("https://feed.example/rss", entries: ["a", "b"]), receivedAt: at) }
        try changes("importSubscriptions") {
            _ = try store.importSubscriptions([OPMLFeed(title: "B", url: URL(string: "https://b.example/rss")!, siteURL: nil, folder: "Work")])
        }
        try changes("updateSubscription") { try store.updateSubscription(feed, title: "Renamed", folder: "") }
        try changes("moveFeed") { try store.moveFeed(id: feed.id, toFolder: "Work") }
        try changes("moveFeeds") { try store.moveFeeds(ids: [feed.id], toFolder: "Other") }
        try changes("renameFolder") { try store.renameFolder(from: "Other", to: "Moved") }
        let article = try #require(store.articles.first)
        try changes("deleteContent") { try store.deleteContent(articleIDs: [article.id], at: at) }
        try changes("applyRetention") { try store.applyRetention(days: 7, at: at) }
        try changes("purgeExpired") { try store.purgeExpired(at: at.addingTimeInterval(400 * 86_400)) }
        let other = try #require(store.feeds.first { $0.id != feed.id })
        try changes("unsubscribe") { try store.unsubscribe(other) }
    }

    @Test func readMarksStarsTheNoteAndARefreshBatchDoNot() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let feed = try store.importFeed(parsed("https://feed.example/rss", entries: ["a", "b"]), receivedAt: at)
        let article = try #require(store.articles.first)
        let before = store.libraryGeneration
        try store.markDisplayed(articleID: article.id, at: at)
        try store.setRead(article, false)
        try store.setStar(articleID: article.id, isStarred: true, at: at)
        try store.saveNote(text: "合成ノート", at: at)
        let source = try #require(feed.sourceURL)
        #expect(store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source,
            result: .modified(parsed(source, entries: ["a", "b", "c"]), etag: "v2", lastModified: nil))], at: at).isEmpty)
        #expect(store.libraryGeneration == before)
    }

    @Test func aFailedSaveChangesTheGeneration() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        final class Gate { var failNext = false }
        let gate = Gate()
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, now: at, saveHook: {
            if gate.failNext { gate.failNext = false; throw CocoaError(.fileWriteUnknown) }
        })
        let feed = try store.importFeed(parsed("https://feed.example/rss", entries: ["a"]), receivedAt: at)
        let before = store.libraryGeneration
        gate.failNext = true
        #expect(throws: (any Error).self) { try store.updateSubscription(feed, title: "失敗", folder: "") }
        #expect(store.libraryGeneration > before)                                  // the rollback reloaded the library
    }
}
