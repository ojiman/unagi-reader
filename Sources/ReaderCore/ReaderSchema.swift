import SwiftData

/// The store's models as 1.0 ships them (specification 7.1). From 1.0 the library is kept across updates, so V1 never changes.
/// It lists the classes the app uses today; the first model change copies them into this enum unchanged, then adds
/// `ReaderSchemaV2` and a stage in `ReaderMigrationPlan` (architecture 3).
public enum ReaderSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [Feed.self, Article.self, ContentSnapshot.self, FeedMembership.self, ReaderSettings.self, Note.self]
    }
}

/// Every schema version, oldest first, and how to move between them. A library written before the schema had a version has
/// the V1 models, so it opens as V1.
public enum ReaderMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [ReaderSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
