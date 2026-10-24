import AppKit
import Testing
import ReaderCore
@testable import UnagiReader

/// Headings, lists, code, emphasis and tables of the feed's HTML in the article text (decision 0066, #407).
@Suite(EnglishLanguage()) @MainActor struct BodyStructureTextTests {
    private let blocks = [
        BodyParagraph(text: "大見出し", heading: 2),
        BodyParagraph(text: "本文の太字と斜体とcode()です", styles: [BodyStyle(location: 3, length: 2, kind: .strong), BodyStyle(location: 6, length: 2, kind: .emphasis),
                                                                 BodyStyle(location: 9, length: 6, kind: .code)]),
        BodyParagraph(text: "• 項目", listDepth: 1),
        BodyParagraph(text: "1. 入れ子", listDepth: 2),
        BodyParagraph(text: "let x = 1\n  print(x)", code: true),
        BodyParagraph(text: "名前\t値", table: true)]

    private func install(scale: CGFloat = 1) -> ArticleTextView {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        view.install(title: "合成", publisher: "合成購読", date: "", paragraphs: blocks.map(\.text), unavailable: nil, bodyParagraphs: blocks, scale: scale)
        return view
    }
    private func at(_ view: ArticleTextView, _ text: String, offset: Int = 0) -> [NSAttributedString.Key: Any] {
        let location = (view.string as NSString).range(of: text).location + offset
        return view.textStorage!.attributes(at: location, effectiveRange: nil)
    }

    @Test func eachKindHasItsLook() throws {
        let view = install()
        let body = try #require(at(view, "本文")[.font] as? NSFont)
        let heading = try #require(at(view, "大見出し")[.font] as? NSFont)
        #expect(heading.pointSize > body.pointSize && heading.pointSize < 26)            // the title stays the largest
        #expect(heading.fontDescriptor.symbolicTraits.contains(.bold) || (heading.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? Double ?? 0 > 0.2)
        #expect((at(view, "太字")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect((at(view, "code()")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect((at(view, "let x")[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        let item = try #require(at(view, "• 項目")[.paragraphStyle] as? NSParagraphStyle)
        let nested = try #require(at(view, "1. 入れ子")[.paragraphStyle] as? NSParagraphStyle)
        #expect(item.firstLineHeadIndent > 0 && item.headIndent > item.firstLineHeadIndent)    // a hanging indent for the marker
        #expect(nested.firstLineHeadIndent > item.firstLineHeadIndent)
        #expect((view.string as NSString).range(of: "let x = 1\u{2028}  print(x)").location != NSNotFound)   // one paragraph, two lines
        let row = try #require(at(view, "名前")[.paragraphStyle] as? NSParagraphStyle)
        #expect(!row.tabStops.isEmpty && row.tabStops[0].location > 40)
        // Copy keeps the markers, line breaks and tabs.
        #expect(view.plainText([NSRange(location: 0, length: (view.string as NSString).length)]).contains("• 項目\n1. 入れ子\nlet x = 1\n  print(x)\n名前\t値"))
    }

    @Test func sizesFollowTheArticleTextSize() throws {
        let standard = install(), larger = install(scale: 1.25)
        for text in ["大見出し", "let x", "code()"] {
            let a = try #require(at(standard, text)[.font] as? NSFont), b = try #require(at(larger, text)[.font] as? NSFont)
            #expect(abs(b.pointSize - a.pointSize * 1.25) < 0.01)
        }
    }
}
