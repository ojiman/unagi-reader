import Foundation
import SwiftData

/// What a refresh batch wrote, for the main actor to refetch and publish. Values only: no model crosses actors (#303).
struct BatchResult: Sendable {
    var feedIDs: [UUID] = []
    var changedArticleIDs: [UUID] = []
    var newMembershipKeys: [String] = []
    var titlesChanged = false
    /// The feeds that could not be saved, even on their own.
    var errors: [UUID: any Error] = [:]

    mutating func add(_ other: BatchResult) {
        feedIDs += other.feedIDs; changedArticleIDs += other.changedArticleIDs; newMembershipKeys += other.newMembershipKeys
        titlesChanged = titlesChanged || other.titlesChanged
    }
}

/// Merges and saves refresh batches off the main thread (plan "Refresh merge off the main thread"). A plain actor, not a `@ModelActor`:
/// in step 0 a `@ModelActor`'s work ran on the main thread. Each batch gets a new `ModelContext`, so no context collects the library's
/// models and makes its saves walk them (#249, #303), and the batch's models go with it.
actor RefreshWriter {
    private let container: ModelContainer
    private let saveHook: (@Sendable () throws -> Void)?
    /// Built from the store when first needed, and again when the store's library generation is not the one it was built at.
    private var index: EntryIndex?
    private var indexGeneration: Int?
    /// For a test: whether the last batch was written on the main thread (it must not be).
    private(set) var lastRunOnMainThread = false

    init(container: ModelContainer, saveHook: (@Sendable () throws -> Void)? = nil) {
        self.container = container; self.saveHook = saveHook
    }

    /// Writes a batch with one save. When that save fails, each feed is written and saved on its own, so a feed that cannot be saved does
    /// not hold back the others. `generation` is the store's library generation when the batch was sent.
    func apply(_ items: [FetchedFeed], at: Date, retentionDays: Int, generation: Int) -> BatchResult {
        lastRunOnMainThread = pthread_main_np() != 0
        if indexGeneration != generation { index = nil }
        do {
            return try autoreleasepool { try write(items, at: at, retentionDays: retentionDays, generation: generation) }
        } catch {
            index = nil                                             // the failed batch's new IDs are not in the store
            var result = BatchResult()
            for item in items {
                do { result.add(try autoreleasepool { try write([item], at: at, retentionDays: retentionDays, generation: generation) }) }
                catch { index = nil; result.errors[item.feedID] = error }
            }
            return result
        }
    }

    private func write(_ items: [FetchedFeed], at: Date, retentionDays: Int, generation: Int) throws -> BatchResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let models = ArticleModels()
        var result = BatchResult()
        // A subscription removed, or given another address, since its fetch is skipped.
        var stored: [(item: FetchedFeed, feed: Feed)] = []
        for item in items {
            let id = item.feedID
            guard let feed = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == id })).first,
                  feed.sourceURL == item.sourceURL else { continue }
            stored.append((item, feed))
        }
        let toMerge: [(feedID: UUID, feed: ParsedFeed)] = stored.compactMap { item, feed in
            guard case .modified(let parsed, _, _) = item.result, parsed.sourceURL.absoluteString == feed.sourceURL else { return nil }
            return (feed.id, parsed)
        }
        var index: EntryIndex?
        if !toMerge.isEmpty {
            index = try currentIndex(generation: generation)
            index!.clearChanges()
            try EntryMerge.prefetch(toMerge, index: index!, into: context, models: models)
        }
        for (item, feed) in stored {
            if case .modified(let parsed, let etag, let modified) = item.result, parsed.sourceURL.absoluteString == feed.sourceURL, let index {
                let title = feed.title
                try EntryMerge.merge(parsed, receivedAt: at, folder: nil, index: index, into: context, feed: feed, models: models, retentionDays: retentionDays)
                result.titlesChanged = result.titlesChanged || feed.title != title
                feed.etag = etag; feed.lastModified = modified
            }
            feed.lastFetchedAt = at
            result.feedIDs.append(feed.id)
        }
        try saveHook?()
        try context.save()
        if let index {
            result.changedArticleIDs = Array(index.changedArticleIDs); result.newMembershipKeys = index.newMembershipKeys
            index.clearChanges()
        }
        return result
    }

    /// Fetched in a context of its own, so the batch's context does not register the whole library.
    private func currentIndex(generation: Int) throws -> EntryIndex {
        if let index { return index }
        let built = try autoreleasepool {
            let context = ModelContext(container)
            return EntryIndex(articles: try context.fetch(FetchDescriptor<Article>()), memberships: try context.fetch(FetchDescriptor<FeedMembership>()))
        }
        index = built; indexGeneration = generation
        return built
    }
}

/// The merge of a feed's entries into a context, used on the main actor (adding a subscription) and by `RefreshWriter`. Nothing here
/// reads the store: the caller gives the feed's model in `target`, the retention days, and the library's models it already holds.
enum EntryMerge {
    static func contentAvailable(_ article: Article, at: Date, retentionDays: Int) -> Bool {
        article.contentDeletedAt == nil &&
        RetentionPolicy(days: retentionDays).expiresAt(receivedAt: article.firstReceivedAt, firstReadAt: article.firstReadAt) > at
    }

    /// Adds or updates the feed and its entries in `target`, without saving. The feeds of one refresh batch share `index` and `models`.
    /// `known` holds models of `target` by ID that need no fetch (the library context's articles, on the main actor).
    static func merge(_ parsed: ParsedFeed, receivedAt: Date, folder: String?, index: EntryIndex, into target: ModelContext, feed: Feed,
                      models: ArticleModels, retentionDays: Int, known: [UUID: Article] = [:]) throws {
        target.insert(feed)
        feed.sourceURL = parsed.sourceURL.absoluteString
        feed.siteURL = parsed.siteURL?.absoluteString ?? feed.siteURL
        feed.iconURL = parsed.iconURL?.absoluteString ?? feed.iconURL
        if !feed.customTitle { feed.title = parsed.title }
        if let folder { feed.folder = SingleLineText.name(folder) }
        func model(_ id: UUID) throws -> Article {
            if let article = models.byID[id] ?? known[id] { return article }
            guard let article = try target.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })).first else {
                throw CocoaError(.fileReadUnknown)      // the index knows an article the store does not: apply the feed on its own
            }
            models.byID[id] = article
            return article
        }
        for entry in parsed.entries {
            let identity = entry.url?.absoluteString ?? (parsed.sourceURL.absoluteString + "|" + entry.sourceID)
            let existing = try index.articleID(identity: identity, feedID: feed.id, sourceID: entry.sourceID).map(model)
            let article = existing ?? Article(feedID: feed.id, title: entry.title, summary: entry.summary,
                                              publisher: entry.url?.host ?? "", publishedAt: entry.publishedAt ?? .distantPast, receivedAt: receivedAt)
            if existing == nil { target.insert(article); models.byID[article.id] = article; index.add(article.id) }
            let oldIdentity = article.identityKey
            if let url = entry.url {
                article.identityKey = identity
                article.originalURL = url.absoluteString
            } else if article.identityKey == nil { article.identityKey = identity }
            index.update(article.id, identity: article.identityKey, from: oldIdentity)
            article.title = entry.title
            let available = contentAvailable(article, at: receivedAt, retentionDays: retentionDays)
            if available { article.summary = entry.summary; article.imageURL = entry.imageURL?.absoluteString ?? article.imageURL }
            else { try clearContent(of: article, at: receivedAt, in: target, models: models) }
            if let date = entry.publishedAt { article.publishedAt = date }
            // A second feed must not overwrite a saved article with a shorter excerpt.
            let id = article.id
            let snapshot = models.bodiesFetched.contains(id) ? models.bodies[id]
                : try target.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == id })).first
            if available, let snapshot {
                if !entry.body.isEmpty &&
                    snapshot.coverageRaw != ContentCoverage.extracted.rawValue &&
                    (article.feedID == feed.id || entry.body.count > snapshot.text.count) {
                    snapshot.text = entry.body; snapshot.coverageRaw = entry.coverage.rawValue
                    snapshot.bodyFormatData = BodyParagraph.encode(entry.bodyParagraphs)
                }
            } else if available && !entry.body.isEmpty {
                let snapshot = ContentSnapshot(articleID: id, text: entry.body, coverage: entry.coverage, bodyParagraphs: entry.bodyParagraphs)
                target.insert(snapshot)
                if models.bodiesFetched.contains(id) { models.bodies[id] = snapshot }
            }
            if index.join(feedID: feed.id, articleID: id, sourceID: entry.sourceID) {
                let membership = FeedMembership(feedID: feed.id, articleID: id, sourceID: entry.sourceID)
                target.insert(membership)
                index.newMembershipKeys.append(membership.key)
            }
        }
    }

    /// Fetches, with one fetch each, the articles a batch's entries will update and their bodies, into `models` (#303): one fetch per
    /// entry would cost more than the save in a small context saves.
    static func prefetch(_ parsed: [(feedID: UUID, feed: ParsedFeed)], index: EntryIndex, into target: ModelContext, models: ArticleModels) throws {
        var ids: [UUID] = []
        for (feedID, feed) in parsed {
            for entry in feed.entries {
                let identity = entry.url?.absoluteString ?? (feed.sourceURL.absoluteString + "|" + entry.sourceID)
                if let id = index.articleID(identity: identity, feedID: feedID, sourceID: entry.sourceID), models.byID[id] == nil { ids.append(id) }
            }
        }
        guard !ids.isEmpty else { return }
        for article in try target.fetch(FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })) { models.byID[article.id] = article }
        for snapshot in try target.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { ids.contains($0.articleID) })) { models.bodies[snapshot.articleID] = snapshot }
        models.bodiesFetched.formUnion(ids)
    }

    /// The content of an article that left retention while a feed still carries it: as `removeContent`, for one article, in `target`.
    private static func clearContent(of article: Article, at: Date, in target: ModelContext, models: ArticleModels? = nil) throws {
        if article.contentDeletedAt == nil || !article.summary.isEmpty || article.imageURL != nil {
            article.contentDeletedAt = article.contentDeletedAt ?? at
            article.summary = ""; article.imageURL = nil
        }
        let id = article.id
        for snapshot in try target.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == id })) { target.delete(snapshot) }
        if models?.bodiesFetched.contains(id) == true { models?.bodies[id] = nil }
    }
}
