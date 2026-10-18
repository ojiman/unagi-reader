import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

// Checks PRD-17 (specification 7).
/// Specification 3.1.4: the filter narrows the list of the scope; `j` / `k` walk the filtered list; the field is the system's search field.
@Suite(EnglishLanguage(), .serialized) @MainActor struct ListFilterTests {
    private struct Harness {
        let host: NSHostingView<ReaderView>
        let window: NSWindow
        let directory: URL
    }
    private func harness(filter: String) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try inMemoryReaderStore()
        let titles = ["Swift の話 A", "別の記事", "swift の話 B", "その他"]
        let entries = titles.enumerated().map { index, title in
            ParsedEntry(sourceID: "synthetic-\(index)", title: title, url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約",
                        body: "Swift は本文にだけある", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
        }
        _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
        let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")), initialListFilter: filter)
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-list-filter")
        window.contentView = host
        window.orderFront(nil)
        return Harness(host: host, window: window, directory: directory)
    }
    private func finish(_ h: Harness) { h.window.close(); try? FileManager.default.removeItem(at: h.directory) }
    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
    private func settle(_ h: Harness, line: Int = #line, until ready: () -> Bool) async throws {
        for _ in 0..<250 {
            h.host.layoutSubtreeIfNeeded()
            if ready() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(ready(), sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1))
    }
    private func shown(_ h: Harness) -> String { find(ArticleTextView.self, in: h.host)?.string ?? "" }

    @Test func theFilterNarrowsTheListToTitlesThatContainTheText() async throws {
        let h = try harness(filter: "SWIFT")
        defer { finish(h) }
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 2 }    // the body is not searched
    }

    @Test func anEmptyFilterShowsTheWholeList() async throws {
        let h = try harness(filter: "  ")
        defer { finish(h) }
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
    }

    @Test func jAndKWalkTheFilteredList() async throws {
        let h = try harness(filter: "swift")
        defer { finish(h) }
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 2 }
        let table = try #require(find(NativeArticleList.Table.self, in: h.host))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await settle(h) { shown(h).contains("Swift の話 A") }
        #expect(table.keyHandler?("j") == true)
        try await settle(h) { shown(h).contains("swift の話 B") }                                 // 「別の記事」 is skipped
        #expect(table.keyHandler?("j") == true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(shown(h).contains("swift の話 B") && table.selectedRow == 1)                     // the end of the filtered list
    }

    /// The field is the system's search field, inside the list column, and it is there while it has text.
    @Test func theFieldIsTheSystemSearchFieldOverTheList() async throws {
        let h = try harness(filter: "swift")
        defer { finish(h) }
        try await settle(h) { find(NSSearchField.self, in: h.host) != nil && find(NativeArticleList.Table.self, in: h.host) != nil }
        let field = try #require(find(NSSearchField.self, in: h.host)), table = try #require(find(NativeArticleList.Table.self, in: h.host))
        let fieldFrame = field.convert(field.bounds, to: nil), list = table.convert(table.bounds, to: nil)
        #expect(fieldFrame.minX >= list.minX && fieldFrame.maxX <= list.maxX)
        #expect(fieldFrame.minY >= 800 - ArticleBand.height)                                       // in the list's band (decision 0057)
        #expect(field.stringValue == "swift")
    }

    /// The field's ✕ clears it through the field's action, not a text change: the whole list comes back (seen in a synthetic run).
    @Test func clearingTheFieldWithItsCrossRestoresTheList() async throws {
        let h = try harness(filter: "swift")
        defer { finish(h) }
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 2 }
        #expect(try #require(find(NativeArticleList.Table.self, in: h.host)).keyHandler?("/") == true)
        try await settle(h) { find(NSSearchField.self, in: h.host) != nil }
        let field = try #require(find(NSSearchField.self, in: h.host))
        field.stringValue = ""                                                                   // what the ✕ does, then it sends the action
        #expect(field.sendAction(field.action, to: field.target))
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
    }

    /// The owner's rule (3.1.4): a field with text stays open when the keyboard goes elsewhere, and the list stays narrowed.
    @Test func aFieldWithTextStaysOpenWhenTheKeyboardGoesElsewhere() async throws {
        let h = try harness(filter: "")
        defer { finish(h) }
        h.window.makeKeyAndOrderFront(nil)
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
        let table = try #require(find(NativeArticleList.Table.self, in: h.host))
        #expect(table.keyHandler?("/") == true)
        try await settle(h) { find(NSSearchField.self, in: h.host)?.currentEditor() != nil }
        let field = try #require(find(NSSearchField.self, in: h.host))
        field.stringValue = "swift"
        #expect(field.sendAction(field.action, to: field.target))
        try await settle(h) { table.numberOfRows == 2 }
        h.window.makeFirstResponder(table)                                                       // a click elsewhere
        try await Task.sleep(for: .milliseconds(400))
        #expect(find(NSSearchField.self, in: h.host) != nil && table.numberOfRows == 2)
    }

    /// Specification 3.1.4: an empty field that loses the keyboard turns back into the magnifier.
    @Test func anEmptyFieldLeftAloneTurnsBackIntoTheMagnifier() async throws {
        let h = try harness(filter: "")
        defer { finish(h) }
        h.window.makeKeyAndOrderFront(nil)
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
        let table = try #require(find(NativeArticleList.Table.self, in: h.host))
        #expect(find(NSSearchField.self, in: h.host) == nil)                                      // only the magnifier
        #expect(table.keyHandler?("/") == true)
        try await settle(h) { find(NSSearchField.self, in: h.host)?.currentEditor() != nil }
        h.window.makeFirstResponder(table)                                                       // the keyboard goes elsewhere
        try await settle(h) { find(NSSearchField.self, in: h.host) == nil }
    }

    /// While Japanese text is being composed in the field, the list does not change; it follows when the composition is committed.
    @Test func composingInTheFieldDoesNotChangeTheList() async throws {
        let h = try harness(filter: "")
        defer { finish(h) }
        h.window.makeKeyAndOrderFront(nil)
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
        let table = try #require(find(NativeArticleList.Table.self, in: h.host))
        #expect(table.keyHandler?("/") == true)
        try await settle(h) { find(NSSearchField.self, in: h.host)?.currentEditor() != nil }
        let field = try #require(find(NSSearchField.self, in: h.host))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("その", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 0))
        editor.didChangeText()                                                                    // as an input method's edit does
        try await Task.sleep(for: .milliseconds(300))
        #expect(table.numberOfRows == 4)                                                         // composing: the list stays
        editor.insertText("その", replacementRange: NSRange(location: 0, length: 2))                // committed
        try await settle(h) { table.numberOfRows == 1 }
    }
}
