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
        #expect(paragraphs.map(\.text) == ["合成記事 - 合成新聞", "合成の要約です。"])
        let cite = paragraphs[0], summary = paragraphs[1]
        // The favicon is inline, before the title.
        #expect(cite.images == [BodyImage(location: 0, url: "https://favicon.example/64?url=news")])
        // The entry image had a paragraph of its own: it opens the next paragraph, on its own line, with its link.
        #expect(summary.images?.first == BodyImage(location: 0, url: "https://img.example/a.jpg", link: "https://news.example/a", block: true))
        // The counter and the button had a paragraph with no text either, and come last.
        let length = ("合成の要約です。" as NSString).length
        #expect(summary.images?.dropFirst().map(\.url) == ["https://b.example/entry/image/a", "https://synthetic.example/images/append.gif"])
        #expect(summary.images?.dropFirst().allSatisfy { $0.location == length && $0.block && $0.link == "https://b.example/entry/a" } == true)
        #expect(summary.images?.last?.width == 16 && summary.images?.last?.height == 12)
        #expect(cite.quoteDepth == 1 && summary.quoteDepth == 1)
    }

    @Test func anImageInsideTextSitsAtItsOffset() throws {
        let paragraphs = try #require(ArticleMarkup.parse("<p>前🙂<img src='/a.png' width='40' height='20'>後ろ</p>", base: Self.base))
        #expect(paragraphs.map(\.text) == ["前🙂後ろ"])
        #expect(paragraphs[0].images == [BodyImage(location: ("前🙂" as NSString).length, url: "https://synthetic.example/a.png", width: 40, height: 20)])
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
        let paragraph = BodyParagraph(text: "原文の段落", images: [BodyImage(location: 0, url: "https://a.example/1.png", block: true),
                                                                   BodyImage(location: 2, url: "https://a.example/2.png")])
        let plan = TranslationPlan(title: "", content: ArticleContent(articleID: UUID(), text: "原文の段落", summary: "", coverage: .feedProvided,
                                                                     originalURL: nil, bodyParagraphs: [paragraph]), target: "en")
        let translated = plan.apply([0: "A translated paragraph"]).paragraphs[0]
        #expect(translated.images?.map(\.location) == [0, ("A translated paragraph" as NSString).length])
        #expect(translated.images?.map(\.url) == ["https://a.example/1.png", "https://a.example/2.png"])
    }
}
