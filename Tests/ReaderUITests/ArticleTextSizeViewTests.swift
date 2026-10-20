import AppKit
import SwiftUI
import Testing
import ReaderCore
@testable import UnagiReader

// Specification 3.7: the article's text size.
@Suite(EnglishLanguage(), .serialized) @MainActor struct ArticleTextSizeViewTests {
    private func fontSize(_ view: NSTextView, of text: String) -> CGFloat? {
        let location = (view.string as NSString).range(of: text).location
        guard location != NSNotFound else { return nil }
        return (view.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont)?.pointSize
    }

    @Test func bodyTitleAndDateScaleWhileThePublisherStaysAHeading() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.install(title: "合成記事", publisher: "SYNTHETIC", date: "2026年10月17日", paragraphs: ["合成本文"], unavailable: nil, scale: 1)
        #expect(fontSize(view, of: "合成本文") == 16 && fontSize(view, of: "合成記事") == 26 && fontSize(view, of: "SYNTHETIC") == 12)
        let scale = CGFloat(ArticleTextSize.scale(22))
        view.install(title: "合成記事", publisher: "SYNTHETIC", date: "2026年10月17日", paragraphs: ["合成本文"], unavailable: nil, scale: scale)
        #expect(fontSize(view, of: "合成本文") == 22)
        #expect(fontSize(view, of: "合成記事") == 35.75)
        #expect(fontSize(view, of: "SYNTHETIC") == 12)
        #expect(fontSize(view, of: "2026年10月17日") == 16.5)
    }

    @Test func resizingAndBodySizeChangesKeepThePublisherAtTheTop() throws {
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        func install(_ scale: CGFloat) {
            view.install(title: "合成記事", publisher: "SYNTHETIC", date: "", paragraphs: ["合成本文"], unavailable: nil, scale: scale)
        }
        func publisherTop() throws -> CGFloat {
            let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
            manager.ensureLayout(for: container)
            return manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 9), in: container).minY + view.textContainerInset.height
        }
        install(1)
        let top = try publisherTop()
        for width in [360.0, 1200.0] {
            view.setFrameSize(NSSize(width: width, height: 500))
            install(CGFloat(ArticleTextSize.scale(22)))
            #expect(abs(try publisherTop() - top) < 0.5)
        }
    }

    /// The largest step in the narrowest article (360 pt, the note beside it): a long Japanese title still wraps into a few lines.
    @Test func aLongTitleAtTheLargestStepFitsTheNarrowArticle() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 700))
        let view = ArticleTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 700))
        scroll.documentView = view
        let title = "小さく作って毎日触ってみる、読む・選ぶ・保存するという一連の動き"     // 31 characters
        view.install(title: title, publisher: "SYNTHETIC", date: "", paragraphs: ["合成本文"], unavailable: nil, scale: CGFloat(ArticleTextSize.scale(22)))
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let range = manager.glyphRange(forCharacterRange: (view.string as NSString).range(of: title), actualCharacterRange: nil)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: range) { _, _, _, _, _ in lines += 1 }
        #expect(lines <= 5, "the title takes \(lines) lines")                        // 5 measured on macOS 27 (3 at the standard size)
    }

    @Test func changingTheSizeKeepsTheParagraphAtTheTop() async throws {
        let id = UUID()
        let paragraphs = (0..<60).map { "合成段落 \($0)。" + String(repeating: "読むことの楽しさ。", count: 12) }
        func article(_ scale: CGFloat) -> NativeArticleText {
            NativeArticleText(articleID: id, title: "合成記事", publisher: "SYNTHETIC", date: "", paragraphs: paragraphs, unavailable: nil,
                              initialAnchor: nil, initialOffset: 0, reduceMotion: true, onScroll: { _, _ in }, onInteraction: {},
                              onDisplayBegin: {}, onDisplayed: {}, textScale: scale)
        }
        let host = NSHostingView(rootView: article(1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let found = view as? T { return found }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        let text = try #require(find(ArticleTextView.self, in: host))
        text.restore(anchor: "paragraph-30", offset: 0)
        #expect(text.readingPosition().anchor == "paragraph-30")
        host.rootView = article(CGFloat(ArticleTextSize.scale(22)))
        host.layoutSubtreeIfNeeded()
        #expect(fontSize(text, of: "合成段落 30。") == 22)
        #expect(text.readingPosition().anchor == "paragraph-30")
        host.rootView = article(CGFloat(ArticleTextSize.scale(14)))
        host.layoutSubtreeIfNeeded()
        #expect(text.readingPosition().anchor == "paragraph-30")
    }
}
