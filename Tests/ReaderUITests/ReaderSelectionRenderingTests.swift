import AppKit
import SwiftUI
import Testing
import ReaderCore
@testable import UnagiReader

@Suite(EnglishLanguage()) @MainActor struct ReaderSelectionRenderingTests {
    @MainActor private final class Documents { var values: [String] = [] }

    /// #249: selecting a cached article must not lay out an unavailable-body document before its saved text.
    @Test func selectingCachedTextDoesNotRenderAnUnavailableBodyFirst() async throws {
        let store = try inMemoryReaderStore()
        let entries = (0..<3).map { index -> ParsedEntry in
            let summary: String = index == 2 ? "" : "Synthetic summary"
            let body: String = index == 2 ? "" : "Cached body \(index)"
            let publishedAt = Date.now.addingTimeInterval(Double(-index))
            return ParsedEntry(sourceID: "\(index)", title: "Cached story \(index)", url: URL(string: "https://synthetic.example/\(index)"),
                summary: summary, body: body, coverage: .feedProvided, publishedAt: publishedAt)
        }
        _ = try store.importFeed(ParsedFeed(title: "Synthetic", sourceURL: URL(string: "https://synthetic.example/rss")!, entries: entries, skippedEntries: 0))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store), imageLoader: ReaderImageLoader(directory: directory))
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close(); try? FileManager.default.removeItem(at: directory) }
        func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            (view as? T) ?? view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        func settle(until ready: () -> Bool) async throws {
            let end = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < end {
                host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                if ready() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(ready(), "The synthetic reader did not reach its final state")
        }
        try await settle { find(NativeArticleList.Table.self, in: host)?.numberOfRows == 3 }
        let table = try #require(find(NativeArticleList.Table.self, in: host))
        #expect(table.keyHandler?("j") == true)
        try await settle { find(ArticleTextView.self, in: host)?.string.contains("Cached body 0") == true }
        let text = try #require(find(ArticleTextView.self, in: host))
        let storage = try #require(text.textStorage)
        let documents = Documents()
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: .main) { notification in
            let string = (notification.object as? NSTextStorage)?.string
            MainActor.assumeIsolated {
                if let string { documents.values.append(string) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(table.keyHandler?("j") == true)
        host.layoutSubtreeIfNeeded()
        try await settle { text.string.contains("Cached body 1") }
        #expect(!documents.values.isEmpty)
        #expect(!documents.values.contains { $0.contains("The article body is unavailable.") })
        #expect(table.selectedRow == 1)
        try await settle { store.articles[1].firstReadAt != nil }
        #expect(table.keyHandler?("j") == true)
        try await settle { text.string.contains("The article body is unavailable.") }
        #expect(store.articles[2].firstReadAt == nil)
    }
}
