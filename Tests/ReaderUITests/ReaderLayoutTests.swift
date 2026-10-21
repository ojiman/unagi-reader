import AppKit
import SwiftUI
import WebKit
import ReaderCore
import Testing
@testable import UnagiReader

/// The tests that fold the split view's columns in a hosted window. Two windows that fold at the same time disturb each other (the
/// sidebar of one stays open), so the suites in this one run one after the other.
@Suite(EnglishLanguage(), .serialized) enum SplitViewFoldTests {}

extension SplitViewFoldTests {
    // Checks PRD-01 (specification 7).
    @Suite(EnglishLanguage(), .serialized) @MainActor struct ReaderLayoutTests {
        private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        private func settle(_ host: NSView, line: Int = #line, state: () -> String = { "" }, until ready: () -> Bool) async throws {
            for _ in 0..<250 {
                host.layoutSubtreeIfNeeded()
                if ready() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(ready(), "Synthetic reader did not reach the expected state \(state())", sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1))
        }
        @Test func originalPageFoldsTheSidebarAndClosingBringsItBack() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
            let entries = (0..<3).map { index in
                ParsedEntry(sourceID: "synthetic-\(index)", title: "合成記事 \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約", body: "合成本文", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
            }
            _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
            let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
                imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")))
            let host = NSHostingView(rootView: reader)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-reader-layout")
            window.contentView = host
            window.orderFront(nil)      // the fold is an animation; a window that is never shown does not run it on time
            defer { window.close() }
            func sidebarVisible() -> Bool {
                guard let sidebar = find(NSOutlineView.self, in: host) else { return false }
                return !sidebar.isHiddenOrHasHiddenAncestor && sidebar.visibleRect.width > 80
            }
            try await settle(host) { find(NativeArticleList.Table.self, in: host)?.numberOfRows == 3 && sidebarVisible() }
            let table = try #require(find(NativeArticleList.Table.self, in: host))
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(host) { find(ArticleTextView.self, in: host)?.string.contains("合成記事 0") == true }
            let frame = table.convert(table.bounds, to: nil)
            func listIsBack() -> Bool { abs(table.convert(table.bounds, to: nil).minX - frame.minX) < 1 && abs(table.bounds.width - frame.width) < 1 }
            func state() -> String { "[sidebar \(sidebarVisible()), list x \(table.convert(table.bounds, to: nil).minX), page \(pageIsClosed() ? "closed" : "open")]" }
            func pageIsClosed() -> Bool { find(OriginalReaderWebView.self, in: host) == nil && find(OriginalFailureHostingView<AnyView>.self, in: host) == nil }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))      // the window has just appeared; a person does not press `v` in its first frame
            for row in [1, 2, 0] {
                let coordinator = try #require(table.delegate as? NativeArticleList.Coordinator)
                coordinator.parent.onKey("v")
                try await settle(host) { !pageIsClosed() }
                // Decision 0057: the page's ✕ is at the left of the article band, at the top of the window, right of the list.
                func bandButtons(_ view: NSView) -> [NSRect] {
                    ((view as? NSButton).map { [$0.convert($0.bounds, to: nil)] } ?? []) + view.subviews.flatMap { bandButtons($0) }
                }
                try await settle(host) {
                    let listRight = table.convert(table.bounds, to: nil).maxX
                    return bandButtons(host).contains { $0.minY >= window.contentLayoutRect.maxY - ArticleBand.height && $0.minX >= listRight && $0.minX < listRight + 60 }
                }
                // Issue #204: the page starts right below the band's controls, with no dark strip of empty band above it.
                func pageTop() -> CGFloat? {
                    let page: NSView? = find(OriginalReaderWebView.self, in: host) ?? find(OriginalFailureHostingView<AnyView>.self, in: host)
                    return page.map { window.contentLayoutRect.maxY - $0.convert($0.bounds, to: nil).maxY }
                }
                try await settle(host) { (pageTop() ?? 99) < 40 }
                // Decision 0046: the sidebar folds with the page, and the list moves to the window's left edge with the same width.
                try await settle(host, state: state) { !sidebarVisible() && table.convert(table.bounds, to: nil).minX < 1 }
                #expect(abs(table.bounds.width - frame.width) < 1)
                try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))      // let the fold finish, as a person reading the page would
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                try await settle(host) { pageIsClosed() }
                // Closing the page, however it is closed, brings the sidebar back.
                try await settle(host, state: state) { sidebarVisible() && listIsBack() }
            }
        }
        /// Closing the page while the sidebar is still folding (a quick `v` then `Esc`, or a quick `v` then `j`) must still bring the sidebar
        /// back. The fold's end had written the folded state over the close.
        @Test func closingThePageInTheMiddleOfTheFoldStillBringsTheSidebarBack() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
            let entries = (0..<3).map { index in
                ParsedEntry(sourceID: "synthetic-\(index)", title: "合成記事 \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約", body: "合成本文", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
            }
            _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
            let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
                imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")))
            let host = NSHostingView(rootView: reader)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-reader-quick-close")
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await settle(host) { find(NativeArticleList.Table.self, in: host)?.numberOfRows == 3 }
            let table = try #require(find(NativeArticleList.Table.self, in: host))
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(host) { find(ArticleTextView.self, in: host)?.string.contains("合成記事 0") == true }
            let frame = table.convert(table.bounds, to: nil)
            func sidebarVisible() -> Bool {
                guard let sidebar = find(NSOutlineView.self, in: host) else { return false }
                return !sidebar.isHiddenOrHasHiddenAncestor && sidebar.visibleRect.width > 80
            }
            func listIsBack() -> Bool { abs(table.convert(table.bounds, to: nil).minX - frame.minX) < 1 && abs(table.bounds.width - frame.width) < 1 }
            func pageIsClosed() -> Bool { find(OriginalReaderWebView.self, in: host) == nil && find(OriginalFailureHostingView<AnyView>.self, in: host) == nil }
            func state() -> String { "[sidebar \(sidebarVisible()), list x \(table.convert(table.bounds, to: nil).minX), page \(pageIsClosed() ? "closed" : "open")]" }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))      // the window has just appeared
            let coordinator = try #require(table.delegate as? NativeArticleList.Coordinator)
            for row in [1, 2, 0] {
                coordinator.parent.onKey("v")
                try await settle(host) { !pageIsClosed() }
                // At once, without waiting for the fold to end:
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                try await settle(host, state: state) { pageIsClosed() }
                try await settle(host, state: state) { sidebarVisible() && listIsBack() }
                // It must also stay back, not come back for a moment.
                try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
                #expect(sidebarVisible() && listIsBack(), "the sidebar did not stay back \(state())")
            }
        }
    }
}
