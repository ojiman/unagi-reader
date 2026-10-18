import Foundation
import SwiftData
import Testing
@testable import ReaderCore

@MainActor struct ArticleLoadingTests {
    /// A body that an earlier version took from the original page (the app no longer fetches pages; decision 0056).
    private func storeExtractedBody(_ text: String, for articleID: UUID, in store: ReaderStore) throws {
        let request = FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == articleID })
        if let snapshot = try store.context.fetch(request).first {
            snapshot.text = text; snapshot.coverageRaw = ContentCoverage.extracted.rawValue; snapshot.bodyFormatData = nil
        } else {
            store.context.insert(ContentSnapshot(articleID: articleID, text: text, coverage: .extracted))
        }
        try store.context.save(); try store.reload()
    }

    @Test func openingAnArticleShowsTheFeedText() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        _ = try store.importFeed(ArticleMarkupTests.feed())
        let article = try #require(store.articles.first)
        let loading = ArticleLoadingController(store: store)
        await loading.load(articleID: article.id)
        #expect(loading.displayed?.coverage == .feedProvided)
        #expect(article.firstReadAt == nil)                                                   // choosing content does not claim display
    }

    @Test func aBodyExtractedByAnEarlierVersionIsStillShown() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let xml = "<rss><channel><item><guid>a</guid><link>https://synthetic.example/posts/1</link><description>合成要約</description></item></channel></rss>"
        _ = try store.importFeed(FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://synthetic.example/rss")!))
        let article = try #require(store.articles.first)
        try storeExtractedBody("以前の抽出本文", for: article.id, in: store)
        let loading = ArticleLoadingController(store: store)
        await loading.load(articleID: article.id)
        #expect(loading.displayed?.text == "以前の抽出本文")                                     // saved data is not deleted (decision 0003)
    }

    @Test func aRefreshedBodyWaitsWhileThePersonReads() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        func feed(_ body: String) throws -> ParsedFeed {
            try FeedParser.parse(Data("<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><title>合成</title><item><guid>a</guid><link>https://synthetic.example/a</link><description>要約</description><c:encoded>\(body)</c:encoded></item></channel></rss>".utf8),
                                 sourceURL: URL(string: "https://synthetic.example/rss")!)
        }
        _ = try store.importFeed(feed("最初の本文"))
        let article = try #require(store.articles.first)
        let loading = ArticleLoadingController(store: store)
        await loading.load(articleID: article.id)
        loading.recordInteraction(articleID: article.id)                                       // the person is reading
        _ = try store.importFeed(feed("新しい本文"))
        loading.refreshCachedContent()
        #expect(loading.displayed?.text == "最初の本文")                                        // the reading position is not moved
        #expect(loading.availableUpdate?.text == "新しい本文")
        try loading.applyAvailableUpdate()
        #expect(loading.displayed?.text == "新しい本文" && loading.availableUpdate == nil)
    }

    @Test func anInteractionKeepsTheDisplayOfTheSelectedArticleOnly() {
        var state = ArticleLoadingState(); let a = UUID(), b = UUID()
        state.begin(articleID: a)
        #expect(state.mayReplaceCurrentDisplay)
        state.recordInteraction(articleID: b)                                                   // another article: ignored
        #expect(state.mayReplaceCurrentDisplay)
        state.recordInteraction(articleID: a)
        #expect(!state.mayReplaceCurrentDisplay)
        state.begin(articleID: b)
        #expect(state.mayReplaceCurrentDisplay && state.selectedArticleID == b)
    }
}
