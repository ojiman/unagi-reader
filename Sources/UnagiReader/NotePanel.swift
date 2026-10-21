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
    /// Copies the note; true when the text is on the pasteboard.
    let onCopy: () -> Bool
    let onClose: () -> Void
    /// The note shows the list beside it (the layout button's state).
    let listShown: Bool
    let onSwitchLayout: () -> Void
    /// How 「記事をノートに送る」 reaches the editor (specification 3.3).
    let link: NoteEditorLink
    @State private var copySign = CopySign()

    var body: some View {
        VStack(spacing: 0) {
            header
            NoteEditor(store: store, link: link)
        }
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
            // A check mark for a moment says the copy worked (#374); nothing changes when it did not.
            BandButton(id: "copy", symbol: copySign.symbol, help: String(localized: "Copy Markdown", bundle: ReaderLocalization.bundle), label: String(localized: "Copy Markdown", bundle: ReaderLocalization.bundle), enabled: hasText) {
                guard onCopy() else { return }
                copySign.show()
                AccessibilityNotification.Announcement(String(localized: "Note copied", bundle: ReaderLocalization.bundle)).post()
            }
        }
        .bandLayout()
    }

    private var hasText: Bool {
        link.hasCopyText ?? !(store.note?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

/// The copy button's symbol: a check mark for a moment after a copy, then the copy symbol again. The symbol changes at once, so Reduce
/// Motion needs nothing of its own.
@Observable @MainActor final class CopySign {
    private(set) var symbol = "doc.on.doc"
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private var hiding: Task<Void, Never>?

    init(duration: Duration = .seconds(1.5)) { self.duration = duration }

    func show() {
        symbol = "checkmark"
        hiding?.cancel()
        hiding = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.symbol = "doc.on.doc"
        }
    }
}
