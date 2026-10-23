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
        let paragraph = BodyParagraph(text: text, images: [
            BodyImage(location: 0, url: "https://img.example/lead.jpg", link: "https://news.example/a", block: true),
            BodyImage(location: ("前🙂" as NSString).length, url: "https://img.example/icon.png", width: 40, height: 20),
            BodyImage(location: (text as NSString).length, url: "https://img.example/count.png", link: "https://b.example/entry", block: true)])
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: [text], unavailable: nil, bodyParagraphs: [paragraph])
        let string = view.string as NSString
        let start = string.range(of: "前🙂").location - 2          // the lead image and its line break come first
        #expect(string.substring(with: NSRange(location: start, length: 2)) == "\u{FFFC}\u{2028}")
        let found = cells(view)
        #expect(found.map(\.cell.url) == ["https://img.example/lead.jpg", "https://img.example/icon.png", "https://img.example/count.png"])
        #expect(found.map(\.index) == [start, start + 2 + ("前🙂" as NSString).length, start + 2 + (text as NSString).length + 2])
        #expect(string.substring(with: NSRange(location: found[2].index - 1, length: 1)) == "\u{2028}")
        #expect((view.textStorage?.attribute(.link, at: found[0].index, effectiveRange: nil) as? URL)?.absoluteString == "https://news.example/a")
        #expect(view.textStorage?.attribute(.link, at: found[1].index, effectiveRange: nil) == nil)
        #expect(found[1].cell.cellSize() == NSSize(width: 40, height: 20))
        #expect(found[0].cell.cellSize().height <= 1)                 // no size yet: nothing is reserved that could jump
        // Selection, copy and 「記事をノートに送る」 carry the text, not the image characters.
        let all = NSRange(location: 0, length: string.length)
        #expect(!view.plainText([all]).contains("\u{FFFC}") && view.plainText([all]).contains("\n前🙂後ろ\n"))
    }

    @Test func aWideImageFitsTheColumn() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let paragraph = BodyParagraph(text: "本文", images: [BodyImage(location: 0, url: "https://img.example/wide.jpg", width: 2000, height: 1000, block: true)])
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
            BodyParagraph(text: text, images: index == 2 ? [BodyImage(location: 0, url: "https://img.example/late.jpg", block: true)] : nil)
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
}
