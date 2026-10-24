import Foundation
import Testing
@testable import ReaderCore

/// Images in the feed's HTML stay where the feed puts them (decision 0066, #406).
struct BodyImageMarkupTests {
    static let base = URL(string: "https://synthetic.example/feed")!

    /// The shape of a Hatena Bookmark entry's `content:encoded`, with synthetic addresses.
    static let bookmark = """
    <blockquote cite="https://news.example/a"><cite><img src="https://favicon.example/64?url=news" alt="" /> <a href="https://news.example/a">合成記事 - 合成新聞</a></cite>\
    <p><a href="https://news.example/a"><img src="https://img.example/a.jpg" class="entry-image" /></a></p>\
    <p>合成の要約です。</p>\
    <p><a href="https://b.example/entry/a"><img src="https://b.example/entry/image/a" alt="" border="0" /></a> \
    <a href="https://b.example/entry/a"><img src="/images/append.gif" width="16" height="12" /></a></p></blockquote>
    """

    @Test func everyImageOfABookmarkEntryKeepsItsPlaceAndItsLink() throws {
        let paragraphs = try #require(ArticleMarkup.parse(Self.bookmark, base: Self.base))
        // A block with images and no text is a paragraph without text: the feed's blocks stay apart (review of #413).
        #expect(paragraphs.map(\.text) == ["合成記事 - 合成新聞", "", "合成の要約です。", ""])
        // The favicon is inline, before the title.
        #expect(paragraphs[0].images == [BodyImage(location: 0, url: "https://favicon.example/64?url=news")])
        #expect(paragraphs[1].images == [BodyImage(location: 0, url: "https://img.example/a.jpg", link: "https://news.example/a")])
        #expect(paragraphs[2].images == nil)
        // The counter and the button share their paragraph, and stay together.
        #expect(paragraphs[3].images?.map(\.url) == ["https://b.example/entry/image/a", "https://synthetic.example/images/append.gif"])
        #expect(paragraphs[3].images?.allSatisfy { $0.location == 0 && $0.link == "https://b.example/entry/a" } == true)
        #expect(paragraphs[3].images?.last?.width == 16 && paragraphs[3].images?.last?.height == 12)
        #expect(paragraphs.allSatisfy { $0.quoteDepth == 1 })
    }

    @Test func anImageInsideTextSitsAtItsOffset() throws {
        let paragraphs = try #require(ArticleMarkup.parse("<p>前🙂<img src='/a.png' width='40' height='20'>後ろ</p>", base: Self.base))
        #expect(paragraphs.map(\.text) == ["前🙂後ろ"])
        #expect(paragraphs[0].images == [BodyImage(location: ("前🙂" as NSString).length, url: "https://synthetic.example/a.png", width: 40, height: 20)])
    }

    /// A comic or photo entry: the body has images and no text (review of #413).
    @Test func aBodyOfImagesOnlyKeepsThemInAParagraphWithoutText() throws {
        let paragraphs = try #require(ArticleMarkup.parse("<p><img src='https://synthetic.example/comic.png'></p><p><a href='/next'><img src='/b.png'></a></p>", base: Self.base))
        #expect(paragraphs == [BodyParagraph(text: "", images: [BodyImage(location: 0, url: "https://synthetic.example/comic.png")]),
                               BodyParagraph(text: "", images: [BodyImage(location: 0, url: "https://synthetic.example/b.png", link: "https://synthetic.example/next")])])
    }

    @MainActor @Test func aBodyOfImagesOnlyIsSavedShownAndExpired() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let at = Date(timeIntervalSince1970: 1_000_000)
        let xml = "<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><title>合成</title><item><guid>a</guid><link>https://synthetic.example/comic/1</link><description>第1話</description><c:encoded><![CDATA[<p><img src='https://synthetic.example/comic.png'></p>]]></c:encoded></item></channel></rss>"
        try store.importFeed(try FeedParser.parse(Data(xml.utf8), sourceURL: Self.base), receivedAt: at)
        let article = try #require(store.articles.first)
        let content = try #require(try store.content(articleID: article.id, at: at))
        #expect(content.paragraphs == [""] && content.coverage == .feedProvided)
        #expect(content.bodyParagraphs.first?.images?.map(\.url) == ["https://synthetic.example/comic.png"])
        // Nothing to translate but the title.
        #expect(TranslationPlan(title: "題", content: content, target: "en").items.map(\.index) == [TranslationPlan.titleIndex])
        try store.markDisplayed(articleID: article.id, at: at)
        #expect(store.article(id: article.id)?.isRead == true)
        // Retention counts it as a body and removes it.
        #expect(try store.previewDeletion(days: 7, at: at.addingTimeInterval(86_400 * 8)).bodyCount == 1)
        try store.deleteContent(articleIDs: [article.id], at: at)
        #expect(try store.content(articleID: article.id, at: at) == nil)
    }

    /// The summary the list shows has the text only, without the empty paragraphs of image blocks.
    @Test func theSummaryOfABodyWithImageBlocksHasNoEmptyLines() throws {
        let xml = "<rss><channel><title>合成</title><item><guid>a</guid><link>https://synthetic.example/a</link><description><![CDATA[<p><img src='https://synthetic.example/a.png'></p><p>要約です。</p>]]></description></item></channel></rss>"
        let entry = try #require(try FeedParser.parse(Data(xml.utf8), sourceURL: Self.base).entries.first)
        #expect(entry.summary == "要約です。")
        #expect(entry.bodyParagraphs?.map(\.text) == ["", "要約です。"] && entry.body == "\n\n要約です。")
    }

    @Test func onlyWebImagesAreKept() throws {
        let html = "<p>本文<img src='javascript:alert(1)'><img src='data:image/png;base64,AAAA'><img><img src='file:///private/tmp/x.png'><img src='https://ok.example/x.png' width='wide'></p>"
        let paragraphs = try #require(ArticleMarkup.parse(html, base: Self.base))
        #expect(paragraphs[0].images == [BodyImage(location: 2, url: "https://ok.example/x.png")])
    }

    @Test func aBodyWithoutImagesSavesWhatItSavedBefore() throws {
        let paragraphs = try #require(ArticleMarkup.parse("<p>本文<a href='/x'>リンク</a></p>", base: Self.base))
        #expect(paragraphs[0].images == nil)
        let saved = try #require(BodyParagraph.encode(paragraphs))
        #expect(!String(decoding: saved, as: UTF8.self).contains("images"))
        // A body saved by an earlier version, with no images key, still reads.
        let earlier = Data(#"[{"text":"本文","links":[],"quoteDepth":0}]"#.utf8)
        #expect(BodyParagraph.decode(earlier, matching: "本文") == [BodyParagraph(text: "本文")])
    }

    @Test func aTranslatedParagraphKeepsItsImagesAtItsEdges() {
        let paragraph = BodyParagraph(text: "原文の段落", images: [BodyImage(location: 0, url: "https://a.example/1.png"),
                                                                   BodyImage(location: 2, url: "https://a.example/2.png")])
        let plan = TranslationPlan(title: "", content: ArticleContent(articleID: UUID(), text: "原文の段落", summary: "", coverage: .feedProvided,
                                                                     originalURL: nil, bodyParagraphs: [paragraph]), target: "en")
        let translated = plan.apply([0: "A translated paragraph"]).paragraphs[0]
        #expect(translated.images?.map(\.location) == [0, ("A translated paragraph" as NSString).length])
        #expect(translated.images?.map(\.url) == ["https://a.example/1.png", "https://a.example/2.png"])
    }
}
