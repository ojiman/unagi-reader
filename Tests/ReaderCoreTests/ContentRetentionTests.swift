import Foundation
import Testing
import SwiftData
@testable import ReaderCore

// Checks PRD-08 (specification 7).
@MainActor struct ContentRetentionTests {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let day: TimeInterval = 86_400
    func parsed() throws -> ParsedFeed {
        try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!)
    }
    @Test func thirtyDayBoundariesAndFirstReadAnchor() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let article = try #require(store.articles.first)
        #expect(store.retentionDays == 30)
        #expect(try store.content(articleID: article.id, at: start.addingTimeInterval(30 * day - 1)) != nil)
        #expect(try store.content(articleID: article.id, at: start.addingTimeInterval(30 * day)) == nil)
        let read = start.addingTimeInterval(day)
        try store.markDisplayed(articleID: article.id, at: read)
        try store.setRead(article, false)
        #expect(try store.availableContentExpiries(at: read)[article.id] == start.addingTimeInterval(31 * day))
        #expect(try store.content(articleID: article.id, at: start.addingTimeInterval(31 * day)) == nil)
    }
    /// #250: the preview reads only the bodies of expired articles; the selection and the counts stay as before.
    @Test func previewSelectsTheSameArticlesWhenItReadsOnlyExpiredBodies() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let container = try ModelContainer(for: ReaderStore.schema, configurations: [
            ModelConfiguration("Reader", schema: ReaderStore.schema, url: library.url, cloudKitDatabase: .none)])
        let context = ModelContext(container); context.autosaveEnabled = false
        let feed = Feed(title: "Feed", symbol: "dot.radiowaves.left.and.right"); context.insert(feed)
        func add(_ title: String, summary: String, body: String?, receivedAt: Date) -> Article {
            let article = Article(feedID: feed.id, title: title, summary: summary, publisher: "", publishedAt: receivedAt, receivedAt: receivedAt)
            context.insert(article)
            if let body { context.insert(ContentSnapshot(articleID: article.id, text: body, coverage: .feedProvided, bodyParagraphs: nil)) }
            return article
        }
        let old = start.addingTimeInterval(-40 * day)
        let fresh = add("fresh", summary: "s", body: "body", receivedAt: start)
        let summaryOnly = add("summary", summary: "s", body: nil, receivedAt: old)
        let bodyOnly = add("body", summary: "", body: "body", receivedAt: old)
        let empty = add("empty", summary: "", body: "", receivedAt: old)
        let many = (0..<1_500).map { add("many \($0)", summary: "", body: "body", receivedAt: old) }
        try context.save()
        // Opened at a time when nothing has expired yet, so the opening purge keeps everything.
        let store = try ReaderStore(container: container, now: old)
        let preview = try store.previewDeletion(days: nil, at: start)
        let selected = Set(preview.articleIDs)
        #expect(!selected.contains(fresh.id) && !selected.contains(empty.id))
        #expect(selected.contains(summaryOnly.id) && selected.contains(bodyOnly.id))
        #expect(selected.isSuperset(of: many.map(\.id)) && selected.count == 1_502)
        #expect(preview.bodyCount == 1_501 && preview.summaryCount == 1)
        #expect(preview.articleIDs == store.articles.map(\.id).filter(selected.contains))
    }
    @Test func previewDoesNotMutateAndShorteningCommitsOnce() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let id = try #require(store.articles.first).id
        let later = start.addingTimeInterval(10 * day)
        let preview = try store.previewDeletion(days: 7, at: later)
        #expect(preview.articleIDs == [id] && preview.bodyCount == 1 && preview.summaryCount == 1 && preview.estimatedBytes > 0)
        #expect(store.retentionDays == 30)
        #expect(try store.content(articleID: id, at: later) != nil)
        try store.applyRetention(days: 7, at: later)
        #expect(store.retentionDays == 7)
        #expect(try store.availableContentExpiries(at: later)[id] == nil)
        #expect(try store.content(articleID: id, at: later) == nil)
        #expect(throws: (any Error).self) { try store.applyRetention(days: 0, at: later) }
        #expect(store.retentionDays == 7)
    }
    @Test func expiredContentCannotBeReadOrReimported() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let article = try #require(store.articles.first)
        let deadline = start.addingTimeInterval(30 * day)
        #expect(try store.content(articleID: article.id, at: deadline) == nil)
        _ = try store.importFeed(parsed(), receivedAt: deadline)
        #expect(article.summary.isEmpty)
        #expect(try store.content(articleID: article.id, at: deadline) == nil)
        #expect(article.firstReceivedAt == start)
        try store.applyRetention(days: 365, at: deadline)
        _ = try store.importFeed(parsed(), receivedAt: deadline.addingTimeInterval(day))
        #expect(try store.content(articleID: article.id, at: deadline) == nil)
    }
    @Test func aRemovedEntryIsCleanedAgainWithoutTouchingOtherContentOrSavingTwice() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let saves = TestBox(0)
        let store = try ReaderStore(container: container, now: start, saveHook: { saves.value += 1 })
        let parsed = try parsed()
        let feed = try store.importFeed(parsed, receivedAt: start)
        let article = try #require(store.articles.first)
        let at = start.addingTimeInterval(31 * day)
        try store.purgeExpired(at: at)
        let deletedAt = article.contentDeletedAt
        // A deletion marker alone must not hide bytes left in an inconsistent store.
        article.summary = "Leftover"; article.imageURL = "https://example.test/old.png"
        store.context.insert(ContentSnapshot(articleID: article.id, text: "Leftover body"))
        let other = Article(feedID: feed.id, title: "Other", summary: "Kept", publisher: "example", publishedAt: at, receivedAt: at)
        store.context.insert(other)
        store.context.insert(ContentSnapshot(articleID: other.id, text: "Kept body"))
        try store.save(); try store.reload()
        saves.value = 0
        for _ in 0..<2 {
            let failed = await store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: parsed.sourceURL.absoluteString, result: .modified(parsed, etag: nil, lastModified: nil))], at: at)
            #expect(failed.isEmpty)
        }
        #expect(saves.value == 2) // One save per refresh batch, even when an entry's content is already gone.
        #expect(article.contentDeletedAt == deletedAt && article.summary.isEmpty && article.imageURL == nil)
        let snapshots = try store.context.fetch(FetchDescriptor<ContentSnapshot>())
        #expect(snapshots.count == 1 && snapshots.first?.articleID == other.id)
        #expect(try store.content(articleID: other.id, at: at)?.text == "Kept body")
    }
    @Test func anExpiredRefreshWhoseSavesFailRestoresTheContentUntilRetry() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let fail = TestBox(false)
        let store = try ReaderStore(container: container, now: start, saveHook: { if fail.value { throw CocoaError(.fileWriteUnknown) } })
        let parsed = try parsed()
        let feed = try store.importFeed(parsed, receivedAt: start)
        let id = try #require(store.articles.first).id
        let at = start.addingTimeInterval(31 * day)
        let fetched = FetchedFeed(feedID: feed.id, sourceURL: parsed.sourceURL.absoluteString, result: .modified(parsed, etag: nil, lastModified: nil))
        fail.value = true
        #expect(await store.applyRefreshes([fetched], at: at)[feed.id] != nil)
        #expect(store.article(id: id)?.contentDeletedAt == nil)
        #expect(store.article(id: id)?.summary.isEmpty == false)
        #expect(try store.context.fetchCount(FetchDescriptor<ContentSnapshot>()) == 1)
        fail.value = false
        #expect(await store.applyRefreshes([fetched], at: at).isEmpty)
        #expect(store.article(id: id)?.contentDeletedAt == at && store.article(id: id)?.summary == "")
        #expect(try store.context.fetchCount(FetchDescriptor<ContentSnapshot>()) == 0)
    }
    @Test func deletionKeepsTheNoteAcrossReopen() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: start)
            let feed = try store.importFeed(parsed(), receivedAt: start)
            let article = try #require(store.articles.first)
            try store.markDisplayed(articleID: article.id, at: start)
            try store.saveNote(text: "残すノート", at: start)
            try store.deleteContent(articleIDs: [article.id], at: start)
            try store.unsubscribe(feed)
            #expect(article.firstReadAt == start && article.firstReceivedAt == start)
            _ = try store.importFeed(parsed(), receivedAt: start.addingTimeInterval(day))
            #expect(try store.content(articleID: article.id, at: start) == nil)
        }
        let reopened = try ReaderStore(url: library.url, now: start.addingTimeInterval(90 * day))
        #expect(reopened.notes.count == 1 && reopened.note?.text == "残すノート")
        #expect(reopened.articles.count == 1 && reopened.articles.first?.summary == "")
    }
    @Test func purgeExpiresContentAndNotifiesOnlyForChange() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: start)
        _ = try store.importFeed(parsed(), receivedAt: start)
        let later = start.addingTimeInterval(30 * day)
        try store.purgeExpired(at: later)
        try store.purgeExpired(at: later)
        #expect(store.articles.first?.summary == "")
        #expect(try store.availableContentExpiries(at: later).isEmpty)
    }
    @Test func failedSaveRollsBackAndDoesNotNotify() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let id = try autoreleasepool {
            let writable = try ReaderStore(url: library.url, now: start)
            _ = try writable.importFeed(parsed(), receivedAt: start)
            return try #require(writable.articles.first).id
        }
        let schema = ReaderStore.schema
        let configuration = ModelConfiguration("Reader", schema: schema, url: library.url, allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = try ReaderStore(container: container, now: start)
        let at = start.addingTimeInterval(10 * day)
        #expect(throws: (any Error).self) { try store.applyRetention(days: 7, at: at) }
        #expect(store.retentionDays == 30)
        #expect(try store.content(articleID: id, at: at)?.text.contains("本文 & 補足") == true)
        #expect(try store.availableContentExpiries(at: at)[id] == start.addingTimeInterval(30 * day))
    }
}
