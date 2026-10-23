import Foundation
import Testing
@testable import ReaderCore

/// Headings, lists, code, emphasis and tables of the feed's HTML keep their kind (decision 0066, #407).
struct BodyStructureMarkupTests {
    static let base = URL(string: "https://synthetic.example/feed")!
    private func parse(_ html: String) throws -> [BodyParagraph] { try #require(ArticleMarkup.parse(html, base: Self.base)) }

    @Test func headingsKeepTheirLevel() throws {
        let paragraphs = try parse("<h1>大見出し</h1><p>本文</p><h3>小見出し</h3><h6>最小</h6>")
        #expect(paragraphs.map(\.text) == ["大見出し", "本文", "小見出し", "最小"])
        #expect(paragraphs.map(\.heading) == [1, nil, 3, 6])
    }

    @Test func listsKeepTheirMarkersAndDepth() throws {
        let paragraphs = try parse("<ul><li>りんご</li><li>みかん<ol><li>一つ目</li><li><p>二つ目</p><p>続き</p></li></ol></li></ul><ol start='3'><li>三</li></ol>")
        #expect(paragraphs.map(\.text) == ["• りんご", "• みかん", "1. 一つ目", "2. 二つ目", "続き", "3. 三"])
        #expect(paragraphs.map { $0.listDepth ?? 0 } == [1, 1, 2, 2, 2, 1])
        #expect(try parse("<ul><li>外<ul><li>内</li></ul></li></ul>").map(\.text) == ["• 外", "◦ 内"])
    }

    @Test func codeBlocksAndInlineStylesAreMarked() throws {
        let paragraphs = try parse("<pre><code>let x = 1\n  print(x)</code></pre><p>これは<strong>太字</strong>と<em>斜体</em>と<code>code()</code>です</p>")
        #expect(paragraphs[0].code == true && paragraphs[0].text == "let x = 1\n  print(x)")
        let text = paragraphs[1].text as NSString
        #expect(paragraphs[1].code == nil)
        #expect(paragraphs[1].styles == [
            BodyStyle(location: text.range(of: "太字").location, length: 2, kind: .strong),
            BodyStyle(location: text.range(of: "斜体").location, length: 2, kind: .emphasis),
            BodyStyle(location: text.range(of: "code()").location, length: 6, kind: .code)])
    }

    @Test func aTableIsRowsWithSeparatedCells() throws {
        let paragraphs = try parse("<table><tr><th>名前</th><th>値</th></tr><tr><td>速度</td><td><b>8</b> 倍</td></tr></table>")
        #expect(paragraphs.map(\.text) == ["名前\t値", "速度\t8 倍"])
        #expect(paragraphs.allSatisfy { $0.table == true })
        #expect(paragraphs[0].styles == [BodyStyle(location: 0, length: 2, kind: .strong), BodyStyle(location: 3, length: 1, kind: .strong)])   // header cells
        #expect(paragraphs[1].styles == [BodyStyle(location: 3, length: 1, kind: .strong)])
    }

    @Test func aPlainParagraphIsSavedAsBefore() throws {
        let paragraphs = try parse("<p>本文<a href='/x'>リンク</a></p>")
        let saved = String(decoding: try #require(BodyParagraph.encode(paragraphs)), as: UTF8.self)
        for key in ["heading", "listDepth", "code", "table", "styles"] { #expect(!saved.contains(key)) }
    }

    @Test func aTranslatedParagraphKeepsItsKindButNotItsStyles() {
        let paragraph = BodyParagraph(text: "見出し", heading: 2, styles: [BodyStyle(location: 0, length: 1, kind: .strong)])
        let plan = TranslationPlan(title: "", content: ArticleContent(articleID: UUID(), text: "見出し", summary: "", coverage: .feedProvided,
                                                                     originalURL: nil, bodyParagraphs: [paragraph]), target: "en")
        let translated = plan.apply([0: "Heading"]).paragraphs[0]
        #expect(translated.heading == 2 && translated.styles == nil)
    }
}
