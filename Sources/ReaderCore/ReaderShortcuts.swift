import Foundation

/// The keys of the reader, in one place (specification 3.1.5 and 3.7): the list's key handler takes its letters from here, and the
/// shortcut list in Settings shows these rows, so the list shows what the app does. Read only: keys cannot be changed.
public enum ReaderShortcuts {
    public enum Group: String, CaseIterable, Sendable {
        case reading, list, original, note
        public var title: String {
            switch self {
            case .reading: String(localized: "Reading", bundle: ReaderLocalization.bundle)
            case .list: String(localized: "List", bundle: ReaderLocalization.bundle)
            case .original: String(localized: "Original Page", bundle: ReaderLocalization.bundle)
            case .note: String(localized: "Note", bundle: ReaderLocalization.bundle)
            }
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let group: Group
        /// The keys as the person presses them, for example ["j", "k"] or ["⌥⌘I"].
        public let keys: [String]
        public let action: String
        /// Where the keys do not work, or nil.
        public let limit: String?
        public var id: String { keys.joined(separator: " ") + action }
    }

    /// The single letters the reader handles without a modifier key, from the list or the article, when no text is being typed.
    public static let readingLetters: [String] = ["j", "k", "m", "s", "t", "b", "v", "n", "i", "/"]

    static let whileTyping = String(localized: "Unavailable while typing", bundle: ReaderLocalization.bundle)
    static let sendToNote = String(localized: "Send article to note (selected text becomes a quotation)", bundle: ReaderLocalization.bundle)

    public static let rows: [Row] = [
        Row(group: .reading, keys: ["j", "k"], action: String(localized: "Next or previous article", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .reading, keys: ["m"], action: String(localized: "Toggle read or unread", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .reading, keys: ["s"], action: String(localized: "Add or remove Star", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .reading, keys: ["t"], action: String(localized: "Translate article or show original", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .reading, keys: ["b"], action: String(localized: "Open original page in browser", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .list, keys: ["/"], action: String(localized: "Filter the article list by keyword", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .original, keys: ["v"], action: String(localized: "Open original page in the app", bundle: ReaderLocalization.bundle), limit: whileTyping),
        Row(group: .original, keys: ["Esc"], action: String(localized: "Close original page and return to article", bundle: ReaderLocalization.bundle), limit: nil),
        Row(group: .original, keys: ["j", "k", "s", "n"], action: String(localized: "Also available while the original page is open", bundle: ReaderLocalization.bundle), limit: nil),
        Row(group: .note, keys: ["n", "⌥⌘I"], action: String(localized: "Open or close note", bundle: ReaderLocalization.bundle), limit: String(localized: "n is unavailable while typing", bundle: ReaderLocalization.bundle)),
        Row(group: .note, keys: ["i"], action: sendToNote, limit: whileTyping),
        // The menu's key: it works wherever the keyboard is, also while typing in the note (#415).
        Row(group: .note, keys: ["⌘K"], action: sendToNote, limit: nil),
        Row(group: .note, keys: ["⌥⌘↑", "⌥⌘↓"], action: String(localized: "Previous or next article with the note open", bundle: ReaderLocalization.bundle), limit: nil),
        Row(group: .note, keys: ["Esc"], action: String(localized: "Close note and return to article", bundle: ReaderLocalization.bundle), limit: String(localized: "While composing text, cancel composition first", bundle: ReaderLocalization.bundle)),
    ]

    public static func rows(in group: Group) -> [Row] { rows.filter { $0.group == group } }
}
