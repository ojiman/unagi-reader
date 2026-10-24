import Foundation
import Testing
@testable import ReaderCore

@MainActor struct V1StoreUpgradeTests {
    struct Expected: Decodable {
        let baseline: String
        let at, start, end, firstReadAt: Double
        let feedID, articleID, noteID, periodID: UUID
        let dailyNoteID: UUID?
        let scrapKey: String?
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNAGI_READER_V1_FIXTURE_DIR"] != nil,
                   "Beta upgrade checks are opt-in; set UNAGI_READER_V1_FIXTURE_DIR to run."))
    func preservesReleasedV1Store() throws {
        let path = try #require(ProcessInfo.processInfo.environment["UNAGI_READER_V1_FIXTURE_DIR"], "Run scripts/prepare-v1-store-fixture.sh and set UNAGI_READER_V1_FIXTURE_DIR")
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: source.appending(path: "expected.json")))
        #expect(["53102cc42ea665b3379ad2a23d842c3186ad9c3e", "f9db83b49a82947a7031ddf874bc94fcb91ef89d", "1007dce64ebc5d1c9d7ac6f0b3e05869c8581ba4", "215b901ffc3863b3e1afd1e17a76b18101fc0cb6"].contains(expected.baseline))
        let library = try TestLibrary(); defer { library.cleanup() }
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("Reader.store") {
            try FileManager.default.copyItem(at: file, to: library.url.deletingLastPathComponent().appending(path: file.lastPathComponent))
        }
        let at = Date(timeIntervalSince1970: expected.at)
        for round in 0..<2 {
            try autoreleasepool {
                let store = try ReaderStore(url: library.url, now: at)
                let article = try #require(store.articles.first)
                #expect(store.feeds.map(\.id) == [expected.feedID])
                #expect(store.feeds.first?.title == "合成購読" && store.feeds.first?.folder == "技術")
                #expect(article.id == expected.articleID && article.title == "合成記事")
                #expect(article.firstReceivedAt == at && article.firstReadAt == Date(timeIntervalSince1970: expected.firstReadAt))
                // Decision 0067: the identity becomes the subscription's address and the link, so it is found again after resubscribing.
                #expect(article.identityKey == "https://synthetic.example/rss https://synthetic.example/article/1" && article.isRead)
                #expect(store.retentionDays == 90 && store.memberships.count == 1)
                #expect(try store.content(articleID: article.id, at: at)?.text == "合成RSS要約")
                // The old daily/weekly notes are intentionally not carried over (decision 0008); everything else is.
                #expect(article.starredAt == (expected.scrapKey == nil ? nil : at) && article.imageURL == nil)
                #expect(try store.content(articleID: article.id, at: at)?.bodyParagraphs.first?.links.isEmpty == true)
                // Decision 0049: the store has exactly one note, empty at first. It is written once and found again.
                if round == 0 {
                    #expect(store.notes.count == 1 && store.note?.text == "")
                    try store.saveNote(text: "# 移行後のノート\n", at: at)
                } else {
                    #expect(store.notes.count == 1 && store.note?.text == "# 移行後のノート\n")
                }
            }
        }
    }
}
