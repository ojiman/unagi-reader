import AppKit
import SwiftUI
import ReaderCore

enum ReaderCommand: String {
    case next = "j", previous = "k", toggleStar = "s", toggleNote = "n", closeOriginal = "Escape"
}

@MainActor enum ReaderKeyboardCommands {
    static func command(for event: NSEvent) -> ReaderCommand? {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        return event.keyCode == 53 ? .closeOriginal : ReaderCommand(rawValue: event.charactersIgnoringModifiers?.lowercased() ?? "")
    }
    static func acceptsDisplay(articleID: UUID, selectedID: UUID?, contentID: UUID?, originalVisible: Bool) -> Bool {
        !originalVisible && selectedID == articleID && contentID == articleID
    }
    static func listHasFocus(declared: Bool, responder: NSResponder?) -> Bool {
        declared || responder is NSTableView
    }
    /// An editable text view (the note) or a text field takes the keys. The reader's text view is read-only and does not.
    static func isTextInput(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSTextView { return view.isEditable }
        return responder is NSTextField
    }
    /// The keyboard is in the original page: its web view (the page's own fields included) or the failure pane.
    static func isInOriginalPage(_ responder: NSResponder?) -> Bool {
        if responder is OriginalFailureHostingView<AnyView> { return true }
        var view = responder as? NSView
        while let current = view { if current is OriginalReaderWebView { return true }; view = current.superview }
        return false
    }
    /// The open original page's view that takes the keyboard: its web view, or the failure pane.
    static func originalPage(in view: NSView) -> NSView? {
        if view is OriginalReaderWebView || view is OriginalFailureHostingView<AnyView> { return view }
        return view.subviews.lazy.compactMap { originalPage(in: $0) }.first
    }
    static func hasMarkedText(_ responder: NSResponder?) -> Bool {
        (responder as? NSTextInputClient)?.hasMarkedText() == true
    }
    static func permits(sheet: Bool, originalPage: Bool) -> Bool {
        let responder = NSApp.keyWindow?.firstResponder
        return ReaderShortcutPolicy.permits(textInput: isTextInput(responder), markedText: hasMarkedText(responder),
            sheet: sheet || NSApp.keyWindow?.attachedSheet != nil, originalPage: originalPage)
    }
}

// Scroll memory is intentionally not observable: native scroll events must not redraw the entire reader.
@MainActor final class ReaderScrollMemory {
    var state = ReaderSelectionState()
}
