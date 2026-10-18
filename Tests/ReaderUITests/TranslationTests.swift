import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

/// A fake engine: every text comes back as "訳:" and the text. The system's session cannot run in tests (no language packs in CI).
@MainActor private func fakeEngine(decision: LanguageDecision.Outcome = .translate(source: "en"),
                                   gate: AsyncStream<Void>? = nil) -> TranslationEngine {
    TranslationEngine(decide: { _, _ in decision }, batch: { items in
        AsyncThrowingStream { continuation in
            Task {
                if let gate { for await _ in gate { break } }
                for item in items { continuation.yield(TranslationResponse(index: item.index, text: "訳:" + item.text)) }
                continuation.finish()
            }
        }
    }, languages: { ["en", "ja"] })
}

// Checks PRD-18 (specification 7).
/// Specification 3.6: a press translates the open article in place, a second press shows the original, another article shows its
/// original, and nothing is translated that the person did not ask for.
@Suite(EnglishLanguage(), .serialized) @MainActor struct TranslationTests {
    private struct Harness {
        let host: NSHostingView<ReaderView>
        let window: NSWindow
        let directory: URL
    }
    private func harness(engine: TranslationEngine) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try inMemoryReaderStore()
        let entries = (0..<2).map { index in
            ParsedEntry(sourceID: "synthetic-\(index)", title: "Synthetic story \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"),
                        summary: "A synthetic summary.", body: "First paragraph \(index).\n\nSecond paragraph \(index).", coverage: .feedProvided,
                        publishedAt: .now.addingTimeInterval(Double(-index)))
        }
        _ = try store.importFeed(ParsedFeed(title: "Synthetic feed", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
        let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")), translationEngine: engine)
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-translation")
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
        #expect(ready(), "shown: \(shown(h).prefix(200))", sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1))
    }
    private func shown(_ h: Harness) -> String { find(ArticleTextView.self, in: h.host)?.string ?? "" }
    private func open(_ row: Int, in h: Harness) async throws -> NativeArticleList.Table {
        try await settle(h) { find(NativeArticleList.Table.self, in: h.host)?.numberOfRows == 2 }
        let table = try #require(find(NativeArticleList.Table.self, in: h.host))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        try await settle(h) { shown(h).contains("Second paragraph \(row)") }
        return table
    }

    @Test func tTranslatesTheArticleInPlaceAndAgainShowsTheOriginal() async throws {
        let h = try harness(engine: fakeEngine())
        defer { finish(h) }
        let table = try await open(0, in: h)
        #expect(table.keyHandler?("t") == true)
        try await settle(h) { shown(h).contains("訳:Synthetic story 0") && shown(h).contains("訳:Second paragraph 0.") }
        #expect(table.keyHandler?("t") == true)
        try await settle(h) { shown(h).contains("Synthetic story 0") && !shown(h).contains("訳:") }
    }

    @Test func anotherArticleOpensInItsOriginalLanguage() async throws {
        let h = try harness(engine: fakeEngine())
        defer { finish(h) }
        let table = try await open(0, in: h)
        #expect(table.keyHandler?("t") == true)
        try await settle(h) { shown(h).contains("訳:Synthetic story 0") }
        #expect(table.keyHandler?("j") == true)
        try await settle(h) { shown(h).contains("Synthetic story 1") }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!shown(h).contains("訳:"))                                                      // not sticky
    }

    @Test func movingAwayWhileTranslatingDropsTheLateAnswers() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let h = try harness(engine: fakeEngine(gate: gate.stream))
        defer { finish(h) }
        let table = try await open(0, in: h)
        #expect(table.keyHandler?("t") == true)
        #expect(table.keyHandler?("j") == true)
        try await settle(h) { shown(h).contains("Synthetic story 1") }
        gate.continuation.finish()                                                             // the old answers arrive now
        try await Task.sleep(for: .milliseconds(300))
        #expect(!shown(h).contains("訳:"))
    }

    /// Issue #315: `n` gives the keyboard to the note's editor (decision 0064), and a `t` typed at once is written in the note. It must not
    /// translate the article: the window's `t` decided from a state taken while the list still had the keyboard. A real key event goes
    /// through the application, as a key typed by the person does.
    @Test func aTTypedInTheNoteRightAfterOpeningItIsWrittenNotTranslated() async throws {
        let h = try harness(engine: fakeEngine())
        defer { finish(h) }
        h.window.makeKeyAndOrderFront(nil)
        let table = try await open(0, in: h)
        h.window.makeFirstResponder(table)
        #expect(table.keyHandler?("n") == true)
        try await settle(h) { h.window.firstResponder is NoteTextView }
        let note = try #require(h.window.firstResponder as? NoteTextView)
        let before = note.string
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: h.window.windowNumber, context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        NSApp.sendEvent(event)
        try await Task.sleep(for: .milliseconds(300))
        #expect(note.string == before + "t")
        #expect(!shown(h).contains("訳:"))
        // The same after a click: the list takes the keyboard, then the editor at once (as the click of #315 did), and `t` is typed.
        h.window.makeFirstResponder(table)
        try await Task.sleep(for: .milliseconds(100))
        h.window.makeFirstResponder(note)
        NSApp.sendEvent(event)
        try await Task.sleep(for: .milliseconds(300))
        #expect(note.string == before + "tt")
        #expect(!shown(h).contains("訳:"))
    }

    /// The article's text is read-only: with the keyboard in it, `t` still translates (the check of #315 is only for typing).
    @Test func aTWithTheKeyboardInTheArticleTranslates() async throws {
        let h = try harness(engine: fakeEngine())
        defer { finish(h) }
        h.window.makeKeyAndOrderFront(nil)
        _ = try await open(0, in: h)
        let article = try #require(find(ArticleTextView.self, in: h.host))
        h.window.makeFirstResponder(article)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: h.window.windowNumber, context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        NSApp.sendEvent(event)
        try await settle(h) { shown(h).contains("訳:Synthetic story 0") }
    }

    @Test func anArticleAlreadyInTheTargetLanguageIsLeftAsItIs() async throws {
        let h = try harness(engine: fakeEngine(decision: .alreadyInTarget))
        defer { finish(h) }
        let table = try await open(0, in: h)
        #expect(table.keyHandler?("t") == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!shown(h).contains("訳:"))
    }
}

/// The controller's own rules, without a window.
@Suite(EnglishLanguage()) @MainActor struct TranslationControllerTests {
    private let content = ArticleContent(articleID: UUID(), text: "One.\n\nTwo.", summary: "", coverage: .feedProvided, originalURL: nil)

    @Test func aPressTranslatesAndASecondPressShowsTheOriginal() async throws {
        let controller = TranslationController(engine: fakeEngine())
        controller.setTarget("ja", supported: ["en", "ja"])
        controller.toggle(title: "Title", content: content)
        #expect(controller.isOn(for: content.articleID))                                      // on at once, while the language is decided
        for _ in 0..<100 where controller.state.state != .done(failed: 0, source: "en") { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.shown(for: content.articleID)?.title == "訳:Title")
        #expect(controller.shown(for: content.articleID)?.paragraphs.map(\.text) == ["訳:One.", "訳:Two."])
        controller.toggle(title: "Title", content: content)
        #expect(!controller.isOn(for: content.articleID) && controller.state.state == .idle)
    }

    @Test func theStatusRowNamesTheLanguagesInJapanese() {
        #expect(TranslationStatusRow.pair(source: "en", target: "ja") == "English → Japanese")
        #expect(TranslationStatusRow.pair(source: nil, target: "ja") == "→ Japanese")
    }
}

// Checks PRD-18: the chosen target, not the UI language, controls translation.
@Suite(EnglishLanguage()) @MainActor struct TranslationTargetControllerTests {
    private let content = ArticleContent(articleID: UUID(), text: "One. Two.", summary: "", coverage: .feedProvided, originalURL: nil)
    @Test func changingTargetReturnsToOriginalWithoutStartingAnotherTranslation() async throws {
        let controller = TranslationController(engine: fakeEngine())
        controller.setTarget("ja", supported: ["ja", "en"])
        controller.toggle(title: "Title", content: content)
        for _ in 0..<100 where controller.state.shown == nil || controller.state.state != .done(failed: 0, source: "en") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.state.shown != nil)
        controller.setTarget("en", supported: ["ja", "en"])
        #expect(controller.target == "en")
        #expect(controller.state.shown == nil && controller.state.state == .idle)
        #expect(!controller.isOn(for: content.articleID))
    }
    @Test func changingTargetDropsLateBatchAnswers() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let controller = TranslationController(engine: fakeEngine(gate: gate.stream))
        controller.setTarget("ja", supported: ["ja", "en"])
        controller.toggle(title: "Title", content: content)
        for _ in 0..<100 where controller.state.key == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.state.key?.target == "ja")
        controller.setTarget("en", supported: ["ja", "en"])
        gate.continuation.finish()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.state.shown == nil && controller.state.state == .idle)
    }
    @Test func removedManualTargetShowsUnsupportedWithoutTranslating() {
        let controller = TranslationController(engine: fakeEngine())
        controller.setTarget("ko", supported: ["ja", "en"])
        controller.toggle(title: "Title", content: content)
        #expect(controller.target == "ko")
        #expect(controller.state.state == .unsupported)
        #expect(controller.state.shown == nil)
    }
}

@Suite(EnglishLanguage()) @MainActor struct TranslationDetectionCancellationTests {
    @Test func aTargetChangeDiscardsTheOldLanguageDecision() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let engine = TranslationEngine(decide: { _, _ in
            for await _ in gate.stream { break }
            return .translate(source: "en")
        }, batch: nil)
        let controller = TranslationController(engine: engine)
        let content = ArticleContent(articleID: UUID(), text: "Synthetic.", summary: "", coverage: .feedProvided, originalURL: nil)
        controller.setTarget("ja", supported: ["ja", "en"])
        controller.toggle(title: "Title", content: content)
        #expect(controller.isOn(for: content.articleID))
        controller.setTarget("en", supported: ["ja", "en"])
        gate.continuation.finish()
        try await Task.sleep(for: .milliseconds(20))
        #expect(controller.state.state == .idle && controller.configuration == nil)
        #expect(!controller.isOn(for: content.articleID))
    }
}

@Suite(EnglishLanguage()) @MainActor struct TranslationAvailabilityTests {
    @Test func aPressBeforeTheSavedTargetIsResolvedCannotUsePlaceholderEnglish() async throws {
        let controller = TranslationController(engine: fakeEngine())
        let content = ArticleContent(articleID: UUID(), text: "Synthetic.", summary: "", coverage: .feedProvided, originalURL: nil)
        controller.toggle(title: "Title", content: content)
        #expect(!controller.isOn(for: content.articleID))
        #expect(controller.state.state == .idle)
        controller.setTarget("ja", supported: ["en", "ja"])
        controller.toggle(title: "Title", content: content)
        for _ in 0..<100 where controller.state.state != .done(failed: 0, source: "en") { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.state.key?.target == "ja")
        #expect(controller.state.shown?.title == "訳:Title")
    }
}
