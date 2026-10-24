import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// The schema 1.0 ships is frozen as a version (specification 7.1, #449). A library written before the schema had a version opens
/// with it and keeps everything.
@MainActor struct ReaderSchemaTests {
    let at = Date(timeIntervalSince1970: 1_791_152_000)

    @Test func theStoreUsesVersionOneWithTheSixModelsAndNoMigrationStage() {
        #expect(ReaderSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        let names = Set(ReaderStore.schema.entities.map(\.name))
        #expect(names == ["Feed", "Article", "ContentSnapshot", "FeedMembership", "ReaderSettings", "Note"])
        #expect(ReaderStore.schema.version == Schema.Version(1, 0, 0))
        #expect(ReaderMigrationPlan.schemas.map { $0.versionIdentifier } == [Schema.Version(1, 0, 0)])
        #expect(ReaderMigrationPlan.stages.isEmpty)
    }

    /// Writes a library with the schema as it was before #449: the same six models, with no version.
    private func writeUnversionedLibrary(at url: URL) throws -> (feedID: UUID, articleIDs: [UUID]) {
        let schema = Schema([Feed.self, Article.self, ContentSnapshot.self, FeedMembership.self, ReaderSettings.self, Note.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Reader", schema: schema, url: url, cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, now: at)
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://feed.example/rss")!)
        let feed = try store.importFeed(parsed, receivedAt: at, folder: "技術")
        let articleIDs = store.articles.map(\.id)
        let first = try #require(articleIDs.first)
        try store.markDisplayed(articleID: first, at: at.addingTimeInterval(60))
        try store.setStar(articleID: first, isStarred: true, at: at.addingTimeInterval(120))
        try store.applyRetention(days: 90, at: at.addingTimeInterval(180))
        try store.saveNote(text: "# 読んだこと\n- 自分の言葉で", at: at.addingTimeInterval(240))
        return (feed.id, articleIDs)
    }

    @Test func aLibraryWrittenWithoutAVersionOpensAndKeepsEverything() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let written = try autoreleasepool { try writeUnversionedLibrary(at: library.url) }
        for round in 0..<3 {                                                       // open, write, close, open again, open again
            try autoreleasepool {
                let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(Double(round + 1) * 1_000))
                #expect(store.feeds.map(\.id) == [written.feedID])
                #expect(store.feeds.first?.title == "合成ニュース" && store.feeds.first?.folder == "技術")
                #expect(store.articles.map(\.id) == written.articleIDs)
                let first = try #require(store.article(id: written.articleIDs[0]))
                #expect(first.firstReadAt == at.addingTimeInterval(60))
                #expect(first.starredAt == at.addingTimeInterval(120))
                #expect(try store.content(articleID: first.id, at: at.addingTimeInterval(300))?.paragraphs.isEmpty == false)
                #expect(store.retentionDays == 90)
                #expect(store.notes.count == 1)
                if round == 0 {
                    #expect(store.note?.text == "# 読んだこと\n- 自分の言葉で")
                    try store.saveNote(text: "# 読んだこと\n- 自分の言葉で\n- 続き", at: at.addingTimeInterval(1_500))
                } else {
                    #expect(store.note?.text == "# 読んだこと\n- 自分の言葉で\n- 続き")
                }
            }
        }
    }
}
