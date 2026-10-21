import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

extension SplitViewFoldTests {
    @Suite(.serialized) @MainActor struct FullScreenBandTests {
        /// The band must not depend on a toolbar's native safe-area inset (#373).
        @Test(arguments: [false, true])
        func theFirstArticleStaysBelowTheHeading(withToolbar: Bool) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try inMemoryReaderStore()
            let entry = ParsedEntry(sourceID: "synthetic", title: "Synthetic article", url: nil, summary: "Synthetic summary", body: "Synthetic body", coverage: .feedProvided, publishedAt: .now)
            _ = try store.importFeed(ParsedFeed(title: "Synthetic feed", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: [entry], skippedEntries: 0), receivedAt: .now)
            let host = NSHostingView(rootView: ReaderView(store: store, refresh: FeedRefreshController(store: store), imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"))))
            let style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: style, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            if withToolbar { window.toolbar = NSToolbar(identifier: "synthetic-band") }
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            func find(_ view: NSView) -> NativeArticleList.Table? {
                if let table = view as? NativeArticleList.Table { return table }
                for child in view.subviews { if let table = find(child) { return table } }
                return nil
            }
            for _ in 0..<250 {
                host.layoutSubtreeIfNeeded()
                if find(host)?.numberOfRows == 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let table = try #require(find(host))
            #expect(table.numberOfRows == 1)
            // The quiet selection is painted 2 pt inside its row; the transparent corner may sit under the heading.
            let row = table.convert(table.rect(ofRow: 0).insetBy(dx: 2, dy: 2), to: nil)
            let top = host.convert(host.bounds, to: nil).maxY - row.maxY
            let nativeInset = host.convert(host.bounds, to: nil).maxY - window.contentLayoutRect.maxY
            let headingBottom = nativeInset + ListHeader.bandHeight + ListHeader.height
            #expect(top >= headingBottom - 1 && top < headingBottom + 2 * NativeArticleList.Metrics.topInset,
                    "first row starts \(top) pt below the top")
        }
    }
}
