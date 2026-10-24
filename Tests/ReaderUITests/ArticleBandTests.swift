import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

/// Decision 0057: the article's buttons sit in the article column's own band at the top of the window, at its right end.
@Suite(EnglishLanguage(), .serialized) @MainActor struct ArticleBandTests {
    @Test func theArticleButtonsSitInTheArticleBand() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
        let entries = (0..<2).map { index in
            ParsedEntry(sourceID: "s\(index)", title: "合成記事 \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約",
                        body: "合成本文", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
        }
        _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
        let host = NSHostingView(rootView: ReaderView(store: store, refresh: FeedRefreshController(store: store),
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"))))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        func buttons(_ view: NSView) -> [NSButton] { ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap { buttons($0) } }
        for _ in 0..<250 where find(NativeArticleList.Table.self, in: host)?.numberOfRows != 2 {
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20))
        }
        let table = try #require(find(NativeArticleList.Table.self, in: host))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        for _ in 0..<250 where find(ArticleTextView.self, in: host)?.string.contains("合成記事 0") != true {
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20))
        }
        let article = try #require(find(ArticleTextView.self, in: host))
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded()
        let column = article.enclosingScrollView.map { $0.convert($0.bounds, to: nil) } ?? .zero
        // The band is the top 52 pt of the window (AppKit counts y from the bottom).
        let inBand = buttons(host).map { $0.convert($0.bounds, to: nil) }.filter { $0.minY >= 800 - ArticleBand.height && $0.width >= 20 }
        let articleButtons = inBand.filter { $0.minX >= column.minX && $0.maxX <= column.maxX + 1 }
        // note, send to the note (#417; its place is checked by the UI smoke test, which reads labels), Star, translate, globe
        #expect(articleButtons.count == 5, "buttons in the band: \(inBand)")
        #expect((articleButtons.map(\.maxX).max() ?? 0) > column.maxX - 60)                         // at the right end of the column
    }
}
