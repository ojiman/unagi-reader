import Foundation
import SwiftData

public enum NoteError: LocalizedError {
    case missingNote
    public var errorDescription: String? {
        switch self {
        case .missingNote: String(localized: "The note could not be found.", bundle: ReaderLocalization.bundle)
        }
    }
}

/// The one note of the app (decision 0049): plain Markdown text, written beside the article.
@Model public final class Note {
    @Attribute(.unique) public var id: UUID
    /// The note itself: plain Markdown text, `#` lines are headings. Stored exactly as typed; no length limit.
    public var text: String = ""
    public var createdAt: Date
    public var updatedAt: Date
    public init(text: String = "", at: Date) {
        id = UUID(); self.text = text; createdAt = at; updatedAt = at
    }
}

extension ReaderStore {
    /// The note. A store always has exactly one after it is opened (`keepOnlyOneNote`).
    public var note: Note? { notes.first }

    /// The typing path: the note is saved as it is, once per change. A missing note is an error, never a silent drop.
    public func saveNote(text: String, at: Date) throws {
        try reloadIfNeeded()
        guard let note else { throw NoteError.missingNote }
        guard note.text != text else { return }
        note.text = text; note.updatedAt = at
        try save(noteContext)
    }

    /// Decision 0049: the app has one note. A store that has several (from before this decision) keeps the one that was edited last and
    /// deletes the others; a store with none gets an empty one. Runs when the store is opened, before it is read.
    func keepOnlyOneNote(at now: Date) throws {
        let all = try context.fetch(FetchDescriptor<Note>())
        guard all.count != 1 else { return }
        if let keep = all.max(by: { Self.editedBefore($0, $1) }) {
            for note in all where note !== keep { context.delete(note) }
        } else {
            context.insert(Note(at: now))
        }
        try context.save()
    }

    /// Orders by the time of the last edit; equal times keep a fixed order by ID, so the same note is kept at every start.
    private static func editedBefore(_ a: Note, _ b: Note) -> Bool {
        a.updatedAt == b.updatedAt ? a.id.uuidString > b.id.uuidString : a.updatedAt < b.updatedAt
    }
}
