import SwiftUI
import AppKit
import ReaderCore

/// A text view that takes and gives only plain text: pasting or dropping rich text inserts its plain text, and copying puts only the
/// characters on the pasteboard (the headings' size and the list marks' colour are not part of the note).
final class NoteTextView: NSTextView {
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }
    /// The editor does not restyle while text is being composed, so the text being composed would take the typing attributes, which can be
    /// left over from a heading (a heading line without text is still drawn as body text, and after Return the bold font and the marks'
    /// grey stay). It takes the look of its own line instead: the heading's font or the body's, and the text colour. Only the font and the
    /// colour are set: the input method's own marks stay.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        let marked = markedRange()
        guard let storage = textStorage, marked.location != NSNotFound, marked.length > 0 else { return }
        let source = storage.string as NSString
        let paragraph = source.paragraphRange(for: marked)
        var font = NoteEditorStyle.baseFont
        for run in NoteLineStyle.runs(in: source.substring(with: paragraph), baseOffset: paragraph.location) {
            if case .heading(let level) = run.kind, NSIntersectionRange(run.line, marked).length > 0 { font = NoteEditorStyle.headingFont(level: level) }
        }
        storage.addAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: marked)
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
    override func pasteAsRichText(_ sender: Any?) { pasteAsPlainText(sender) }
    /// Run once when the view is next put in a window: the editor of a note being opened is not in the window until the panel is shown.
    var whenInWindow: (@MainActor @Sendable () -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let action = whenInWindow else { return }
        whenInWindow = nil
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { action() } }
    }
}

/// The way into the note editor from outside, for 「記事をノートに送る」 (specification 3.3). The reader keeps one; the editor that is
/// shown attaches itself. Text sent while no editor is shown waits, and goes at the end of the note when one is.
@MainActor final class NoteEditorLink {
    enum Result: Equatable {
        case inserted
        /// The text is in the editor, but the save failed; the editor shows that, as it does for typing.
        case notSaved
        /// Japanese text is being composed in the note: nothing was inserted.
        case composing
        /// The text view did not take the change (it was not editable): nothing was inserted.
        case refused
        case noEditor
    }
    fileprivate weak var coordinator: NoteTextEditor.Coordinator?
    private var waiting: [String] = []
    private var focusWaiting = false
    /// The number of the latest request to take the keyboard; a cancel or a newer request changes it, so an older callback does nothing.
    private var focusRequest = 0

    /// Shows where the text went, with the system's find indicator, and tells VoiceOver (specification 3.3). Replaced in tests.
    var showInserted: (NSTextView, NSRange) -> Void = { view, range in
        view.showFindIndicator(for: range)
        NSAccessibility.post(element: view, notification: .announcementRequested,
                             userInfo: [.announcement: String(localized: "Sent to note", bundle: ReaderLocalization.bundle), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// The window the editor is in; the reader has no other way to it while the window is not the key window.
    var window: NSWindow? { coordinator?.textView?.window }

    /// False while no editor is shown or text is being composed in it.
    var canInsert: Bool { coordinator?.canInsert ?? false }

    /// After the note's caret or selection, where the person left it; at the end of a note whose caret they never placed.
    func insert(_ text: String) -> Result {
        guard let coordinator else { return .noEditor }
        let (result, range) = coordinator.insert(text, atEnd: false)
        if result == .inserted, let range { show(range, in: coordinator, after: 0) }
        return result
    }

    /// For a note that was closed and is being opened: at the end of the note, now if an editor is there, else when one is shown.
    /// Nil while the text waits.
    @discardableResult func insertWhenShown(_ text: String) -> Result? {
        guard let coordinator else { waiting.append(text); return nil }
        let (result, range) = coordinator.insert(text, atEnd: true)
        if result == .inserted, let range { show(range, in: coordinator, after: Self.openingTime) }
        return result
    }

    /// The note's opening motion, and a little more: the indicator is shown once the note has come in.
    static let openingTime = SidebarFold.motionDuration + 0.05

    /// A run loop timer, so it also fires inside a nested run of the loop (as in a hosted test).
    private func show(_ range: NSRange, in coordinator: NoteTextEditor.Coordinator, after delay: TimeInterval) {
        let showNow: @MainActor () -> Void = { [weak self, weak coordinator] in
            guard let self, let view = coordinator?.textView, NSMaxRange(range) <= (view.string as NSString).length else { return }
            self.showInserted(view, range)
        }
        guard delay > 0 else { showNow(); return }
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { showNow() } }
    }

    /// The note being opened takes the keyboard (decision 0064): now if an editor is there, else when one is shown. After this pass of the
    /// view update, as for waiting text.
    func focusWhenShown() {
        focusRequest += 1
        guard coordinator != nil else { focusWaiting = true; return }
        queueFocus()
    }

    private func queueFocus() {
        guard let coordinator else { return }
        let request = focusRequest
        RunLoop.main.perform(inModes: [.common]) { [weak self, weak coordinator] in
            MainActor.assumeIsolated {
                coordinator?.takeKeyboard(stillWanted: { [weak self] in self?.focusRequest == request })
            }
        }
    }

    /// The note closed before its editor took the keyboard: it does not take it later (#322).
    func cancelFocus() {
        focusRequest += 1
        focusWaiting = false
        coordinator?.cancelKeyboard()
    }

    fileprivate func attach(_ coordinator: NoteTextEditor.Coordinator) {
        guard self.coordinator !== coordinator else { return }
        self.coordinator = coordinator
        if focusWaiting { focusWaiting = false; queueFocus() }                // the same request, now with an editor
        guard !waiting.isEmpty else { return }
        // After this pass of the view update: the editor first gets the store's text, which would otherwise be put back over the insertion.
        // A run loop block, not the main queue, so it also runs inside a nested run of the loop (as in a hosted test).
        RunLoop.main.perform(inModes: [.common]) { [weak self] in MainActor.assumeIsolated { self?.insertWaiting() } }
    }

    private func insertWaiting() {
        guard let coordinator else { return }
        let texts = waiting
        waiting = []
        for text in texts {
            let (result, range) = coordinator.insert(text, atEnd: true)
            if result == .inserted, let range { show(range, in: coordinator, after: Self.openingTime) }
        }
    }
}

/// The note editor: an AppKit text view (SwiftUI's `TextEditor` has no hook for display attributes of plain text). The saved text is
/// exactly what is typed: no smart quotes, dashes, spaces or replacements, no list continuation; headings and list lines only get a look
/// (`NoteEditorStyle`). Styling never touches the text and waits while Japanese text is being composed.
struct NoteTextEditor: NSViewRepresentable {
    let text: String
    /// Called once per edit by the person (typing, paste, undo, redo) with the whole text; returns whether it was saved.
    let onChange: (String) -> Bool
    /// How 「記事をノートに送る」 reaches this editor.
    var link: NoteEditorLink? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NoteTextView()
        textView.isRichText = true                       // needed for attributes; paste, drop and copy stay plain (NoteTextView)
        textView.allowsUndo = true
        textView.usesFontPanel = false; textView.usesRuler = false; textView.importsGraphics = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.font = NoteEditorStyle.baseFont
        textView.typingAttributes = NoteEditorStyle.baseAttributes()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(String(localized: "Note", bundle: ReaderLocalization.bundle))
        textView.string = text
        if let storage = textView.textStorage {
            NoteEditorStyle.apply(to: storage, around: NSRange(location: 0, length: storage.length))
            storage.delegate = context.coordinator
        }
        textView.delegate = context.coordinator
        context.coordinator.attach(textView, shownText: text)
        link?.attach(context.coordinator)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        link?.attach(context.coordinator)
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.show(text, in: textView)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
        var onChange: (String) -> Bool
        weak var textView: NSTextView?
        /// Each editor has its own undo history: it is not shared with the window, with the article list, or with the editor of another note.
        private let undoHistory = UndoManager()
        private var observers: [NSObjectProtocol] = []
        /// The text the store last agreed with: what was last shown from outside, or last saved.
        private var agreedText: String
        /// Text from outside that arrived while Japanese text was being composed; it is merged in when the composition ends.
        private var waitingText: String?
        /// The paragraphs a styling pass skipped while composing; they are restyled when the composition ends.
        private var skippedRange: NSRange?
        var restylePending: Bool { skippedRange != nil }
        /// The last save failed: the view holds text the store does not, so store text is not pushed over it.
        private var unsaved = false
        /// True while text that arrived from outside is being put in; that is not an edit by the person, so it is not saved back.
        private var applyingOutsideText = false
        /// The person has placed the caret in this editor; until then 「記事をノートに送る」 goes at the end of the note.
        private var caretPlaced = false

        init(onChange: @escaping (String) -> Bool) { self.onChange = onChange; agreedText = "" }

        func attach(_ textView: NSTextView, shownText: String) {
            self.textView = textView
            agreedText = shownText
            // TextKit 2 does not post a change notification for undo and redo, so they are watched here.
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: undoHistory, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.undoOrRedoDone() }
                })
            }
        }
        isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func undoManager(for view: NSTextView) -> UndoManager? { undoHistory }

        /// `Esc` (`cancelOperation:`) is not the text view's: it goes up to the window, which closes the note (decision 0050). While
        /// Japanese text is being composed the input method takes the first `Esc`; if one still arrives here, it only ends the composition
        /// (it never opens the text view's completion list).
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            if textView.hasMarkedText() { textView.inputContext?.discardMarkedText(); return true }
            textView.nextResponder?.tryToPerform(selector, with: nil)
            return true
        }

        private func undoOrRedoDone() {
            guard let textView, textView.string != agreedText else { return }
            save(textView.string)
        }

        private func save(_ text: String) {
            if onChange(text) { agreedText = text; unsaved = false } else { unsaved = true }
        }

        /// Text that arrives from outside (a summary that was sent, its undo) is put in as a change of only the part that differs, in one
        /// undoable edit, so the selection and the scroll position stay. It waits while a composition is in progress, and it does not
        /// overwrite typed text that could not be saved.
        func show(_ text: String, in textView: NSTextView) {
            if textView.hasMarkedText() {
                waitingText = text == agreedText ? nil : text
                return
            }
            if unsaved { unsaved = textView.string != text; if unsaved { return } }
            waitingText = nil
            guard textView.string != text else { agreedText = text; return }
            replace(textView, with: text)
            agreedText = text
        }

        private func replace(_ textView: NSTextView, with text: String) {
            let old = textView.string as NSString, new = text as NSString
            var start = 0
            let shortest = min(old.length, new.length)
            while start < shortest, old.character(at: start) == new.character(at: start) { start += 1 }
            var tail = 0
            while tail < shortest - start, old.character(at: old.length - 1 - tail) == new.character(at: new.length - 1 - tail) { tail += 1 }
            if start > 0, UTF16.isLeadSurrogate(old.character(at: start - 1)) { start -= 1 }            // never cut a surrogate pair
            if tail > 0, UTF16.isTrailSurrogate(old.character(at: old.length - tail)) { tail -= 1 }
            let oldRange = NSRange(location: start, length: old.length - tail - start)
            let replacement = new.substring(with: NSRange(location: start, length: new.length - tail - start))
            let selection = textView.selectedRange()
            guard textView.shouldChangeText(in: oldRange, replacementString: replacement) else { return }
            applyingOutsideText = true
            defer { applyingOutsideText = false }
            textView.textStorage?.replaceCharacters(in: oldRange, with: replacement)
            textView.didChangeText()
            let delta = (replacement as NSString).length - oldRange.length
            let oldEnd = oldRange.location + oldRange.length
            if selection.location + selection.length <= oldRange.location {
                textView.setSelectedRange(selection)
            } else if selection.location >= oldEnd {
                textView.setSelectedRange(NSRange(location: selection.location + delta, length: selection.length))
            } else {
                textView.setSelectedRange(NSRange(location: min(selection.location, new.length), length: 0))
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !applyingOutsideText else { return }
            settleAfterComposition(textView)
            save(textView.string)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView, textView.window?.firstResponder === textView { caretPlaced = true }
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText(), skippedRange != nil || waitingText != nil else { return }
            settleAfterComposition(textView)
            if textView.string != agreedText { save(textView.string) }
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            if textView?.hasMarkedText() == true {
                skippedRange = skippedRange.map { NSUnionRange($0, editedRange) } ?? editedRange
                return
            }
            NoteEditorStyle.apply(to: textStorage, around: editedRange)
        }

        var canInsert: Bool { textView.map { !$0.hasMarkedText() } ?? false }

        func cancelKeyboard() { (textView as? NoteTextView)?.whenInWindow = nil }

        /// The editor takes the keyboard, if the request is still wanted when this runs. The caret stays where the person left it; in a
        /// note they have not placed it in, it goes at the end.
        func takeKeyboard(stillWanted: @escaping @MainActor () -> Bool) {
            guard stillWanted(), let textView else { return }
            guard let window = textView.window else {
                (textView as? NoteTextView)?.whenInWindow = { [weak self] in self?.takeKeyboard(stillWanted: stillWanted) }
                return
            }
            guard window.makeFirstResponder(textView) else { return }
            if !caretPlaced {
                let end = NSRange(location: (textView.string as NSString).length, length: 0)
                textView.setSelectedRange(end)
                textView.scrollRangeToVisible(end)
            }
        }

        /// 「記事をノートに送る」 (specification 3.3): the text goes after the caret or selection the person left (nothing is replaced), or at
        /// the end of the note, as a paragraph of its own (`NoteClip.paragraph`). It is one undo step and is saved like typing. The keyboard
        /// does not move; the caret goes after the text, so the next one follows it. Also returns where the text itself went.
        func insert(_ text: String, atEnd: Bool) -> (NoteEditorLink.Result, NSRange?) {
            guard let textView else { return (.noEditor, nil) }
            guard !textView.hasMarkedText() else { return (.composing, nil) }
            let current = textView.string as NSString
            let point = atEnd || !caretPlaced ? current.length : min(NSMaxRange(textView.selectedRange()), current.length)
            let (piece, offset) = NoteClip.paragraph(text, in: textView.string, at: point)
            let range = NSRange(location: point, length: 0)
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: range, replacementString: piece) else { return (.refused, nil) }
            textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: piece, attributes: NoteEditorStyle.baseAttributes()))
            textView.didChangeText()                                         // saves, through textDidChange
            textView.breakUndoCoalescing()
            let end = NSRange(location: point + (piece as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
            caretPlaced = true
            return (unsaved ? .notSaved : .inserted, NSRange(location: point + offset, length: (text as NSString).length))
        }

        /// After a composition ends: restyle what was skipped, then merge text that came from outside meanwhile. Only an append and the
        /// removal of an earlier append are merged; anything else leaves what the person typed.
        private func settleAfterComposition(_ textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            if let skipped = skippedRange, let storage = textView.textStorage {
                skippedRange = nil
                NoteEditorStyle.apply(to: storage, around: skipped)
            }
            guard let incoming = waitingText else { return }
            waitingText = nil
            let current = textView.string
            let merged: String?
            if incoming.hasPrefix(agreedText) {
                merged = current + incoming.dropFirst(agreedText.count)
            } else if agreedText.hasPrefix(incoming) {
                let removed = String(agreedText.dropFirst(incoming.count))
                merged = current.hasSuffix(removed) ? String(current.dropLast(removed.count)) : nil
            } else {
                merged = nil
            }
            guard let merged, merged != current else { return }
            replace(textView, with: merged)
        }
    }
}
