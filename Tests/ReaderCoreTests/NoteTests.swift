import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Decision 0049: the app has one note.
// Checks PRD-04 (specification 7).
@MainActor struct NoteTests {
    let at = Date(timeIntervalSince1970: 1_791_152_000)

    @Test func theSchemaHasTheNoteAndNoRecordOfArticlesInIt() {
        let names = Set(ReaderStore.schema.entities.map(\.name))
        #expect(names.contains("Note"))
        #expect(names.isDisjoint(with: ["NoteArticle", "Theme", "ThemeArticle", "ThemeQuestion"]))
    }

    @Test func aNewStoreHasOneEmptyNoteAndAnOpenedOneKeepsIt() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let id = try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: at)
            #expect(store.notes.count == 1 && store.note?.text == "" && store.note?.createdAt == at)
            return try #require(store.note?.id)
        }
        let reopened = try ReaderStore(url: library.url, now: at.addingTimeInterval(day))
        #expect(reopened.notes.count == 1 && reopened.note?.id == id)                       // not a second one, not a new one
    }

    let day: TimeInterval = 86_400

    @Test func aNoteIsStoredExactlyAsTypedAndKeptAfterReopen() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let text = "# 見出し\r\n  本文の行  \n\n- 箇条書き\n"
        try autoreleasepool {
            let store = try ReaderStore(url: library.url, seedDemo: true, now: at)
            let note = try #require(store.note)
            try store.saveNote(text: text, at: at.addingTimeInterval(3))
            #expect(note.text == text && note.updatedAt == at.addingTimeInterval(3))
            let stamp = note.updatedAt
            try store.saveNote(text: text, at: at.addingTimeInterval(9))                      // no change, no new stamp
            #expect(note.updatedAt == stamp)
        }
        let note = try #require(ReaderStore(url: library.url, now: at).note)
        #expect(note.text == text && note.createdAt == at && note.updatedAt == at.addingTimeInterval(3))
    }

    @Test func savingANoteDoesNotCommitAnUnrelatedPendingArticleChange() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, seedDemo: true, now: at)
        let article = try #require(store.articles.first)
        let id = article.id, originalTitle = article.title
        article.title = "An unrelated, unsaved change"
        try store.saveNote(text: "Only this note is saved", at: at)
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.note?.text == "Only this note is saved")
        #expect(reopened.article(id: id)?.title == originalTitle)
    }

    @Test func noteAndLibrarySavesKeepBothAfterAFullReloadAndReopen() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, seedDemo: true, now: at)
        let articleID = try #require(store.articles.first?.id)
        let feed = try #require(store.feeds.first)
        let feedID = feed.id
        try store.saveNote(text: "Before library changes", at: at)
        try store.markDisplayed(articleID: articleID, at: at)
        try store.setStar(articleID: articleID, isStarred: true, at: at)
        try store.updateSubscription(feed, title: "Renamed feed", folder: "Synthetic")
        #expect(store.note?.text == "Before library changes")
        try store.saveNote(text: "After the full reload", at: at.addingTimeInterval(1))
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.note?.text == "After the full reload")
        #expect(reopened.note?.updatedAt == at.addingTimeInterval(1))
        #expect(reopened.article(id: articleID)?.firstReadAt == at)
        #expect(reopened.article(id: articleID)?.starredAt == at)
        #expect(reopened.feed(id: feedID)?.title == "Renamed feed")
    }

    @Test func savingWithoutANoteIsAnErrorNotASilentDrop() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        for note in try store.context.fetch(FetchDescriptor<Note>()) { store.context.delete(note) }                               // a store that lost its note after it was opened
        try store.context.save(); try store.reload()
        #expect(store.note == nil)
        #expect(throws: NoteError.missingNote) { try store.saveNote(text: "書いたこと", at: at) }
    }

    @Test func aLongNoteSavesAndItsTimeIsRecorded() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, seedDemo: true, now: at)
        let long = String(repeating: "長いノートの一行です。\n", count: 10_000)                 // about 100,000 characters
        let start = ContinuousClock.now
        try store.saveNote(text: long, at: at)
        print("note-save 100k characters:", ContinuousClock.now - start)                       // recorded in the verification file, not a gate
        #expect(store.note?.text.count == long.count)
    }

    final class SaveGate { var failNext = false }

    @Test func failedSaveLeavesNoPartialNoteStateAndCanBeRetried() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let gate = SaveGate()
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, seedDemo: true, now: at, saveHook: {
            if gate.failNext { gate.failNext = false; throw CocoaError(.fileWriteUnknown) }
        })
        try store.saveNote(text: "# 成功\n", at: at)
        gate.failNext = true
        #expect(throws: (any Error).self) { try store.saveNote(text: "失われるノート", at: at) }
        #expect(store.notes.count == 1 && store.note?.text == "# 成功\n")
        #expect(try ReaderStore(url: library.url, now: at).note?.text == "# 成功\n")
        try store.saveNote(text: "再試行のノート", at: at.addingTimeInterval(1))
        #expect(store.note?.text == "再試行のノート")
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.notes.count == 1 && reopened.note?.text == "再試行のノート")
    }

    final class RecoveryGate { var failSave = false, failReload = false }

    /// Once reloading works again, the very first note change must recover the store and succeed.
    /// `save()` alone refuses while a reload is pending, so only a leading `reloadIfNeeded()` passes this.
    @Test func theNoteChangeRecoversOnItsFirstCallAfterReloadSucceeds() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let gate = RecoveryGate()
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration("Reader", schema: schema, url: library.url, cloudKitDatabase: .none)])
        let store = try ReaderStore(container: container, seedDemo: true, now: at, saveHook: {
            if gate.failSave { throw CocoaError(.fileWriteUnknown) }
        }, reloadHook: {
            if gate.failReload { throw CocoaError(.fileReadUnknown) }
        })
        func induceFailedRecovery() {
            gate.failSave = true; gate.failReload = true
            #expect(throws: (any Error).self) { try store.saveNote(text: "誘発", at: at.addingTimeInterval(5)) }
            gate.failSave = false; gate.failReload = false
        }
        induceFailedRecovery()
        induceFailedRecovery()
        try store.saveNote(text: "回復後のノート", at: at.addingTimeInterval(6))
        #expect(store.notes.count == 1 && store.note?.text == "回復後のノート")
    }

    // MARK: the first start of this version, on a store that has several notes or none (decision 0049)

    /// Writes notes straight into a store file, as an older version could have left them.
    private func storeWith(_ notes: [(text: String, edited: TimeInterval, id: String?)], in library: TestLibrary) throws {
        try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: at)
            for note in try store.context.fetch(FetchDescriptor<Note>()) { store.context.delete(note) }
            for entry in notes {
                let note = Note(text: entry.text, at: at)
                if let id = entry.id { note.id = UUID(uuidString: id)! }
                note.updatedAt = at.addingTimeInterval(entry.edited)
                store.context.insert(note)
            }
            try store.context.save()
        }
    }

    @Test func severalNotesBecomeTheOneEditedLastAndTheOthersAreDeleted() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        try storeWith([("# 古い\n", 10, nil), ("# 最後に編集した\n本文", 300, nil), ("# 真ん中\n", 100, nil)], in: library)
        try autoreleasepool {
            let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(day))
            #expect(store.notes.count == 1)
            #expect(store.note?.text == "# 最後に編集した\n本文" && store.note?.updatedAt == at.addingTimeInterval(300))
        }
        let again = try ReaderStore(url: library.url, now: at.addingTimeInterval(2 * day))       // the next start changes nothing
        #expect(again.notes.count == 1 && again.note?.text == "# 最後に編集した\n本文")
        #expect(again.note?.updatedAt == at.addingTimeInterval(300))
    }

    @Test func notesEditedAtTheSameTimeKeepTheSameOneAtEveryStart() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let low = "00000000-0000-0000-0000-000000000001", high = "00000000-0000-0000-0000-0000000000FF"
        try storeWith([("高いID", 50, high), ("低いID", 50, low)], in: library)
        let store = try ReaderStore(url: library.url, now: at)
        #expect(store.notes.count == 1 && store.note?.id.uuidString == low && store.note?.text == "低いID")
    }

    @Test func aStoreWithNoNoteGetsAnEmptyOne() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        try storeWith([], in: library)
        let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(day))
        #expect(store.notes.count == 1 && store.note?.text == "" && store.note?.createdAt == at.addingTimeInterval(day))
    }

    @Test func theOnlyNoteIsLeftAloneAtStart() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        try storeWith([("# だけ\n", 20, "00000000-0000-0000-0000-0000000000AB")], in: library)
        let store = try ReaderStore(url: library.url, now: at.addingTimeInterval(day))
        #expect(store.notes.count == 1 && store.note?.id.uuidString == "00000000-0000-0000-0000-0000000000AB")
        #expect(store.note?.text == "# だけ\n" && store.note?.updatedAt == at.addingTimeInterval(20))
    }
}
