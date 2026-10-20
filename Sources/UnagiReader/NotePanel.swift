import SwiftUI
import ReaderCore

/// The note, opened beside the article as the inspector: its band (the ✕, the layout button, previous and next article, copy) and the
/// editor.
struct NotePanel: View {
    @Bindable var store: ReaderStore
    let canPrevious: Bool
    let canNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void
    /// The note shows the list beside it (the layout button's state).
    let listShown: Bool
    let onSwitchLayout: () -> Void
    /// How 「記事をノートに送る」 reaches the editor (specification 3.3).
    let link: NoteEditorLink

    var body: some View {
        VStack(spacing: 0) {
            header
            NoteEditor(store: store, link: link)
        }
        .ignoresSafeArea(.container, edges: .top)                          // the band is at the top of the window, like the others
        .accessibilityElement(children: .contain).accessibilityLabel(String(localized: "Note", bundle: ReaderLocalization.bundle))
    }

    /// The note's band (decision 0057): the ✕ and the layout button at the left, the article arrows and copy at the right.
    private var header: some View {
        HStack(spacing: 2) {
            // The ✕ at the top left of the right column, where the original page has its own (decision 0050).
            BandButton(id: "close", symbol: "xmark", help: String(localized: "Close Note (Esc)", bundle: ReaderLocalization.bundle), label: String(localized: "Close Note", bundle: ReaderLocalization.bundle), action: onClose)
            // The two layouts of the open note (decision 0050).
            BandButton(id: "layout", symbol: listShown ? "rectangle.split.3x1" : "rectangle.split.2x1",
                       help: listShown ? String(localized: "Hide Article List", bundle: ReaderLocalization.bundle) : String(localized: "Show Article List", bundle: ReaderLocalization.bundle), label: listShown ? String(localized: "Hide Article List", bundle: ReaderLocalization.bundle) : String(localized: "Show Article List", bundle: ReaderLocalization.bundle),
                       action: onSwitchLayout)
            Spacer(minLength: 8)
            BandButton(id: "previous", symbol: "chevron.up", help: String(localized: "Previous Article (⌥⌘↑)", bundle: ReaderLocalization.bundle), label: String(localized: "Previous Article", bundle: ReaderLocalization.bundle), enabled: canPrevious,
                       shortcut: KeyboardShortcut(.upArrow, modifiers: [.option, .command]), action: onPrevious)
            BandButton(id: "next", symbol: "chevron.down", help: String(localized: "Next Article (⌥⌘↓)", bundle: ReaderLocalization.bundle), label: String(localized: "Next Article", bundle: ReaderLocalization.bundle), enabled: canNext,
                       shortcut: KeyboardShortcut(.downArrow, modifiers: [.option, .command]), action: onNext)
            // The text is copied as it is; the person pastes it into any AI they like (decision 0049).
            BandButton(id: "copy", symbol: "doc.on.doc", help: String(localized: "Copy Markdown", bundle: ReaderLocalization.bundle), label: String(localized: "Copy Markdown", bundle: ReaderLocalization.bundle), enabled: hasText, action: onCopy)
        }
        .bandLayout()
    }

    private var hasText: Bool {
        link.hasCopyText ?? !(store.note?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
