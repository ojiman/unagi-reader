import AppKit
import QuartzCore
import SwiftUI
import Testing
import ReaderCore
@testable import UnagiReader

@Suite(EnglishLanguage()) @MainActor struct NativeArticleTextTests {
    @Test func pageMotionFollowsDirectionWithoutReplayingForContentUpdates() throws {
        let coordinator = NativeArticleText.Coordinator()
        let a = UUID(), b = UUID()
        let native = NativeArticleText(articleID: a, title: "合成記事", publisher: "SYNTHETIC", date: "", paragraphs: ["合成本文"], unavailable: nil, initialAnchor: nil, initialOffset: 0, reduceMotion: false, onScroll: { _, _ in }, onInteraction: {}, onDisplayBegin: {}, onDisplayed: {})
        let host = NSHostingView(rootView: native)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(findScroll).first
        }
        let scroll = try #require(findScroll(host))
        func screenDelta(_ move: CABasicAnimation) throws -> Double {
            let layer = try #require(scroll.layer), root = try #require(host.layer)
            let offset = try #require(move.fromValue as? Double)
            let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            let before = layer.convert(center, to: root)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = CATransform3DMakeTranslation(0, offset, 0)
            let after = layer.convert(center, to: root)
            layer.transform = CATransform3DIdentity; CATransaction.commit()
            return (after.y - before.y) * (host.isFlipped ? -1 : 1)
        }
        coordinator.animatePage(in: scroll, articleID: a, forward: true, reduceMotion: false)
        #expect(scroll.layer?.animation(forKey: "article-motion") == nil)
        coordinator.animatePage(in: scroll, articleID: b, forward: true, reduceMotion: false)
        let next = try #require(scroll.layer?.animation(forKey: "article-motion") as? CAAnimationGroup)
        let nextMove = try #require(next.animations?.first as? CABasicAnimation)
        #expect(nextMove.keyPath == "transform.translation.y")
        #expect(try screenDelta(nextMove) == -64)
        #expect((nextMove.toValue as? Double) == 0 && next.duration == 0.22)
        scroll.layer?.removeAnimation(forKey: "article-motion")
        coordinator.animatePage(in: scroll, articleID: b, forward: false, reduceMotion: false)
        #expect(scroll.layer?.animation(forKey: "article-motion") == nil)
        coordinator.animatePage(in: scroll, articleID: a, forward: false, reduceMotion: false)
        let previous = try #require(scroll.layer?.animation(forKey: "article-motion") as? CAAnimationGroup)
        let previousMove = try #require(previous.animations?.first as? CABasicAnimation)
        #expect(previousMove.keyPath == "transform.translation.y")
        #expect(try screenDelta(previousMove) == 64)
        coordinator.animatePage(in: scroll, articleID: a, forward: true, reduceMotion: true)
        #expect(scroll.layer?.animation(forKey: "article-motion") == nil)
        coordinator.animatePage(in: scroll, articleID: b, forward: true, reduceMotion: true)
        #expect(scroll.layer?.animation(forKey: "article-motion") == nil)
    }
    /// Decision 0056: the article ends with its text (or the sentence that there is none), with no coverage line under it.
    @Test func theArticleEndsWithItsTextAndNoCoverageLine() {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        for (paragraphs, last) in [(["取得できた合成要約"], "取得できた合成要約"), ([], "本文は利用できません。")] {
            view.install(title: "合成記事", publisher: "SYNTHETIC", date: "", paragraphs: paragraphs, unavailable: paragraphs.isEmpty ? "本文は利用できません。" : nil)
            #expect(view.string.hasPrefix("SYNTHETIC\n"))
            #expect(view.string.hasSuffix(last + "\n"))
        }
    }
    @Test func namedBodyLinkIsClickableAndQuoteIsIndented() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let text = "合成🙂：詳細はこちら"
        let range = (text as NSString).range(of: "詳細はこちら")
        let paragraph = BodyParagraph(text: text, links: [BodyLink(location: range.location, length: range.length, url: "https://synthetic.example/detail#section")], quoteDepth: 1)
        view.install(title: "合成", publisher: "SYNTHETIC", date: "", paragraphs: [text], unavailable: nil, bodyParagraphs: [paragraph])
        let body = (view.string as NSString).range(of: text)
        let index = body.location + range.location
        let link = try #require(view.textStorage?.attribute(.link, at: index, effectiveRange: nil) as? URL)
        #expect(link.absoluteString == "https://synthetic.example/detail#section")
        let style = try #require(view.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.headIndent > 0)
        var opened: URL?
        view.onOpenLink = { opened = $0; return true }
        #expect(view.textView(view, clickedOnLink: link, at: index))
        #expect(opened == link)
        #expect(view.textView(view, clickedOnLink: "file:///private/tmp/forbidden", at: index))
        #expect(opened == link)
        view.install(title: "次の記事", publisher: "SYNTHETIC", date: "", paragraphs: [text], unavailable: nil)
        let plain = (view.string as NSString).range(of: text)
        #expect(view.textStorage?.attribute(.link, at: plain.location + range.location, effectiveRange: nil) == nil)
    }
    @Test func fixedHeroArrivalDoesNotMoveReadingPosition() {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let hero = NSImageView()
        view.configureHero(hero)
        view.install(title: "合成", publisher: "SYNTHETIC", date: "", paragraphs: (0..<50).map { "段落 \($0)" }, unavailable: nil, hero: true)
        view.restore(anchor: "paragraph-7", offset: 12)
        let before = view.readingPosition()
        hero.image = NSImage(size: NSSize(width: 500, height: 300))
        view.layoutSubtreeIfNeeded()
        let after = view.readingPosition()
        #expect(hero.frame.height == 180)
        #expect(before.anchor == after.anchor && abs(before.offset - after.offset) < 1)
    }
    @Test func nativeListFocusIsRecognizedWithoutSwiftUIFocusState() {
        let table = NSTableView()
        #expect(ReaderKeyboardCommands.listHasFocus(declared: false, responder: table))
        #expect(!ReaderKeyboardCommands.listHasFocus(declared: false, responder: NSTextView()))
        #expect(ReaderKeyboardCommands.listHasFocus(declared: true, responder: nil))
    }
    @Test func paragraphPositionSurvivesNativeScrollAndWidthChange() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame)
        scroll.documentView = view
        let paragraphs = (0..<80).map { "合成段落\($0)。" + String(repeating: "日本語の長い文章です。", count: 20) }
        view.install(title: "合成タイトル", publisher: "SYNTHETIC", date: "2026/10/05", paragraphs: paragraphs, unavailable: nil)
        #expect(view.string.contains(paragraphs.last!))
        view.restore(anchor: "paragraph-7", offset: 23.5)
        let before = view.readingPosition()
        #expect(before.anchor == "paragraph-7")
        #expect(abs(before.offset - 23.5) < 1)
        scroll.setFrameSize(NSSize(width: 850, height: 400))
        view.setFrameSize(NSSize(width: 850, height: view.frame.height))
        view.restore(anchor: before.anchor, offset: before.offset)
        let after = view.readingPosition()
        #expect(after.anchor == before.anchor && abs(after.offset - before.offset) < 1)
    }

    @Test func displayStartPrecedesLayoutWithoutMarkingInvisibleBody() {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        var textAtStart: String?
        var displayed = 0
        view.onDisplayBegin = { textAtStart = view.string }
        view.onDisplayed = { displayed += 1 }
        view.install(title: "合成", publisher: "SYNTHETIC", date: "", paragraphs: ["新しい合成本文"], unavailable: nil)
        #expect(textAtStart == "")
        #expect(view.string.contains("新しい合成本文"))
        #expect(displayed == 0)
    }

    @Test func viewportResizeRoundTripsPreserveParagraphPositionAutomatically() {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        let paragraphs = (0..<80).map { "合成段落\($0)。" + String(repeating: "日本語の長い文章です。", count: 20) }
        view.install(title: "合成", publisher: "SYNTHETIC", date: "", paragraphs: paragraphs, unavailable: nil)
        view.restore(anchor: "paragraph-7", offset: 23.5)
        for _ in 0..<10 {
            for width in [850.0, 600.0] {
                scroll.setFrameSize(NSSize(width: width, height: 400))
                view.setFrameSize(NSSize(width: width, height: view.frame.height))
            }
            let position = view.readingPosition()
            #expect(position.anchor == "paragraph-7" && abs(position.offset - 23.5) < 1)
        }
    }

    @Test func headerOnlyViewportDoesNotCountBodyAsDisplayed() {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        let scroll = NSScrollView(frame: view.frame); scroll.documentView = view
        view.install(title: String(repeating: "長い合成タイトル ", count: 20), publisher: "SYNTHETIC", date: "2026/10/05", paragraphs: ["取得できた合成要約。"], unavailable: nil)
        view.restore(anchor: nil, offset: 0)
        #expect(!view.hasVisibleBody)
        view.restore(anchor: "paragraph-0", offset: 0)
        #expect(view.hasVisibleBody)
        view.install(title: "期限切れ", publisher: "SYNTHETIC", date: "", paragraphs: [], unavailable: "本文は利用できません。")
        #expect(!view.hasVisibleBody)
    }

    /// An article that fits the area shows no scroll bar, also when the next article replaces it; a long one shows it.
    @Test func theScrollBarShowsOnlyWhenTheArticleIsLongerThanTheArea() throws {
        func article(_ id: UUID, paragraphs: Int) -> NativeArticleText {
            NativeArticleText(articleID: id, title: "合成記事", publisher: "SYNTHETIC", date: "", paragraphs: (0..<paragraphs).map { "合成本文\($0)" }, unavailable: nil,
                              initialAnchor: nil, initialOffset: 0, reduceMotion: false, onScroll: { _, _ in }, onInteraction: {}, onDisplayBegin: {}, onDisplayed: {})
        }
        let host = NSHostingView(rootView: article(UUID(), paragraphs: 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(findScroll).first
        }
        let scroll = try #require(findScroll(host))
        for paragraphs in [1, 2, 80, 1] {
            host.rootView = article(UUID(), paragraphs: paragraphs); host.layoutSubtreeIfNeeded()
            let long = (scroll.documentView?.frame.height ?? 0) > scroll.contentSize.height
            #expect(scroll.verticalScroller?.isHidden == !long, "\(paragraphs) paragraphs")
        }
    }

    @Test func theHeadlineIsCalmerThanBodyEmphasis() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.install(title: "合成記事", publisher: "合成", date: "", paragraphs: ["合成本文"], unavailable: nil)
        let index = ("合成\n" as NSString).length
        let font = try #require(view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 26)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? 0
        #expect(weight > 0.2 && weight <= NSFont.Weight.semibold.rawValue + 0.01)               // semibold, not bold
    }
}
