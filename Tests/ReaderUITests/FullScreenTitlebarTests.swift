import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

/// Full screen (#373). A hosted test cannot reveal the menu bar and click the green button; the packaged app run is in the PR.
@Suite(EnglishLanguage()) @MainActor struct FullScreenTitlebarTests {
    /// With content under the title bar, the green button that came down with the menu bar sent its click to the content, and the
    /// window could not leave full screen. The content leaves the title bar in full screen and goes back under it before the window
    /// returns to its frame.
    /// The steps are called directly: a posted full-screen notification reaches AppKit too, and the hosted key tests that ran beside
    /// it failed.
    @Test func theContentLeavesTheTitleBarOnlyInFullScreen() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        FullScreenTitlebarFix.Anchor.entering(window)
        #expect(!window.styleMask.contains(.fullSizeContentView))
        FullScreenTitlebarFix.Anchor.leaving(window)
        #expect(window.styleMask.contains(.fullSizeContentView))
    }
}

extension SplitViewFoldTests {
    @Suite(.serialized) @MainActor struct FullScreenListTopTests {
        /// The first article stays at the same height below the band and the heading, whether the title bar lies under the content
        /// (a normal window) or not (full screen). In full screen it went up under the heading (#373).
        @Test func theFirstArticleKeepsItsPlaceWithOrWithoutTheTitleBar() async throws {
            let underTitleBar = try await firstRowTop(styleMask: [.titled, .fullSizeContentView])
            let withoutTitleBar = try await firstRowTop(styleMask: [.titled])
            #expect(abs(underTitleBar - withoutTitleBar) < 0.5, "first row at \(underTitleBar) pt and \(withoutTitleBar) pt")
            #expect(abs(underTitleBar - ListHeader.listTopInset) < 0.5)
        }

        /// From the top of the window's content to the top of the article list's rows.
        private func firstRowTop(styleMask: NSWindow.StyleMask) async throws -> CGFloat {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try inMemoryReaderStore()
            let entry = ParsedEntry(sourceID: "synthetic", title: "Synthetic article", url: nil, summary: "Synthetic summary", body: "Synthetic body", coverage: .feedProvided, publishedAt: .now)
            _ = try store.importFeed(ParsedFeed(title: "Synthetic feed", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: [entry], skippedEntries: 0), receivedAt: .now)
            let host = NSHostingView(rootView: ReaderView(store: store, refresh: FeedRefreshController(store: store), imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"))))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: styleMask, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
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
            // The top edge of the table, with the list scrolled to its top.
            let edge = table.convert(NSPoint(x: 0, y: table.bounds.minY), to: host)
            return host.isFlipped ? edge.y : host.bounds.maxY - edge.y
        }
    }
}
