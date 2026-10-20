import AppKit
import SwiftUI
@testable import ReaderCore
import Testing
import SwiftData
@testable import UnagiReader

// Checks PRD-04, PRD-05 (specification 7).
@Suite(EnglishLanguage(), .serialized) @MainActor struct NoteReaderTests {
    fileprivate func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
    fileprivate func settle(_ host: NSView, until ready: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if ready() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard ready() else {
            throw NSError(domain: "ReaderUITests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Synthetic reader did not reach the expected state"])
        }
    }

    @Test func aMissingRequiredViewStopsTheTest() async {
        await #expect(throws: (any Error).self) {
            try await settle(NSView()) { false }
        }
    }

    @Test func theWaitLetsQueuedViewUpdatesRun() async throws {
        let host = NSView()
        host.isHidden = true
        Task { @MainActor in host.isHidden = false }
        try await settle(host) { !host.isHidden }
    }

    fileprivate func containsText(_ text: String, in view: NSView) -> Bool {
        if let field = view as? NSTextView, field.string == text { return true }
        return view.subviews.contains { containsText(text, in: $0) }
    }
    fileprivate func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? [] + view.subviews.flatMap { buttons(in: $0) }
    }
    /// Only the two narrow chevrons and the copy button in the inspector, ordered left to right (the ✕ at the left is left out).
    fileprivate func panelButtons(in h: Harness) -> [NSButton] {
        let width = h.window.contentView?.bounds.width ?? 1_240
        let candidates = buttons(in: h.host)
        var positioned: [(button: NSButton, frame: NSRect)] = []
        for button in candidates {
            let frame = button.convert(button.bounds, to: nil)
            guard frame.minX > width - 160, frame.width > 0 else { continue }     // the right end of the note's header
            guard button is NSPopUpButton || frame.width <= 30 else { continue }        // the band's buttons (28 pt hit area)
            positioned.append((button, frame))
        }
        positioned.sort { $0.frame.minX < $1.frame.minX }
        return positioned.map(\.button)
    }
    fileprivate struct Harness {
        let store: ReaderStore
        let host: NSHostingView<ReaderView>
        let window: NSWindow
        let directory: URL
    }
    fileprivate func harness(scope: (ReaderStore) throws -> ReaderWorkspaceScope, noteOpen: Bool = false,
                         pasteboard: NSPasteboard = NSPasteboard(name: .init("unagi-reader-test-\(UUID())")),
                         providedStore: ReaderStore? = nil, prepare: (ReaderStore) throws -> Void) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try providedStore ?? inMemoryReaderStore()
        let entries = (0..<4).map { index in
            ParsedEntry(sourceID: "synthetic-\(index)", title: "合成記事 \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約", body: "合成本文", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
        }
        _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
        try prepare(store)
        let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")),
            initialScope: try scope(store), initialNoteOpen: noteOpen,
            noteEditorLink: NoteEditorLink(), notePasteboard: pasteboard)
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-note-reader")
        window.contentView = host
        return Harness(store: store, host: host, window: window, directory: directory)
    }
    fileprivate func finish(_ harness: Harness) {
        harness.window.close(); try? FileManager.default.removeItem(at: harness.directory)
    }

    @Test func theNoteIsAbsentWhileClosedAndBesideTheListAndTheReaderWhenOpen() async throws {
        let closed = try harness(scope: { _ in .all }) { store in try store.saveNote(text: "既存のノート", at: .now) }
        defer { finish(closed) }
        try await settle(closed.host) { find(NativeArticleList.Table.self, in: closed.host)?.numberOfRows == 4 }
        pumpRunLoop(0.2)
        #expect(!containsText("既存のノート", in: closed.host))                            // no note panel until it is opened
        let open = try harness(scope: { _ in .all }, noteOpen: true) { store in try store.saveNote(text: "既存のノート", at: .now) }
        defer { finish(open) }
        try await settle(open.host) { containsText("既存のノート", in: open.host) }
        let table = try #require(find(NativeArticleList.Table.self, in: open.host))
        #expect(table.numberOfRows == 4)                                                  // the list stays in the middle column
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await settle(open.host) { find(ArticleTextView.self, in: open.host)?.string.contains("合成記事 0") == true }   // the reader shows it beside the note
        #expect(containsText("既存のノート", in: open.host))
    }

    /// Decision 0049: it is the same note on every screen that has an article list, Star included.
    @Test func theSameNoteOpensFromTheStarScreen() async throws {
        let h = try harness(scope: { _ in .starred }, noteOpen: true) { store in try store.saveNote(text: "既存のノート", at: .now) }
        defer { finish(h) }
        try await settle(h.host) { containsText("既存のノート", in: h.host) }
    }

    /// The width the person's saved or default setting asks for must be the width the panel has. The modifier that sets it was on the
    /// inspector itself, where it had no effect: the panel stayed about 270 pt wide (checked in a real 1,240 pt window too).
    @Test func theNotePanelOpensAtItsDefaultWidthNotAtWhateverIsLeft() async throws {
        let h = try harness(scope: { _ in .all }, noteOpen: true) { store in try store.saveNote(text: "既存のノート", at: .now) }
        defer { finish(h) }
        try await settle(h.host) { containsText("既存のノート", in: h.host) }
        pumpRunLoop(0.5)
        func editors(in view: NSView) -> [NSTextView] {
            ((view as? NSTextView).map { [$0] } ?? []).filter { $0.string == "既存のノート" } + view.subviews.flatMap { editors(in: $0) }
        }
        let editor = try #require(editors(in: h.host).first)
        let width = editor.convert(editor.bounds, to: nil).width
        // The window is 1,240 pt wide: the window's limit (the article's 360 pt and the list's 400 pt are kept, with a margin) is narrower than the setting.
        let expected = min(NotePanelWidth.load(), NotePanelWidth.maximum(windowWidth: 1_240))
        #expect(abs(width - expected) < 40, "the editor is \(width) pt wide; the panel should ask for \(expected) pt")
    }
}

/// The note panel beside the article (L1). A suite of its own: see the N4 verification record for why. Run each test alone.
@Suite(EnglishLanguage(), .serialized) @MainActor struct NotePanelTests {
    private let t = NoteReaderTests()

    fileprivate func openHarness() throws -> NoteReaderTests.Harness {
        try t.harness(scope: { _ in .all }, noteOpen: true) { store in try store.saveNote(text: "ノートの本文", at: .now) }
    }
    private func shown(_ h: NoteReaderTests.Harness, _ title: String) -> Bool {
        t.find(ArticleTextView.self, in: h.host)?.string.contains(title) == true
    }
    /// Moves to the next (`j`) or the previous (`k`) article as the chevrons do: both reach `ReaderView.move`. The tests do not click the
    /// chevrons: `NSButton.performClick` runs a nested event loop, and in these hosted tests it can stop the main run loop, which ends the
    /// test process with exit code 0 before the summary line is printed. `scripts/check-test-log.sh` fails CI when that happens.
    private func step(_ h: NoteReaderTests.Harness, _ key: String) throws {
        let table = try #require(t.find(NativeArticleList.Table.self, in: h.host))
        #expect(table.keyHandler?(key) == true)
    }

    @Test func theChevronsMoveBetweenTheNotesArticlesAndStopAtTheEnds() async throws {
        let h = try openHarness()
        defer { t.finish(h) }
        try await t.settle(h.host) { t.containsText("ノートの本文", in: h.host) && t.panelButtons(in: h).count >= 2 }
        let buttons = t.panelButtons(in: h)
        try #require(buttons.count >= 2)
        let (previous, next) = (buttons[0], buttons[1])
        #expect(next.isEnabled)                                                           // nothing shown: next (and previous) open the first
        try step(h, "j")
        try await t.settle(h.host) { shown(h, "合成記事 0") }
        try await t.settle(h.host) { !previous.isEnabled }                               // at the first article
        try step(h, "j")
        try await t.settle(h.host) { shown(h, "合成記事 1") }
        try step(h, "j")
        try await t.settle(h.host) { shown(h, "合成記事 2") }
        try step(h, "j")
        try await t.settle(h.host) { shown(h, "合成記事 3") }
        try await t.settle(h.host) { !next.isEnabled }                                   // at the last article
        try step(h, "k")
        try await t.settle(h.host) { shown(h, "合成記事 2") }
        #expect(t.containsText("ノートの本文", in: h.host))                               // the note stayed
    }

    /// After S1a the panel is a header and the editor: no summary button, no summary card, no action bar (AI on or off).
    @Test func theNotePanelHasNoSummaryButtonAndNoActionBar() async throws {
        let h = try openHarness()
        defer { t.finish(h) }
        try await t.settle(h.host) { t.containsText("ノートの本文", in: h.host) && t.panelButtons(in: h).count >= 2 }
        pumpRunLoop(0.3)
        #expect(t.panelButtons(in: h).count == 3)                                         // two chevrons and one copy button
        #expect(!t.containsText("記事から要約する", in: h.host) && !t.containsText("わかりやすく", in: h.host))
    }

    @Test func theListAndTheChevronsAgreeOnTheShownArticle() async throws {
        let h = try openHarness()
        defer { t.finish(h) }
        try await t.settle(h.host) { t.find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 && t.panelButtons(in: h).count >= 2 }
        let table = try #require(t.find(NativeArticleList.Table.self, in: h.host))
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)       // chosen in the list, not in the panel
        try await t.settle(h.host) { shown(h, "合成記事 2") }
        try step(h, "k")                                                        // previous
        try await t.settle(h.host) { shown(h, "合成記事 1") }
        try await t.settle(h.host) { table.selectedRow == 1 }                            // the list follows
    }
}

@MainActor func pumpRunLoop(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// Decision 0049: the one thing left of the hand-off to another AI is 「Markdownをコピー」, which copies the note's text as it is.
@Suite(EnglishLanguage(), .serialized) @MainActor struct MarkdownCopyTests {
    private let t = NoteReaderTests()

    @Test func theCopyButtonExistsAndAnEmptyNoteCannotBeCopied() async throws {
        let h = try t.harness(scope: { _ in .all }, noteOpen: true) { _ in }
        defer { t.finish(h) }
        try await t.settle(h.host) { t.panelButtons(in: h).count == 3 }                    // two chevrons and the copy button
        #expect(!h.host.rootView.copyNote())
    }

    /// #361: failed edits stay in the editor and must remain available to Copy Markdown.
    @Test(arguments: ["", "Saved"])
    func aFailedSaveCopiesTheVisibleNote(initial: String) async throws {
        let schema = ReaderStore.schema
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        var fail = false
        let store = try ReaderStore(container: ModelContainer(for: schema, configurations: [configuration]), saveHook: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let pasteboard = NSPasteboard(name: .init("unagi-copy-recovery-" + UUID().uuidString))
        let h = try t.harness(scope: { _ in .all }, noteOpen: true, pasteboard: pasteboard, providedStore: store) {
            try $0.saveNote(text: initial, at: .now)
        }
        defer { t.finish(h); pasteboard.releaseGlobally() }
        try await t.settle(h.host) { t.find(NoteTextView.self, in: h.host) != nil && t.panelButtons(in: h).count == 3 }
        let editor = try #require(t.find(NoteTextView.self, in: h.host))
        fail = true
        editor.insertText(" plus unsaved", replacementRange: NSRange(location: (initial as NSString).length, length: 0))
        try #require(editor.string == initial + " plus unsaved")
        #expect(store.note?.text == initial) // The save really failed; copying must not claim that it succeeded.
        try await t.settle(h.host) { t.panelButtons(in: h).last?.isEnabled == true }
        #expect(h.host.rootView.copyNote())
        #expect(pasteboard.string(forType: .string) == initial + " plus unsaved")
        editor.insertText("", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try #require(editor.string.isEmpty && store.note?.text == initial)
        try await t.settle(h.host) { t.panelButtons(in: h).last?.isEnabled == false }
        #expect(!h.host.rootView.copyNote())
        #expect(pasteboard.string(forType: .string) == initial + " plus unsaved") // Even a direct action must not copy the older saved text.
    }

    @Test func aPasteboardWriteFailureIsNotReportedAsSuccess() throws {
        let h = try t.harness(scope: { _ in .all }) {
            try $0.saveNote(text: "Keep this note", at: .now)
        }
        defer { t.finish(h) }
        #expect(!h.host.rootView.copyNote(write: { _ in false }))
        #expect(h.store.note?.text == "Keep this note")
    }

    @Test func theCopyUsesTheExactTextOfTheNote() async throws {
        let note = "# 保存\r\n本文 🐟"
        let pasteboard = NSPasteboard(name: .init("unagi-reader-copy-\(UUID())"))
        let h = try t.harness(scope: { _ in .all }, noteOpen: true, pasteboard: pasteboard) { store in try store.saveNote(text: note, at: .now) }
        defer { t.finish(h) }
        #expect(pasteboard.setString("previous clipboard", forType: .string))
        #expect(h.host.rootView.copyNote())
        #expect(pasteboard.string(forType: .string) == note)
    }
}

/// 「記事をノートに送る」 from the list's key handler, as the app's `c` reaches it (specification 3.3). Checks PRD-19.
@Suite(EnglishLanguage(), .serialized) @MainActor struct SendToNoteTests {
    private let t = NoteReaderTests()

    private func table(_ h: NoteReaderTests.Harness) throws -> NativeArticleList.Table {
        try #require(t.find(NativeArticleList.Table.self, in: h.host))
    }
    private func choose(_ row: Int, in h: NoteReaderTests.Harness) async throws {
        try await t.settle(h.host) { t.find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
        try table(h).selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        try await t.settle(h.host) { t.find(ArticleTextView.self, in: h.host)?.string.contains("合成記事 \(row)") == true }
    }
    private func noteText(_ h: NoteReaderTests.Harness) -> String { h.store.note?.text ?? "" }

    @Test func aClosedNoteOpensAndTakesTheLinkAtItsEnd() async throws {
        let h = try t.harness(scope: { _ in .all }) { store in try store.saveNote(text: "メモ", at: .now) }
        defer { t.finish(h) }
        try await choose(0, in: h)
        h.window.makeFirstResponder(try table(h))
        #expect(try table(h).keyHandler?("c") == true)
        try await t.settle(h.host) { noteText(h) != "メモ" }
        #expect(noteText(h).hasPrefix("メモ\n\n[合成記事 0](") && noteText(h).hasSuffix(")\n"), "note: \(noteText(h).debugDescription)")
        try await t.settle(h.host) { t.containsText(noteText(h), in: h.host) }              // the note panel is open and shows it
        // The keyboard does not go into the note. The list folds away as the note opens, so the article takes it, as with `n`.
        #expect(!(h.window.firstResponder is NoteTextView), "first responder: \(String(describing: h.window.firstResponder))")
    }

    @Test func anOpenNoteTakesOneParagraphEachTime() async throws {
        let h = try t.harness(scope: { _ in .all }, noteOpen: true) { store in try store.saveNote(text: "メモ", at: .now) }
        defer { t.finish(h) }
        try await t.settle(h.host) { t.containsText("メモ", in: h.host) }
        try await choose(1, in: h)
        h.window.makeFirstResponder(try table(h))
        #expect(try table(h).keyHandler?("c") == true)
        try await t.settle(h.host) { noteText(h).contains("[合成記事 1](") }
        #expect(h.window.firstResponder === (try table(h)))                                  // with the note open, the list keeps the keyboard
        try await choose(2, in: h)
        #expect(try table(h).keyHandler?("c") == true)
        try await t.settle(h.host) { noteText(h).contains("[合成記事 2](") }
        let paragraphs = noteText(h).components(separatedBy: "\n\n")
        #expect(paragraphs.count == 3 && paragraphs[0] == "メモ" && paragraphs[1].hasPrefix("[合成記事 1](") && paragraphs[2].hasPrefix("[合成記事 2](")
                && paragraphs[2].hasSuffix(")\n") && !paragraphs[1].contains("\n"),
                "note: \(noteText(h).debugDescription)")
    }

    @Test func withNoArticleChosenNothingHappens() async throws {
        let h = try t.harness(scope: { _ in .all }) { store in try store.saveNote(text: "メモ", at: .now) }
        defer { t.finish(h) }
        try await t.settle(h.host) { t.find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 4 }
        #expect(try table(h).keyHandler?("c") == true)
        pumpRunLoop(0.4)
        #expect(noteText(h) == "メモ")
        #expect(!t.containsText("メモ", in: h.host))                                        // the note did not open
    }

    @Test func theSelectionIsTheArticlesOnlyWhenTheArticleHasTheKeyboard() async throws {
        let h = try t.harness(scope: { _ in .all }) { _ in }
        defer { t.finish(h) }
        try await choose(0, in: h)
        let article = try #require(t.find(ArticleTextView.self, in: h.host))
        let range = (article.string as NSString).range(of: "合成本文")
        try #require(range.location != NSNotFound)
        h.window.makeFirstResponder(article)
        article.setSelectedRange(range)
        #expect(ArticleTextView.selectedText(in: h.window) == "合成本文")
        article.setSelectedRange(NSRange(location: range.location, length: 0))
        #expect(ArticleTextView.selectedText(in: h.window) == nil)                         // a caret is not a selection
        article.setSelectedRange(range)
        h.window.makeFirstResponder(try table(h))
        #expect(ArticleTextView.selectedText(in: h.window) == nil)                         // the list has the keyboard
    }
}
