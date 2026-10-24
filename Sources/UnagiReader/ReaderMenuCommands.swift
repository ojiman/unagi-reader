import SwiftUI
import ReaderCore

/// The band's actions in the menu bar (decision 0057: nothing is only in a band; Apple's guideline for toolbar items). The library window
/// publishes them; with no such window the items are off.
struct ReaderActions {
    let noteOpen: Bool
    let toggleNote: () -> Void
    let starred: Bool
    let canStar: Bool
    let toggleStar: () -> Void
    let canSendToNote: Bool
    let sendToNote: () -> Void
    let canOpenBrowser: Bool
    let openBrowser: () -> Void
}

private struct ReaderActionsKey: FocusedValueKey { typealias Value = ReaderActions }

extension FocusedValues {
    var readerActions: ReaderActions? {
        get { self[ReaderActionsKey.self] }
        set { self[ReaderActionsKey.self] = newValue }
    }
}

struct ReaderMenuCommands: Commands {
    @FocusedValue(\.readerActions) private var actions

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(actions?.noteOpen == true ? String(localized: "Close Note", bundle: ReaderLocalization.bundle) : String(localized: "Open Note", bundle: ReaderLocalization.bundle)) { actions?.toggleNote() }
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(actions == nil)
        }
        CommandMenu(String(localized: "Article", bundle: ReaderLocalization.bundle)) {
            Button(actions?.starred == true ? String(localized: "Remove Star", bundle: ReaderLocalization.bundle) : String(localized: "Add Star", bundle: ReaderLocalization.bundle)) { actions?.toggleStar() }
                .disabled(actions?.canStar != true)
            // 「記事をノートに送る」 (specification 3.3). ⌘K works wherever the keyboard is, also in the note's editor; its reading key `i`
            // is not shown here, as with the others in this menu.
            Button(String(localized: "Send Article to Note", bundle: ReaderLocalization.bundle)) { actions?.sendToNote() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions?.canSendToNote != true)
            Button(String(localized: "Open original page in browser", bundle: ReaderLocalization.bundle)) { actions?.openBrowser() }
                .disabled(actions?.canOpenBrowser != true)
        }
    }
}

/// Help ▸ 「ショートカット一覧」: opens Settings on the shortcut list (specification 3.7).
struct ShortcutHelpCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(String(localized: "Keyboard Shortcuts", bundle: ReaderLocalization.bundle)) {
                UserDefaults.standard.set(ReaderSettingsView.Pane.shortcuts.rawValue, forKey: ReaderSettingsView.paneKey)
                openSettings()
            }
        }
    }
}
