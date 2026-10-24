import Testing
@testable import ReaderCore

// Specification 3.7: the shortcut list is made from the keys the reader handles.
@Suite(EnglishLanguage()) struct ReaderShortcutsTests {
    @Test func everyReadingLetterIsInTheList() {
        let listed = Set(ReaderShortcuts.rows.flatMap(\.keys))
        for letter in ReaderShortcuts.readingLetters { #expect(listed.contains(letter), "\(letter) is not in the shortcut list") }
    }

    @Test func everyLetterInTheListIsHandled() {
        let letters = ReaderShortcuts.rows.flatMap(\.keys).filter { $0.count == 1 }
        for letter in letters { #expect(ReaderShortcuts.readingLetters.contains(letter), "\(letter) is listed but not handled") }
    }

    @Test func theGroupsAreInTheOrderOfTheSpecification() {
        #expect(ReaderShortcuts.Group.allCases.map(\.title) == ["Reading", "List", "Original Page", "Note"])
        for group in ReaderShortcuts.Group.allCases { #expect(!ReaderShortcuts.rows(in: group).isEmpty) }
        #expect(Set(ReaderShortcuts.rows.map(\.id)).count == ReaderShortcuts.rows.count)
    }

    @Test func theNotesKeysAreListed() {
        let note = ReaderShortcuts.rows(in: .note).flatMap(\.keys)
        #expect(note.contains("n") && note.contains("⌥⌘I") && note.contains("i") && note.contains("⌘K") && note.contains("⌥⌘↑") && note.contains("Esc"))
    }

    // #415: `i` replaces `c`; `⌘K` also works while typing in the note, so its row names no limit.
    @Test func sendingToTheNoteIsIAndCommandK() {
        #expect(ReaderShortcuts.readingLetters.contains("i") && !ReaderShortcuts.readingLetters.contains("c"))
        #expect(!ReaderShortcuts.rows.flatMap(\.keys).contains("c"))
        let letter = ReaderShortcuts.rows.first { $0.keys == ["i"] }
        let command = ReaderShortcuts.rows.first { $0.keys == ["⌘K"] }
        #expect(letter?.group == .note && letter?.limit == "Unavailable while typing")
        #expect(command?.group == .note && command?.limit == nil && command?.action == letter?.action)
    }
}
