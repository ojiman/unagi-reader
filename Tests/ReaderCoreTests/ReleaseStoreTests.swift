import Foundation
import Testing
@testable import ReaderCore

/// From 1.0 nothing is lost (specification 7.1, #450): a library written by the release opens with this code and reads back exactly what the
/// release read back, before and after a write and a reopen. CI runs it on every code change with a store made by
/// `scripts/make-release-store.sh` from `v1.0.0`, and fails when it does not run. Locally it is opt-in: set `UNAGI_READER_RELEASE_STORE_DIR`.
@MainActor struct ReleaseStoreTests {
    struct Expected: Decodable {
        struct FeedRecord: Decodable { let id: UUID; let title, folder, sourceURL: String }
        struct ArticleRecord: Decodable {
            let id, feedID: UUID
            let title, identityKey: String
            let firstReadAt, starredAt: Double                                         // -1: none
            let isRead: Bool
            let text: String?                                                          // nil: no content to show
            let links: [String]
        }
        let tag, commit: String
        let at, readAt: Double
        let feeds: [FeedRecord]
        let articles: [ArticleRecord]
        struct MembershipRecord: Decodable, Hashable { let feedID, articleID: UUID; let sourceID: String }
        struct ListRecord: Decodable { let feedID: UUID; let all, unread: [UUID] }
        let retentionDays, noteCount, unreadCount: Int
        let noteText: String
        let memberships: [MembershipRecord]
        let lists: [ListRecord]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNAGI_READER_RELEASE_STORE_DIR"] != nil,
                   "Set UNAGI_READER_RELEASE_STORE_DIR to a store made by scripts/make-release-store.sh (CI always does)."))
    func aLibraryWrittenByTheReleaseOpensAndKeepsEverything() throws {
        let path = try #require(ProcessInfo.processInfo.environment["UNAGI_READER_RELEASE_STORE_DIR"])
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: source.appending(path: "expected.json")))
        #expect(expected.tag == "v1.0.0")
        #expect(expected.articles.count == 4 && expected.articles.contains { $0.text == nil } && expected.articles.contains { !$0.links.isEmpty })
        #expect(expected.articles.contains { $0.firstReadAt >= 0 && !$0.isRead } && expected.articles.contains { $0.isRead })   // read state and first read are apart
        #expect(expected.memberships.count == expected.articles.count && expected.lists.count == expected.feeds.count)
        let library = try TestLibrary(); defer { library.cleanup() }
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix("Reader.store") {
            try FileManager.default.copyItem(at: file, to: library.url.deletingLastPathComponent().appending(path: file.lastPathComponent))
        }
        let at = Date(timeIntervalSince1970: expected.at), readAt = Date(timeIntervalSince1970: expected.readAt)
        func date(_ value: Double) -> Date? { value < 0 ? nil : Date(timeIntervalSince1970: value) }
        for round in 0..<3 {                                                       // open, write, close, open again, open again
            try autoreleasepool {
                let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(Double(round + 1) * 300))
                #expect(store.feeds.count == expected.feeds.count)
                for feed in expected.feeds {
                    let found = try #require(store.feed(id: feed.id), "subscription \(feed.title)")
                    #expect(found.title == feed.title && found.folder == feed.folder && found.sourceURL == feed.sourceURL)
                }
                #expect(Set(store.articles.map(\.id)) == Set(expected.articles.map(\.id)))
                for record in expected.articles {
                    let article = try #require(store.article(id: record.id), "article \(record.title)")
                    #expect(article.feedID == record.feedID && article.title == record.title && (article.identityKey ?? "") == record.identityKey)
                    #expect(article.firstReadAt == date(record.firstReadAt) && article.isRead == record.isRead && article.starredAt == date(record.starredAt))
                    let content = try store.content(articleID: record.id, at: readAt)
                    #expect(content?.text == record.text, "content of \(record.title)")
                    #expect((content?.bodyParagraphs.flatMap { $0.links.map(\.url) } ?? []) == record.links)
                }
                // The memberships build the subscription and folder lists (`reload()`); losing one would empty a list.
                #expect(Set(store.memberships.map { Expected.MembershipRecord(feedID: $0.feedID, articleID: $0.articleID, sourceID: $0.sourceID) })
                        == Set(expected.memberships))
                for list in expected.lists {
                    #expect(store.visibleArticleIDs(feedID: list.feedID, unreadOnly: false, keeping: nil) == list.all)
                    #expect(store.visibleArticleIDs(feedID: list.feedID, unreadOnly: true, keeping: nil) == list.unread)
                }
                #expect(store.unreadCount == expected.unreadCount)
                #expect(store.retentionDays == expected.retentionDays && store.notes.count == expected.noteCount)
                if round == 0 {
                    #expect(store.note?.text == expected.noteText)
                    try store.saveNote(text: expected.noteText + "\n- 次の版で書き足した", at: at.addingTimeInterval(1_000))
                } else {
                    #expect(store.note?.text == expected.noteText + "\n- 次の版で書き足した")
                }
            }
        }
    }
}
