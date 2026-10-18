import Foundation
import SwiftData
@testable import ReaderCore

/// Hosted work can outlive scratch cleanup. These fixtures deliberately omit SQLite save/rollback.
/// Disk-backed core tests and NoteTextEditorTests keep separate persistence coverage.
@MainActor func inMemoryReaderStore() throws -> ReaderStore {
    let schema = ReaderStore.schema
    let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ReaderStore(container: ModelContainer(for: schema, configurations: [configuration]))
}
