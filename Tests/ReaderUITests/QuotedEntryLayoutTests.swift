import AppKit
import Testing
import ReaderCore
@testable import UnagiReader

/// A quoted bookmark entry reads as one quote: one bar, and images taller than the text on lines of their own (#429).
@Suite(EnglishLanguage()) @MainActor struct QuotedEntryLayoutTests {
    private func cells(_ view: ArticleTextView) -> [(index: Int, cell: BodyImageCell)] {
        var found: [(Int, BodyImageCell)] = []
        let storage = view.textStorage!
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? BodyImageCell { found.append((range.location, cell)) }
        }
        return found
    }
    private func rect(_ view: ArticleTextView, _ index: Int) -> NSRect {
        let manager = view.layoutManager!
        return manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil),
                                    in: view.textContainer!)
    }
    private func index(_ view: ArticleTextView, of text: String) -> Int { (view.string as NSString).range(of: text).location }

    /// The shape of the entry the owner saw, with synthetic addresses: the favicon and the linked title in `cite`, the entry image,
    /// the summary, and the counter with the button.
    static let entry = """
    <blockquote><cite><img src="https://favicon.example/64" alt="" /> <a href="https://news.example/a">合成記事の見出し | 合成新聞</a></cite>\
    <p><a href="https://news.example/a"><img src="https://img.example/a.jpg" class="entry-image" /></a></p>\
    <p>合成の要約です。</p>\
    <p><a href="https://b.example/entry/a"><img src="https://b.example/entry/image/a" alt="" /></a> <a href="https://b.example/entry/a"><img src="https://b.example/append.gif" /></a></p></blockquote>\
    <p>引用の外</p><blockquote><p>外側</p><blockquote><p>内側</p></blockquote><p>また外側</p></blockquote>
    """
    private func install(_ view: ArticleTextView) throws {
        let xml = "<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><title>合成</title><item><guid>a</guid><link>https://news.example/a</link><c:encoded><![CDATA[\(Self.entry)]]></c:encoded></item></channel></rss>"
        let blocks = try #require(try FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://b.example/rss")!).entries.first?.bodyParagraphs)
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks)
    }
    private func picture(_ width: CGFloat, _ height: CGFloat) -> NSImage { NSImage(size: NSSize(width: width, height: height)) }

    @Test func aQuoteHasOneBarAlongAllItsParagraphs() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        try install(view)
        view.show(picture(64, 64), for: "https://favicon.example/64")
        view.show(picture(120, 90), for: "https://img.example/a.jpg")
        let bars = view.quoteBarRects()
        // The bookmark quote, then 「外側」…「また外側」 with 「内側」 inside it.
        #expect(bars.count == 3)
        let first = try #require(bars.first)
        let top = rect(view, cells(view)[0].index).minY + view.textContainerOrigin.y
        let bottom = rect(view, cells(view)[3].index).maxY + view.textContainerOrigin.y
        #expect(first.minY <= top + 0.5 && first.maxY >= bottom - 0.5)                    // through the paragraph spacing
        #expect(!first.intersects(NSRect(x: 0, y: rect(view, index(view, of: "引用の外")).midY + view.textContainerOrigin.y, width: 1_000, height: 1)))
        let outer = bars[1], inner = bars[2]
        #expect(inner.minX > outer.minX)
        #expect(outer.minY <= rect(view, index(view, of: "外側")).minY + view.textContainerOrigin.y + 0.5)
        #expect(outer.maxY >= rect(view, index(view, of: "また外側")).maxY + view.textContainerOrigin.y - 0.5)
        #expect(inner.minY >= outer.minY && inner.maxY <= outer.maxY)
    }

    @Test func anImageTallerThanTheTextStandsOnALineOfItsOwn() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        try install(view)
        let favicon = cells(view)[0], title = index(view, of: "合成記事の見出し")
        #expect(abs(rect(view, favicon.index).midY - rect(view, title).midY) < 20)          // no size yet: in the line
        view.show(picture(64, 64), for: "https://favicon.example/64")
        #expect(rect(view, title).minY >= rect(view, favicon.index).maxY - 0.5)           // the title starts below the favicon
        #expect(favicon.cell.pictureSize == NSSize(width: 64, height: 64))
        // The counter and the button are no taller than the text: side by side.
        view.show(picture(44, 13), for: "https://b.example/entry/image/a")
        view.show(picture(16, 12), for: "https://b.example/append.gif")
        let counter = cells(view)[2], button = cells(view)[3]
        #expect(abs(rect(view, counter.index).minY - rect(view, button.index).minY) < 2 && rect(view, button.index).minX > rect(view, counter.index).minX)
    }

    @Test func aTallImageMovesWithoutMovingTheTextBeingRead() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let texts = (0..<60).map { "合成段落\($0)。" + String(repeating: "日本語の本文です。", count: 12) }
        let blocks = texts.enumerated().map { index, text in
            BodyParagraph(text: text, quoteDepth: index < 4 ? 1 : 0, images: index == 2 ? [BodyImage(location: 0, url: "https://img.example/late.png")] : nil)
        }
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: texts, unavailable: nil, bodyParagraphs: blocks)
        view.restore(anchor: "paragraph-30", offset: 12)
        let before = view.readingPosition()
        view.show(picture(300, 200), for: "https://img.example/late.png")
        let after = view.readingPosition()
        #expect(after.anchor == before.anchor && abs(after.offset - before.offset) < 1)
        #expect(rect(view, index(view, of: "合成段落2。")).minY >= rect(view, cells(view)[0].index).maxY - 0.5)
    }

    @Test func anImageNeverRunsPastTheIndentedColumn() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let column = try #require(view.textContainer?.containerSize.width)
        let blocks = [BodyParagraph(text: "• 項目", images: [BodyImage(location: 2, url: "https://img.example/wide.png", width: 2000, height: 1000)], listDepth: 2),
                      BodyParagraph(text: "引用", quoteDepth: 2, images: [BodyImage(location: 0, url: "https://img.example/wide2.png", width: 2000, height: 1000)])]
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks)
        for found in cells(view) {
            let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: found.index, effectiveRange: nil) as? NSParagraphStyle)
            #expect(found.cell.cellSize().width <= column - max(style.headIndent, style.firstLineHeadIndent) + 0.5)
            #expect(rect(view, found.index).maxX <= column + 0.5)
        }
    }
}
