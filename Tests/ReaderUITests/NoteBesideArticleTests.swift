import AppKit
import SwiftUI
import SwiftData
@testable import ReaderCore
import Testing
@testable import UnagiReader

/// Decision 0049: the note opens beside the article. Opening it folds the sidebar and the list away to the left and the note comes in
/// from the right (article on the left, note on the right); closing it brings everything back. The tests look at where the views are
/// in a hosted window.
extension SplitViewFoldTests {
    // Checks PRD-04 (specification 7).
    @Suite(EnglishLanguage(), .serialized) @MainActor struct NoteBesideArticleTests {
        private let noteText = "既存のノート"

        private struct Harness {
            let store: ReaderStore
            let host: NSHostingView<ReaderView>
            let window: NSWindow
            let directory: URL
        }
        private func harness(noteOpen: Bool = false, listShown: Bool = false) throws -> Harness {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try inMemoryReaderStore()
            let entries = (0..<3).map { index in
                ParsedEntry(sourceID: "synthetic-\(index)", title: "合成記事 \(index)", url: URL(string: "http://127.0.0.1:1/article/\(index)"), summary: "合成要約", body: "合成本文", coverage: .feedProvided, publishedAt: .now.addingTimeInterval(Double(-index)))
            }
            _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
            try store.saveNote(text: noteText, at: .now)
            let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
                imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")),
                initialNoteOpen: noteOpen, initialListShown: listShown,
                notePasteboard: NSPasteboard(name: .init("unagi-reader-test-\(UUID())")))
            let host = NSHostingView(rootView: reader)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-note-beside")
            window.contentView = host
            window.orderFront(nil)
            return Harness(store: store, host: host, window: window, directory: directory)
        }
        private func finish(_ h: Harness) { h.window.close(); try? FileManager.default.removeItem(at: h.directory) }

        private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }
        private func editor(in h: Harness) -> NSTextView? {
            func search(_ view: NSView) -> NSTextView? {
                if let text = view as? NSTextView, text.string == noteText { return text }
                return view.subviews.lazy.compactMap { search($0) }.first
            }
            return search(h.host)
        }
        /// The closed note stays in the view tree, outside the window on the right.
        private func noteVisible(_ h: Harness) -> Bool { (x(editor(in: h)) ?? 99_999) < 1_240 - 50 }
        private func table(in h: Harness) -> NativeArticleList.Table? { find(NativeArticleList.Table.self, in: h.host) }
        private func article(in h: Harness) -> ArticleTextView? { find(ArticleTextView.self, in: h.host) }
        private func x(_ view: NSView?) -> CGFloat? { view.map { $0.convert($0.bounds, to: nil).minX } }
        private func right(_ view: NSView?) -> CGFloat? { view.map { $0.convert($0.bounds, to: nil).maxX } }
        private func sidebarButtonsMounted(_ h: Harness) -> Bool {
            h.window.titlebarAccessoryViewControllers.contains { $0.view is NSHostingView<SidebarTitlebarControls.Buttons> }
        }
        private func state(_ h: Harness) -> String {
            "[sidebar buttons \(sidebarButtonsMounted(h)), list x \(x(table(in: h)).map { "\($0)" } ?? "none"), article x \(x(article(in: h)).map { "\($0)" } ?? "none"), note x \(x(editor(in: h)).map { "\($0)" } ?? "none")]"
        }
        private func settle(_ h: Harness, line: Int = #line, until ready: () -> Bool) async throws {
            for _ in 0..<250 {
                h.host.layoutSubtreeIfNeeded()
                if ready() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(ready(), "did not reach the expected state \(state(h))", sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: line, column: 1))
        }
        private func press(_ key: String, in h: Harness) throws {
            let list = try #require(table(in: h))
            #expect(list.keyHandler?(key) == true)
        }

        @Test func theHostedEditorCanSaveAQueuedEditAfterHarnessCleanup() async throws {
            let h = try harness(noteOpen: true)
            defer { finish(h) }
            try await settle(h) { editor(in: h) != nil }
            let view = try #require(editor(in: h))
            // Deliver a queued edit through the retained hosted editor after its scratch directory is gone.
            let edit = Task {
                view.insertText("Queued synthetic note", replacementRange: NSRange(location: 0, length: (view.string as NSString).length))
            }
            finish(h)
            await edit.value
            #expect(view.string == "Queued synthetic note")
            let context = ModelContext(h.store.context.container)
            #expect(try context.fetch(FetchDescriptor<Note>()).first?.text == "Queued synthetic note")
        }

        @Test func nOpensTheNoteBesideTheArticleAndFoldsTheSidebarAndTheList() async throws {
            let h = try harness()
            defer { finish(h) }
            try await settle(h) { table(in: h)?.numberOfRows == 3 && sidebarButtonsMounted(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            try await settle(h) { article(in: h)?.string.contains("合成記事 1") == true }
            let listX = try #require(x(list)), listWidth = list.bounds.width
            #expect(!noteVisible(h))                                                            // the note is not there until it is opened
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))                 // the window has just appeared

            try press("n", in: h)
            try await settle(h) { noteVisible(h) && !sidebarButtonsMounted(h) && (x(article(in: h)) ?? 999) < 40 }
            // Article on the left, note on the right; the list is folded away, so it takes no room.
            let articleRight = try #require(right(article(in: h)))
            #expect(try #require(x(editor(in: h))) >= articleRight - 1)
            #expect(article(in: h)?.string.contains("合成記事 1") == true)                       // the same article
            try await settle(h) { (list.window == nil) || list.convert(list.bounds, to: nil).width < 1 || list.isHiddenOrHasHiddenAncestor }

            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))                 // let the move finish, as a person would wait
            try press("n", in: h)
            // macOS 27 (the support floor) puts the list back exactly. CI's macOS 26.6 (the build floor only) keeps the sidebar narrower
            // after the 640 pt note leaves a 1,240 pt window (seen twice on PR #190: the list at x 193); there it checks the list is back.
            // In a window narrower than 1,400 pt the list returns at once (#222), while the note is still leaving: the sidebar then comes back
            // at its smallest width, as on macOS 26.6, and the list is checked to be back.
            let exact = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                && SidebarFold.animatesListFold(windowWidth: 1_240)
            try await settle(h) {
                !noteVisible(h) && sidebarButtonsMounted(h) && (exact ? abs((x(list) ?? 0) - listX) < 1 && abs(list.bounds.width - listWidth) < 1
                                                                      : (x(list) ?? 0) > 150 && list.bounds.width > 200)
            }
            #expect(list.selectedRow == 1)                                                      // the selection did not change
            #expect(article(in: h)?.string.contains("合成記事 1") == true)
        }

        /// Specification 3.5 (Width): a wide saved note width gives way in a narrow window; the article keeps 360 pt and nothing leaves the
        /// window (issue: the note at 1,100 pt in a 1,240 pt window pushed the article out to the left).
        @Test func aWideSavedNoteLeavesTheArticleItsWidthInANarrowWindow() async throws {
            let saved = UserDefaults.standard.object(forKey: NotePanelWidth.key)
            UserDefaults.standard.set(1_100.0, forKey: NotePanelWidth.key)
            defer { if let saved { UserDefaults.standard.set(saved, forKey: NotePanelWidth.key) } else { UserDefaults.standard.removeObject(forKey: NotePanelWidth.key) } }
            let h = try harness()
            defer { finish(h) }
            try await settle(h) { table(in: h)?.numberOfRows == 3 && sidebarButtonsMounted(h) }
            try #require(table(in: h)).selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            try await settle(h) { article(in: h)?.string.contains("合成記事 1") == true }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            try press("n", in: h)
            try await settle(h) { noteVisible(h) && !sidebarButtonsMounted(h) }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            h.host.layoutSubtreeIfNeeded()
            let articleView = try #require(article(in: h)), noteView = try #require(editor(in: h))
            #expect(try #require(x(articleView)) >= -1, "\(state(h))")                          // not pushed out to the left
            #expect(try #require(x(noteView)) >= NotePanelWidth.articleMinimum - 1, "\(state(h))")        // the article column keeps its width
            #expect(try #require(right(noteView)) <= 1_241, "\(state(h))")                       // nothing is outside the window on the right
        }

        /// The same in the three-column layout (the list is shown beside the note): the list keeps its 280 pt too.
        @Test func aWideSavedNoteLeavesTheListAndTheArticleTheirWidthsInThreeColumns() async throws {
            let saved = UserDefaults.standard.object(forKey: NotePanelWidth.key)
            UserDefaults.standard.set(1_100.0, forKey: NotePanelWidth.key)
            defer { if let saved { UserDefaults.standard.set(saved, forKey: NotePanelWidth.key) } else { UserDefaults.standard.removeObject(forKey: NotePanelWidth.key) } }
            let h = try harness(noteOpen: true, listShown: true)
            defer { finish(h) }
            try await settle(h) { table(in: h)?.numberOfRows == 3 && noteVisible(h) }
            try #require(table(in: h)).selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            try await settle(h) { article(in: h)?.string.contains("合成記事 1") == true }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            h.host.layoutSubtreeIfNeeded()
            let list = try #require(table(in: h)), noteView = try #require(editor(in: h))
            #expect(try #require(x(list)) >= -1, "\(state(h))")                                   // not pushed out to the left
            #expect(list.bounds.width >= NotePanelWidth.listMinimum - 20, "list \(list.bounds.width) \(state(h))")   // (the table has its own insets)
            // The article column between the list and the note keeps its 360 pt.
            let listRight = try #require(right(list))
            #expect(try #require(x(noteView)) - listRight >= NotePanelWidth.articleMinimum - 1, "list right \(listRight), \(state(h))")
            #expect(try #require(right(noteView)) <= 1_241, "\(state(h))")
        }

        /// Decision 0064 (issue #313): `n`, the note button and `⌥⌘I` open the note with the keyboard in its editor, the caret at the end
        /// of a note the person has not placed it in, so they can write at once. Closing the note again (here as `⌥⌘I` or the note button
        /// do, which reach the same action as this `n`) gives the keyboard back to the list. `c` keeps it where it was (`SendToNoteTests`).
        @Test func openingTheNoteGivesTheKeyboardToTheEditor() async throws {
            let h = try harness()
            defer { finish(h) }
            h.window.makeKeyAndOrderFront(nil)
            try await settle(h) { table(in: h)?.numberOfRows == 3 }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            h.window.makeFirstResponder(list)
            try await settle(h) { article(in: h)?.string.contains("合成記事 0") == true }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            try press("n", in: h)
            try await settle(h) { noteVisible(h) && !sidebarButtonsMounted(h) && h.window.firstResponder === editor(in: h) }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            let note = try #require(editor(in: h))
            #expect(h.window.firstResponder === note)                                       // the end of the fold does not take it away
            #expect(note.selectedRange() == NSRange(location: (noteText as NSString).length, length: 0))
            try press("n", in: h)
            try await settle(h) { !noteVisible(h) && sidebarButtonsMounted(h) && h.window.firstResponder === list }
        }

        /// Decision 0050 point 3: the ✕ sits at the top left of the note, as the original page's ✕ sits at the top left of the page. Pressing
        /// it is not tested here: its SwiftUI button has no target to send to, and `performClick` can end a hosted run (AGENTS.md). It calls
        /// the same `toggleNote` as `n`, which the tests above check.
        @Test func theNoteHasACrossAtItsTopLeft() async throws {
            let h = try harness(noteOpen: true)
            defer { finish(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(h) { noteVisible(h) && (x(article(in: h)) ?? 999) < 40 }
            func buttons(_ view: NSView) -> [NSButton] { ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap { buttons($0) } }
            let noteLeft = try #require(x(editor(in: h)))
            try await settle(h) {
                buttons(h.host).contains { let frame = $0.convert($0.bounds, to: nil); return abs(frame.minX - noteLeft) < 24 && frame.minY > 700 }
            }
        }

        private func escape(to view: NSView, in h: Harness) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: h.window.windowNumber,
                                                      context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            view.keyDown(with: event)
        }
        /// The window with the note open and the keyboard in its editor (decision 0064): article 1 is shown.
        private func openNote(_ h: Harness) async throws -> NativeArticleList.Table {
            h.window.makeKeyAndOrderFront(nil)
            try await settle(h) { table(in: h)?.numberOfRows == 3 && sidebarButtonsMounted(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            h.window.makeFirstResponder(list)
            try await settle(h) { article(in: h)?.string.contains("合成記事 1") == true }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            try press("n", in: h)
            try await settle(h) { noteVisible(h) && !sidebarButtonsMounted(h) }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            return list
        }

        /// Decision 0050 point 2: `Esc` closes the note, from the article or from the note's editor, and shows the same article with
        /// the list selection on it.
        @Test func escapeFromTheArticleClosesTheNote() async throws {
            let h = try harness()
            defer { finish(h) }
            let list = try await openNote(h)
            let reader = try #require(article(in: h))
            h.window.makeFirstResponder(reader)
            try escape(to: reader, in: h)
            try await settle(h) { !noteVisible(h) && sidebarButtonsMounted(h) && h.window.firstResponder === list }
            #expect(list.selectedRow == 1 && article(in: h)?.string.contains("合成記事 1") == true)
        }

        @Test func escapeFromTheEditorClosesTheNoteButNotWhileComposing() async throws {
            let h = try harness()
            defer { finish(h) }
            let list = try await openNote(h)
            let note = try #require(editor(in: h))
            h.window.makeFirstResponder(note)
            note.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: note.string.count, length: 0))
            func shown() -> Bool { (x(note) ?? 99_999) < 1_240 - 50 }                         // the composed text changes what `editor(in:)` finds
            try escape(to: note, in: h)
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            #expect(shown())                                                                  // composing: the note stays
            note.unmarkText()
            try escape(to: note, in: h)
            try await settle(h) { !shown() && sidebarButtonsMounted(h) && h.window.firstResponder === list }
            #expect(list.selectedRow == 1)
        }

        /// Specification 3.1.3, issue #312: with the original page and the note open, `Esc` in the note closes the note and gives the
        /// keyboard to the page, so that a second `Esc` reaches the page's own `Esc`, which closes it (`OriginalKeyboardTests`). The
        /// synthetic page cannot load; locally it soon shows its failure pane, on CI it may still be loading, so either may have the keyboard.
        @Test func escapeInTheNoteGivesTheKeyboardToTheOriginalPage() async throws {
            let h = try harness()
            defer { finish(h) }
            let list = try await openNote(h)
            try press("v", in: h)
            func pageShown() -> Bool { ReaderKeyboardCommands.originalPage(in: h.host) != nil }
            try await settle(h) { pageShown() }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            let note = try #require(editor(in: h))
            h.window.makeFirstResponder(note)
            try escape(to: note, in: h)
            try await settle(h) { !noteVisible(h) && ReaderKeyboardCommands.isInOriginalPage(h.window.firstResponder) }
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            // The list comes back beside the page and does not take the keyboard from it.
            #expect(pageShown() && ReaderKeyboardCommands.isInOriginalPage(h.window.firstResponder) && h.window.firstResponder !== list)
        }

        /// Decision 0050 point 1: with the note open, `j` / `k` move the article and the note stays open.
        @Test func jAndKMoveTheArticleWithTheNoteOpen() async throws {
            let h = try harness()
            defer { finish(h) }
            let list = try await openNote(h)
            try press("j", in: h)
            try await settle(h) { article(in: h)?.string.contains("合成記事 2") == true }
            try press("k", in: h)
            try await settle(h) { article(in: h)?.string.contains("合成記事 1") == true }
            #expect(noteVisible(h) && list.selectedRow == 1)
        }

        @Test func theLayoutButtonShowsTheListBesideTheArticleAndTheNote() async throws {
            let h = try harness(noteOpen: true, listShown: true)
            defer { finish(h) }
            try await settle(h) { table(in: h)?.numberOfRows == 3 && noteVisible(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(h) { article(in: h)?.string.contains("合成記事 0") == true }
            // List, article and note, from the left; the sidebar is folded.
            try await settle(h) { !sidebarButtonsMounted(h) && (x(list) ?? 999) < 1 }
            try await settle(h) { (x(article(in: h)) ?? 0) >= (right(list) ?? 99_999) - 1 }
            try await settle(h) { (x(editor(in: h)) ?? 0) >= (right(article(in: h)) ?? 99_999) - 1 }
        }

        /// Issue #195: the window can restore a folded list column (saved while the note was open, then the app ended without quitting).
        /// The note starts closed, so the list must come back by itself.
        @Test func aListFoldedByTheSystemComesBackWhileTheNoteIsClosed() async throws {
            let h = try harness()
            defer { finish(h) }
            try await settle(h) { table(in: h)?.numberOfRows == 3 && sidebarButtonsMounted(h) }
            let list = try #require(table(in: h))
            try await Task.sleep(for: .seconds(SidebarFold.motionDuration * 2))
            var view: NSView? = list.superview
            var item: NSSplitViewItem?
            while let current = view, item == nil {
                if let split = current as? NSSplitView, let controller = split.delegate as? NSSplitViewController {
                    item = controller.splitViewItems.first { list.isDescendant(of: $0.viewController.view) }
                }
                view = current.superview
            }
            let column = try #require(item)
            column.canCollapse = true
            column.isCollapsed = true                                                          // what a restored window state does
            // Back and usable: the width it had before the system folded it is not known, so it comes back at least at its smallest width.
            try await settle(h) { !column.isCollapsed && list.bounds.width >= 280 - 1 && (x(list) ?? 0) > 100 }
        }

        /// Decision 0057: the note's controls (✕, layout, previous, next, copy) sit in the note's own band at the top of the window.
        @Test func theNoteControlsSitInTheNoteBand() async throws {
            let h = try harness(noteOpen: true)
            defer { finish(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(h) { noteVisible(h) && (x(article(in: h)) ?? 999) < 40 }
            func buttons(_ view: NSView) -> [NSButton] { ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap { buttons($0) } }
            let noteLeft = try #require(x(editor(in: h)))
            // Kept in small steps: the CI compiler (Swift 6.3.3) gave up on one long expression here.
            func bandFrames() -> [NSRect] {
                let frames: [NSRect] = buttons(h.host).map { $0.convert($0.bounds, to: nil) }
                let bandBottom: CGFloat = 800 - ArticleBand.height
                return frames.filter { $0.minY >= bandBottom && $0.width >= 20 }
            }
            try await settle(h) { bandFrames().filter { $0.minX >= noteLeft - 1 }.count == 5 }
            // Nothing of the folded list is left in the band over the article (the list's magnifier went with its column).
            let overArticle: Int = bandFrames().filter { $0.maxX <= noteLeft }.count
            #expect(overArticle == 4)
        }

        /// Issue #370 (specification 3.5): dragging the note's edge to the right stops at the panel's minimum and never folds the panel.
        @Test func draggingTheNoteEdgeToTheRightNeverFoldsTheNote() async throws {
            let h = try harness(noteOpen: true)
            defer { finish(h) }
            try await settle(h) { noteVisible(h) }
            let editor = try #require(editor(in: h))
            var view: NSView? = editor.superview
            var found: (NSSplitViewController, Int)?
            while let current = view, found == nil {
                if let split = current as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
                   let index = controller.splitViewItems.firstIndex(where: { editor.isDescendant(of: $0.viewController.view) }) {
                    found = (controller, index)
                }
                view = current.superview
            }
            let (controller, index) = try #require(found)
            #expect(index > 0)
            // What the person's drag does: the divider before the note moves to the window's right edge, in steps.
            for step in 1...10 {
                let position = controller.splitView.frame.width - CGFloat(10 - step) * 40
                controller.splitView.setPosition(position, ofDividerAt: index - 1)
                h.host.layoutSubtreeIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(300))
            try await settle(h) { noteVisible(h) && !controller.splitViewItems[index].isCollapsed }
            let width = try #require(self.editor(in: h)).enclosingScrollView.map { $0.convert($0.bounds, to: nil).width } ?? 0
            #expect(width >= NotePanelWidth.range.lowerBound - 40, "the note is \(width) pt wide")
        }

        @Test func aNoteOpenAtTheStartHasTheListFolded() async throws {
            let h = try harness(noteOpen: true)
            defer { finish(h) }
            let list = try #require(table(in: h))
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            try await settle(h) { noteVisible(h) && !sidebarButtonsMounted(h) && (x(article(in: h)) ?? 999) < 40 }
            // Decision 0050 point 5: the note is 640 pt wide at first (in this test's own defaults, nothing saved by the person), or what the
            // 1,240 pt window leaves after the article's 360 pt and the list's 280 pt (specification 3.5).
            if UserDefaults.standard.object(forKey: NotePanelWidth.key) == nil {
                let expected = min(NotePanelWidth.defaultWidth, NotePanelWidth.maximum(windowWidth: 1_240))
                try await settle(h) { abs(1_240 - (x(editor(in: h)) ?? 0) - expected) < 2 }
            }
        }
    }
}
