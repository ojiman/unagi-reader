import AppKit
import Testing
import ReaderCore
@testable import UnagiReader

/// The feed's images in the article text (decision 0066, #406).
@Suite(EnglishLanguage()) @MainActor struct BodyImageTextTests {
    private func cells(_ view: ArticleTextView) -> [(index: Int, cell: BodyImageCell)] {
        var found: [(Int, BodyImageCell)] = []
        let storage = view.textStorage!
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? BodyImageCell { found.append((range.location, cell)) }
        }
        return found
    }

    @Test func imagesSitWhereTheFeedPutsThemWithTheirLinks() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let text = "前🙂後ろ"
        let blocks = [BodyParagraph(text: "", images: [BodyImage(location: 0, url: "https://img.example/lead.jpg", link: "https://news.example/a")]),
                      BodyParagraph(text: text, images: [BodyImage(location: ("前🙂" as NSString).length, url: "https://img.example/icon.png", width: 40, height: 20)]),
                      BodyParagraph(text: "", images: [BodyImage(location: 0, url: "https://img.example/count.png", link: "https://b.example/entry"),
                                                       BodyImage(location: 0, url: "https://img.example/button.png")])]
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks)
        let string = view.string as NSString
        let found = cells(view)
        #expect(found.map(\.cell.url) == ["https://img.example/lead.jpg", "https://img.example/icon.png", "https://img.example/count.png", "https://img.example/button.png"])
        let start = string.range(of: "前🙂").location
        #expect(found[1].index == start + ("前🙂" as NSString).length)
        #expect(string.substring(with: NSRange(location: found[0].index, length: 2)) == "\u{FFFC}\n")       // a paragraph of its own
        #expect(found[3].index == found[2].index + 1)                                                    // one paragraph: side by side
        #expect((view.textStorage?.attribute(.link, at: found[0].index, effectiveRange: nil) as? URL)?.absoluteString == "https://news.example/a")
        #expect(view.textStorage?.attribute(.link, at: found[1].index, effectiveRange: nil) == nil)
        #expect(found[1].cell.cellSize() == NSSize(width: 40, height: 20))
        #expect(found[0].cell.cellSize().height <= 1)                 // no size yet: nothing is reserved that could jump
        // Selection, copy and 「記事をノートに送る」 carry the text, not the image characters.
        let all = NSRange(location: 0, length: string.length)
        #expect(!view.plainText([all]).contains("\u{FFFC}") && view.plainText([all]).contains("\n前🙂後ろ\n"))
    }

    /// Images of two blocks of the feed stand on two lines, whatever the width (review of #413).
    @Test func imagesOfSeparateBlocksStandOnSeparateLines() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let html = "<p><img src='https://img.example/1.png' width='120' height='80'></p><p><img src='https://img.example/2.png' width='120' height='80'></p>"
        let xml = "<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><title>合成</title><item><guid>a</guid><link>https://img.example/a</link><c:encoded><![CDATA[\(html)]]></c:encoded></item></channel></rss>"
        let blocks = try #require(try FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://img.example/rss")!).entries.first?.bodyParagraphs)
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        let tops = cells(view).map { manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: $0.index, length: 1), actualCharacterRange: nil), in: container).minY }
        #expect(tops.count == 2 && tops[1] >= tops[0] + 80)
    }

    /// An image paragraph in a quote is indented with the quoted text, clear of the quote's bar (review of #413).
    @Test func anImageOnlyQuoteParagraphKeepsItsIndent() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let html = "<blockquote><p><img src='https://img.example/photo.png' width='120' height='80'></p><p>Quoted text</p></blockquote>"
        let xml = "<rss xmlns:c='http://purl.org/rss/1.0/modules/content/'><channel><title>合成</title><item><guid>a</guid><link>https://img.example/a</link><c:encoded><![CDATA[\(html)]]></c:encoded></item></channel></rss>"
        let blocks = try #require(try FeedParser.parse(Data(xml.utf8), sourceURL: URL(string: "https://img.example/rss")!).entries.first?.bodyParagraphs)
        #expect(blocks.map(\.quoteDepth) == [1, 1])
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks)
        let index = try #require(cells(view).first?.index)
        let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent == 20 && style.firstLineHeadIndent == 20)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        let x = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil), in: container).minX
        let text = (view.string as NSString).range(of: "Quoted text").location
        let textX = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: NSRange(location: text, length: 1), actualCharacterRange: nil), in: container).minX
        #expect(x == 20 && x == textX)
    }

    @Test func aWideImageFitsTheColumn() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let paragraph = BodyParagraph(text: "本文", images: [BodyImage(location: 0, url: "https://img.example/wide.jpg", width: 2000, height: 1000)])
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: ["本文"], unavailable: nil, bodyParagraphs: [paragraph])
        let column = try #require(view.textContainer?.containerSize.width)
        let cell = try #require(cells(view).first?.cell)
        #expect(cell.cellSize().width == column && abs(cell.cellSize().height - column / 2) < 0.5)
        view.setFrameSize(NSSize(width: 400, height: view.frame.height))
        let narrower = try #require(view.textContainer?.containerSize.width)
        #expect(narrower < column && cell.cellSize().width == narrower)
        // In a quote, it fits the quote's indented column.
        let quoted = BodyParagraph(text: "本文", quoteDepth: 1, images: paragraph.images)
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: ["本文"], unavailable: nil, bodyParagraphs: [quoted])
        #expect(cells(view).first?.cell.cellSize().width == narrower - 20)
    }

    @Test func aLateImageDoesNotMoveTheTextBeingRead() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let texts = (0..<60).map { "合成段落\($0)。" + String(repeating: "日本語の本文です。", count: 12) }
        let blocks = texts.enumerated().map { index, text in
            BodyParagraph(text: text, images: index == 2 ? [BodyImage(location: 0, url: "https://img.example/late.jpg")] : nil)
        }
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: texts, unavailable: nil, bodyParagraphs: blocks)
        view.restore(anchor: "paragraph-30", offset: 12)
        let before = view.readingPosition()
        let screenY = before.offset
        view.show(NSImage(size: NSSize(width: 500, height: 300)), for: "https://img.example/late.jpg")
        let after = view.readingPosition()
        #expect(cells(view).first?.cell.cellSize() == NSSize(width: 500, height: 300))
        #expect(after.anchor == before.anchor && abs(after.offset - screenY) < 1)
        // An image that does not come (failed, offline) leaves everything as it was.
        view.show(nil, for: "https://img.example/never.jpg")
        #expect(view.readingPosition().anchor == before.anchor)
    }

    /// A failed image gives its reserved box back, and the text being read stays (review of #413).
    @Test func aFailedImageLeavesNoGapAndTheTextStays() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let texts = (0..<60).map { "合成段落\($0)。" + String(repeating: "日本語の本文です。", count: 12) }
        let url = "https://img.example/failed.png"
        let blocks = texts.enumerated().map { index, text in
            BodyParagraph(text: text, images: index == 2 ? [BodyImage(location: 0, url: url, width: 600, height: 400)] : nil)
        }
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: texts, unavailable: nil, bodyParagraphs: blocks)
        let cell = try #require(cells(view).first?.cell)
        #expect(cell.cellSize().height > 100)
        view.restore(anchor: "paragraph-30", offset: 12)
        let before = view.readingPosition()
        view.show(nil, for: url)
        #expect(cell.cellSize().height <= 1)
        let after = view.readingPosition()
        #expect(after.anchor == before.anchor && abs(after.offset - before.offset) < 1)
    }

    @Test func aBodyOfImagesOnlyIsDrawn() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let block = BodyParagraph(text: "", images: [BodyImage(location: 0, url: "https://img.example/comic.png", width: 300, height: 200)])
        view.install(title: "第1話", publisher: "合成購読", date: "", paragraphs: [""], unavailable: nil, bodyParagraphs: [block])
        #expect(cells(view).map(\.cell.url) == ["https://img.example/comic.png"])
        #expect(view.plainText([NSRange(location: 0, length: (view.string as NSString).length)]) == "合成購読\n第1話\n\n\n")
    }
}
