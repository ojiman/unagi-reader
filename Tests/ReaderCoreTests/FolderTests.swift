import Foundation
import Testing
@testable import ReaderCore

// Checks PRD-11 (specification 7).
@MainActor struct FolderTests {
    @Test func anAddressInTwoSubscriptionsCountsInEach() throws {                // decision 0067
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        for name in ["a", "b"] {
            let feed = try store.importFeed(FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://synthetic.example/" + name)!))
            try store.moveFeed(id: feed.id, toFolder: " 技術 ")
        }
        let article = try #require(store.articles.first)
        #expect(Set(store.folderArticleIDs(folder: "技術", keeping: nil)) == Set(store.articles.map(\.id)) && store.articles.count == 2)
        #expect(store.folderUnreadCount(folder: "技術") == 2)
        try store.markDisplayed(articleID: article.id, at: .now)
        #expect(store.folderUnreadCount(folder: "技術") == 1)
    }
    @Test func movingAndRenamingRetainsSelection() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let at = Date.now, store = try ReaderStore(url: library.url, seedDemo: true, now: at)
        let article = store.articles[0], feed = try #require(store.feed(id: article.feedID))
        try store.moveFeed(id: feed.id, toFolder: " 技術 ")
        let selected = store.folderArticleIDs(folder: "技術", keeping: article.id)
        try store.renameFolder(from: "技術", to: "技術")
        #expect(store.folderArticleIDs(folder: "技術", keeping: article.id) == selected)
        let other = try #require(store.feeds.first { $0.id != feed.id })
        try store.moveFeed(id: other.id, toFolder: "趣味")
        try store.renameFolder(from: "技術", to: " 趣味 ")
        #expect(feed.folder == "趣味" && store.feeds.filter { $0.folder == "技術" }.isEmpty)
        try store.moveFeed(id: feed.id, toFolder: "")
        #expect(store.folderArticleIDs(folder: "趣味", keeping: article.id).contains(article.id))
        #expect(!store.folderArticleIDs(folder: "趣味", keeping: nil).contains(article.id))
        try store.unsubscribe(feed)
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.feed(id: other.id)?.folder == "趣味")
    }

    @Test func droppingSubscriptionsOnAFolderMovesThemAndReportsWhetherAnythingChanged() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, seedDemo: true, now: .now)
        let first = store.feeds[0], second = store.feeds[1]
        #expect(try store.moveFeeds(ids: [first.id, second.id], toFolder: " 技術 "))
        #expect(first.folder == "技術" && second.folder == "技術")
        #expect(try !store.moveFeeds(ids: [first.id, second.id], toFolder: "技術"))               // already there: nothing to save
        #expect(try store.moveFeeds(ids: [first.id], toFolder: ""))                              // dropped on the sources header: unfiled
        #expect(first.folder == "" && second.folder == "技術")
        #expect(try !store.moveFeeds(ids: [UUID()], toFolder: "技術"))                           // an unknown subscription is ignored
        #expect(try !store.moveFeeds(ids: [], toFolder: "技術"))
    }
}
