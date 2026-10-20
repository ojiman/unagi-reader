import Foundation
import SwiftData
import Testing
@testable import ReaderCore

// Checks PRD-08: image-only entries follow the same retention and rollback rules as text.
@MainActor struct ImageRetentionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let image = "https://article.example/image.png"
    private func parsed() -> ParsedFeed {
        let entry = ParsedEntry(sourceID: "image-only", title: "Synthetic image", url: URL(string: "https://article.example/1"),
            summary: "", body: "", coverage: .unavailable, publishedAt: start, imageURL: URL(string: image))
        return ParsedFeed(title: "Images", sourceURL: URL(string: "https://feed.example/rss")!, entries: [entry], skippedEntries: 0)
    }

    @Test(arguments: [false, true])
    func anExpiredImageOnlyEntryMustLoseItsImage(shorten: Bool) throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let id = try #require(store.articles.first?.id)
        try store.setStar(articleID: id, isStarred: true, at: start)
        try store.saveNote(text: "Keep my note", at: start)
        let at = start.addingTimeInterval((shorten ? 8 : 31) * 86_400)
        let preview = try store.previewDeletion(days: shorten ? 7 : nil, at: at)
        #expect(preview.articleIDs == [id])
        #expect(preview.bodyCount == 0 && preview.summaryCount == 0 && preview.estimatedBytes == 0)
        if shorten { try store.applyRetention(days: 7, at: at) }
        else { try store.purgeExpired(at: at) }
        #expect(store.article(id: id)?.imageURL == nil)
        #expect(store.article(id: id)?.contentDeletedAt == at)
        #expect(store.article(id: id)?.title == "Synthetic image")
        #expect(store.article(id: id)?.originalURL == "https://article.example/1")
        #expect(store.article(id: id)?.starredAt == start && store.note?.text == "Keep my note")
        _ = try store.importFeed(parsed(), receivedAt: at)
        #expect(store.article(id: id)?.imageURL == nil) // A later feed must not bring the expired image back.
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.article(id: id)?.imageURL == nil && reopened.note?.text == "Keep my note")
    }

    @Test func aDeletionMarkerDoesNotHideALeftoverImage() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let article = try #require(store.articles.first)
        article.contentDeletedAt = start
        try store.context.save()
        try store.purgeExpired(at: start)
        #expect(store.article(id: article.id)?.imageURL == nil)
        #expect(store.article(id: article.id)?.contentDeletedAt == start)
    }

    @Test func aFailedImagePurgeCanRecoverWithoutLosingTheImageEarly() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        var failSave = false, failReload = false
        let store = try ReaderStore(container: container, now: start,
            saveHook: { if failSave { throw CocoaError(.fileWriteUnknown) } },
            reloadHook: { if failReload { throw CocoaError(.fileReadUnknown) } })
        _ = try store.importFeed(parsed(), receivedAt: start)
        let id = try #require(store.articles.first?.id)
        let at = start.addingTimeInterval(31 * 86_400)
        failSave = true
        #expect(throws: (any Error).self) { try store.purgeExpired(at: at) }
        #expect(store.article(id: id)?.imageURL == image && store.article(id: id)?.contentDeletedAt == nil)
        failReload = true
        #expect(throws: (any Error).self) { try store.purgeExpired(at: at) }
        failSave = false
        #expect(throws: (any Error).self) { try store.purgeExpired(at: at) } // Recovery still blocks writes.
        failReload = false
        try store.purgeExpired(at: at)
        #expect(store.article(id: id)?.imageURL == nil && store.article(id: id)?.contentDeletedAt == at)
    }
}
