import Foundation
import Testing
@testable import ReaderCore

/// A store written by `main` just before the schema got a version (#449) opens as `ReaderSchemaV1` and keeps everything (#451).
/// Opt-in: make the fixture with `scripts/prepare-v1-store-fixture.sh /private/tmp/unagi-reader-<name> d37f41b9c72613f207c5fc2d3a59ef2485e23879`
/// and set `UNAGI_READER_PRE_VERSION_FIXTURE_DIR` to it.
@MainActor struct PreVersionStoreUpgradeTests {
    struct Expected: Decodable {
        let baseline: String
        let at, firstReadAt, starredAt: Double
        let feedID, otherFeedID, readArticleID: UUID
        let articleIDs: [UUID]
        let noteText: String
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNAGI_READER_PRE_VERSION_FIXTURE_DIR"] != nil,
                   "Opt-in: set UNAGI_READER_PRE_VERSION_FIXTURE_DIR to a fixture made from d37f41b."))
    func aStoreWrittenBeforeTheVersionOpensAsVersionOne() throws {
        let path = try #require(ProcessInfo.processInfo.environment["UNAGI_READER_PRE_VERSION_FIXTURE_DIR"])
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: source.appending(path: "expected.json")))
        #expect(expected.baseline == "d37f41b9c72613f207c5fc2d3a59ef2485e23879")
        let library = try TestLibrary(); defer { library.cleanup() }
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("Reader.store") {
            try FileManager.default.copyItem(at: file, to: library.url.deletingLastPathComponent().appending(path: file.lastPathComponent))
        }
        let at = Date(timeIntervalSince1970: expected.at)
        for round in 0..<3 {                                                       // open, write, close, open again, open again
            try autoreleasepool {
                let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(Double(round + 1) * 1_000))
                #expect(Set(store.feeds.map(\.id)) == [expected.feedID, expected.otherFeedID])
                #expect(store.feed(id: expected.feedID)?.title == "合成購読" && store.feed(id: expected.feedID)?.folder == "技術")
                #expect(store.feed(id: expected.otherFeedID)?.folder == "")
                #expect(Set(store.articles.map(\.id)) == Set(expected.articleIDs))
                let read = try #require(store.article(id: expected.readArticleID))
                #expect(read.firstReadAt == Date(timeIntervalSince1970: expected.firstReadAt) && read.isRead)
                #expect(read.starredAt == Date(timeIntervalSince1970: expected.starredAt))
                #expect(store.articles.filter(\.isRead).map(\.id) == [expected.readArticleID])
                #expect(try store.content(articleID: read.id, at: at)?.text == "合成RSS要約1")
                #expect(store.retentionDays == 90 && store.memberships.count == expected.articleIDs.count)
                #expect(store.notes.count == 1)
                if round == 0 {
                    #expect(store.note?.text == expected.noteText)
                    try store.saveNote(text: expected.noteText + "\n- 1.0 で書き足した", at: at.addingTimeInterval(5_000))
                } else {
                    #expect(store.note?.text == expected.noteText + "\n- 1.0 で書き足した")
                }
            }
        }
    }
}
