import Foundation
import Observation
import SwiftData

@Observable @MainActor public final class ReaderStore {
    public private(set) var articles: [Article] = []
    public private(set) var feeds: [Feed] = []
    public private(set) var contentRevision = 0
    public private(set) var settings: ReaderSettings?
    public var retentionDays: Int { settings?.retentionDays ?? 30 }
    public private(set) var memberships: [FeedMembership] = []
    public private(set) var notes: [Note] = []
    public private(set) var starCount = 0
    @ObservationIgnored var starredIDs: Set<UUID> = []
    @ObservationIgnored private var articleIndex: [UUID: Article] = [:]
    /// The title and summary of each article, for the list filter (`filteredIDs`). Dropped on each reload.
    @ObservationIgnored var searchTexts: [UUID: String] = [:]
    @ObservationIgnored private var feedIndex: [UUID: Feed] = [:]
    @ObservationIgnored private var publishedDates: [UUID: Date] = [:]
    @ObservationIgnored var refreshEntryIndex: EntryIndex?
    @ObservationIgnored private var articleFeeds: [UUID: Set<UUID>] = [:]
    public private(set) var articleIDs: [UUID] = []
    @ObservationIgnored private var feedArticleIDs: [UUID: [UUID]] = [:]
    @ObservationIgnored var folderIndex: [String: [UUID]] = [:]
    public private(set) var folderUnreadCounts: [String: Int] = [:]
    @ObservationIgnored private var unreadIDs: Set<UUID> = []
    public private(set) var unreadCount = 0
    public private(set) var feedUnreadCounts: [UUID: Int] = [:]
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored var context: ModelContext
    @ObservationIgnored private var saveHook: (() throws -> Void)?
    @ObservationIgnored private var reloadHook: (() throws -> Void)?
    @ObservationIgnored private var needsReload = false

    public static var schema: Schema {
        Schema([Feed.self, Article.self, ContentSnapshot.self, FeedMembership.self, ReaderSettings.self,
                Note.self])
    }

    public convenience init(url: URL, seedDemo: Bool = false, now: Date = .now) throws {
        let schema = Self.schema
        let configuration = ModelConfiguration("Reader", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        try self.init(container: container, seedDemo: seedDemo, now: now)
    }

    init(container: ModelContainer, seedDemo: Bool = false, now: Date = .now,
         saveHook: (() throws -> Void)? = nil, reloadHook: (() throws -> Void)? = nil) throws {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
        if try context.fetchCount(FetchDescriptor<ReaderSettings>()) == 0 {
            context.insert(ReaderSettings()); try context.save()
        }
        try keepOnlyOneNote(at: now)
        if seedDemo { try seedIfEmpty(now: now) }
        else { try reload() }
        try purgeExpired(at: now)
        self.saveHook = saveHook
        self.reloadHook = reloadHook
    }

    public func seedIfEmpty(now: Date = .now) throws {
        try reloadIfNeeded()
        if try context.fetchCount(FetchDescriptor<Article>()) == 0 {
            DemoLibrary.insert(into: context, at: now)
            try save()
        }
        try reload()
    }

    func reload() throws {
        needsReload = true
        refreshEntryIndex = nil
        try reloadHook?()
        contentRevision += 1
        settings = try context.fetch(FetchDescriptor<ReaderSettings>()).first
        articles = try context.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]))
        feeds = try context.fetch(FetchDescriptor<Feed>(sortBy: [SortDescriptor(\.title)]))
        memberships = try context.fetch(FetchDescriptor<FeedMembership>())
        // Ties on the timestamp break by a stable key, so equal times never reorder between launches.
        notes = try context.fetch(FetchDescriptor<Note>()).sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
        articleIndex = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        searchTexts = [:]
        feedIndex = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })
        var feedArticles: [UUID: [Article]] = [:]
        articleFeeds = [:]
        for membership in memberships { articleFeeds[membership.articleID, default: []].insert(membership.feedID) }
        for article in articles {
            for feedID in articleFeeds[article.id] ?? [] { feedArticles[feedID, default: []].append(article) }
        }
        articleIDs = articles.map(\.id)
        publishedDates = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0.publishedAt) })
        feedArticleIDs = feedArticles.mapValues { $0.map(\.id) }
        folderIndex = [:]
        for article in articles {
            let folders = Set((articleFeeds[article.id] ?? []).compactMap { feedIndex[$0]?.folder })
            for folder in folders { folderIndex[folder, default: []].append(article.id) }
        }
        refreshUnreadCounts()
        refreshStarIndex()
        needsReload = false
    }

    /// Publish only saved changes. Full reloads invalidate the lookup cache, including after a failed save or publication.
    func publishRefresh(index: EntryIndex?, titlesChanged: Bool) throws {
        needsReload = true
        try reloadHook?()
        defer { needsReload = false }
        guard let index else { return } // A 304 changes fetch metadata only.
        let previousFeeds = Dictionary(uniqueKeysWithValues: index.changedArticles.keys.map { ($0, articleFeeds[$0] ?? []) })
        memberships.append(contentsOf: index.newMemberships)
        for membership in index.newMemberships {
            articleFeeds[membership.articleID, default: []].insert(membership.feedID)
        }
        var reordered: [UUID] = []
        var feedUpdates: [UUID: [UUID]] = [:], folderUpdates: [String: [UUID]] = [:]
        for (id, article) in index.changedArticles {
            let isNew = articleIndex[id] == nil
            let date = article.publishedAt
            let moved = isNew || publishedDates[id] != date
            publishedDates[id] = date
            articleIndex[id] = article
            searchTexts[id] = nil
            if moved { reordered.append(id) }
            if isNew {
                if !article.isRead { unreadIDs.insert(id); unreadCount += 1 }
                if article.starredAt != nil { starredIDs.insert(id); starCount += 1 }
            }
            let oldFeeds = previousFeeds[id] ?? []
            let oldFolders = Set(oldFeeds.compactMap { feedIndex[$0]?.folder })
            let currentFeeds = articleFeeds[id] ?? []
            let currentFolders = Set(currentFeeds.compactMap { feedIndex[$0]?.folder })
            for feedID in currentFeeds {
                let joined = !oldFeeds.contains(feedID)
                if moved || joined { feedUpdates[feedID, default: []].append(id) }
                if joined { feedUnreadCounts[feedID, default: 0] += article.isRead ? 0 : 1 }
            }
            for folder in currentFolders {
                let joined = !oldFolders.contains(folder)
                if moved || joined { folderUpdates[folder, default: []].append(id) }
                if joined { folderUnreadCounts[folder, default: 0] += article.isRead ? 0 : 1 }
            }
        }
        if !reordered.isEmpty {
            articleIDs = orderedIDs(articleIDs, updating: reordered)
            articles = articleIDs.compactMap { articleIndex[$0] }
        }
        for (feedID, ids) in feedUpdates { feedArticleIDs[feedID] = orderedIDs(feedArticleIDs[feedID] ?? [], updating: ids) }
        for (folder, ids) in folderUpdates { folderIndex[folder] = orderedIDs(folderIndex[folder] ?? [], updating: ids) }
        if titlesChanged { feeds.sort(using: SortDescriptor(\.title)) }
        if !index.changedArticles.isEmpty { contentRevision += 1 }
        index.changedArticles.removeAll(keepingCapacity: true)
        index.newMemberships.removeAll(keepingCapacity: true)
    }

    /// Both lists are already ordered apart from the affected IDs; compare cached dates, without reading every SwiftData model again.
    private func orderedIDs(_ ids: [UUID], updating: [UUID]) -> [UUID] {
        let changed = Set(updating)
        let kept = ids.filter { !changed.contains($0) }
        let added = updating.sorted { publishedDates[$0, default: .distantPast] > publishedDates[$1, default: .distantPast] }
        var result: [UUID] = []
        result.reserveCapacity(kept.count + added.count)
        var i = 0, j = 0
        while i < kept.count && j < added.count {
            if publishedDates[kept[i], default: .distantPast] >= publishedDates[added[j], default: .distantPast] {
                result.append(kept[i]); i += 1
            } else { result.append(added[j]); j += 1 }
        }
        result.append(contentsOf: kept[i...]); result.append(contentsOf: added[j...])
        return result
    }

    func reloadIfNeeded() throws {
        if needsReload { try reload() }
    }

    func refreshStarIndex() {
        starredIDs = Set(articles.filter { $0.starredAt != nil }.map(\.id))
        starCount = starredIDs.count
    }

    public func article(id: UUID) -> Article? { articleIndex[id] }
    public func feed(id: UUID) -> Feed? { feedIndex[id] }
    public func visibleArticleIDs(feedID: UUID?, unreadOnly: Bool, keeping: UUID?) -> [UUID] {
        // Observe one array/count rather than registering every SwiftData Article.id getter.
        _ = contentRevision
        let all = articleIDs
        let values = feedID.map { feedArticleIDs[$0] ?? [] } ?? all
        guard unreadOnly else { return values }
        _ = unreadCount
        return values.filter { unreadIDs.contains($0) || $0 == keeping }
    }
    private func refreshUnreadCounts() {
        unreadCount = articles.filter { !$0.isRead }.count
        unreadIDs = Set(articles.filter { !$0.isRead }.map(\.id))
        feedUnreadCounts = feedArticleIDs.mapValues { $0.filter { unreadIDs.contains($0) }.count }
        folderUnreadCounts = folderIndex.mapValues { $0.filter { unreadIDs.contains($0) }.count }
    }
    private func updateUnreadCounts(_ article: Article, wasRead: Bool) {
        guard article.isRead != wasRead else { return }
        let delta = article.isRead ? -1 : 1
        unreadCount += delta
        if article.isRead { unreadIDs.remove(article.id) } else { unreadIDs.insert(article.id) }
        for id in articleFeeds[article.id] ?? [] { feedUnreadCounts[id, default: 0] += delta }
        let folders = Set((articleFeeds[article.id] ?? []).compactMap { feedIndex[$0]?.folder })
        for folder in folders { folderUnreadCounts[folder, default: 0] += delta }
    }

    /// Whether a subscription with this address exists (the stored form lower-cases the host).
    public func isSubscribed(to url: URL) -> Bool {
        guard let address = ArticleURL.validated(url.absoluteString)?.absoluteString else { return false }
        return feeds.contains { $0.sourceURL == address }
    }

    @discardableResult public func importFeed(_ parsed: ParsedFeed, receivedAt: Date = .now, folder: String? = nil) throws -> Feed {
        try reloadIfNeeded()
        let index = EntryIndex(articles: articles, memberships: memberships)
        do {
            let feed = try merge(parsed, receivedAt: receivedAt, folder: folder, index: index)
            try save()
            try reload()
            return feed
        } catch { rollback(); throw error }
    }

    /// Adds or updates the feed and its entries in the context, without saving. The feeds of one refresh batch share `index`.
    func merge(_ parsed: ParsedFeed, receivedAt: Date, folder: String?, index: EntryIndex) throws -> Feed {
        let feed = feeds.first { $0.sourceURL == parsed.sourceURL.absoluteString } ?? Feed(title: parsed.title, symbol: "dot.radiowaves.left.and.right")
        context.insert(feed)
        feed.sourceURL = parsed.sourceURL.absoluteString
        feed.siteURL = parsed.siteURL?.absoluteString ?? feed.siteURL
        feed.iconURL = parsed.iconURL?.absoluteString ?? feed.iconURL
        if !feed.customTitle { feed.title = parsed.title }
        if let folder { feed.folder = SingleLineText.name(folder) }
        for entry in parsed.entries {
            let identity = entry.url?.absoluteString ?? (parsed.sourceURL.absoluteString + "|" + entry.sourceID)
            let existing = index.article(identity: identity, feedID: feed.id, sourceID: entry.sourceID)
            let article = existing ?? Article(feedID: feed.id, title: entry.title, summary: entry.summary,
                                              publisher: entry.url?.host ?? "", publishedAt: entry.publishedAt ?? .distantPast, receivedAt: receivedAt)
            if existing == nil { context.insert(article); index.add(article) }
            let oldIdentity = article.identityKey
            if let url = entry.url {
                article.identityKey = identity
                article.originalURL = url.absoluteString
            } else if article.identityKey == nil { article.identityKey = identity }
            index.update(article, from: oldIdentity)
            article.title = entry.title
            let available = isContentAvailable(article, at: receivedAt)
            if available { article.summary = entry.summary; article.imageURL = entry.imageURL?.absoluteString ?? article.imageURL }
            else { _ = try removeContent(articleIDs: [article.id], at: receivedAt) }
            if let date = entry.publishedAt { article.publishedAt = date }
            // A second feed must not overwrite a saved article with a shorter excerpt.
            let id = article.id
            if available, let snapshot = try context.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == id })).first {
                if !entry.body.isEmpty &&
                    snapshot.coverageRaw != ContentCoverage.extracted.rawValue &&
                    (article.feedID == feed.id || entry.body.count > snapshot.text.count) {
                    snapshot.text = entry.body; snapshot.coverageRaw = entry.coverage.rawValue
                    snapshot.bodyFormatData = BodyParagraph.encode(entry.bodyParagraphs)
                }
            } else if available && !entry.body.isEmpty { context.insert(ContentSnapshot(articleID: id, text: entry.body, coverage: entry.coverage, bodyParagraphs: entry.bodyParagraphs)) }
            if index.join(feedID: feed.id, articleID: id, sourceID: entry.sourceID) {
                let membership = FeedMembership(feedID: feed.id, articleID: id, sourceID: entry.sourceID)
                context.insert(membership)
                index.newMemberships.append(membership)
            }
        }
        return feed
    }

    public func updateSubscription(_ feed: Feed, title: String, folder: String) throws {
        try reloadIfNeeded()
        guard let feed = self.feed(id: feed.id) else { return }
        let title = SingleLineText.name(title)
        guard !title.isEmpty else { throw FeedImportError.missingTitle }
        feed.title = title; feed.folder = SingleLineText.name(folder); feed.customTitle = true
        try save(); try reload()
    }

    public func unsubscribe(_ feed: Feed) throws {
        try reloadIfNeeded()
        guard let feed = self.feed(id: feed.id) else { return }
        for membership in memberships where membership.feedID == feed.id { context.delete(membership) }
        context.delete(feed)
        // Keep articles and bodies. Subscription removal is not article deletion.
        try save(); try reload()
    }

    public func setRead(_ article: Article, _ value: Bool) throws {
        try reloadIfNeeded()
        guard let article = self.article(id: article.id) else { return }
        guard article.isRead != value else { return }
        let wasRead = article.isRead
        article.isRead = value
        try save()
        updateUnreadCounts(article, wasRead: wasRead)
    }

    /// `discardExtractedBodies` once per library: the marker is a file in the library's folder, so a copy or a renamed folder of the library
    /// keeps it. Returns nil when it was done before;
    /// a failure leaves no marker, so it is tried again at the next start.
    @discardableResult public func discardExtractedBodiesOnce(marker: URL) throws -> Int? {
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let removed = try discardExtractedBodies()
        try Data().write(to: marker)
        return removed
    }

    /// Removes the bodies that an earlier version took from the original pages by itself when an article was opened. They can be wrong
    /// (a page's menus and counters instead of the article). The article keeps its RSS summary and the next feed refresh brings back the
    /// feed's own body. Returns how many bodies were removed.
    @discardableResult public func discardExtractedBodies() throws -> Int {
        try reloadIfNeeded()
        let raw = ContentCoverage.extracted.rawValue
        let snapshots = try context.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.coverageRaw == raw }))
        guard !snapshots.isEmpty else { return 0 }
        for snapshot in snapshots { context.delete(snapshot) }
        try save(); try reload()
        return snapshots.count
    }

    public func content(articleID: UUID, at: Date) throws -> ArticleContent? {
        try reloadIfNeeded()
        guard let article = articleIndex[articleID], isContentAvailable(article, at: at) else { return nil }
        let request = FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == articleID })
        let snapshot = try context.fetch(request).first
        let savedBody = snapshot?.text ?? ""
        let body = savedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : savedBody
        let summary = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !summary.isEmpty else { return nil }
        return ArticleContent(articleID: articleID, text: body.isEmpty ? summary : body, summary: summary,
                              coverage: body.isEmpty ? .summaryOnly : ContentCoverage(rawValue: snapshot?.coverageRaw ?? "") ?? .unavailable,
                              originalURL: article.originalURL.flatMap { ArticleURL.validated($0) },
                              bodyParagraphs: body.isEmpty ? nil : BodyParagraph.decode(snapshot?.bodyFormatData, matching: body))
    }

    public func markDisplayed(articleID: UUID, at: Date) throws {
        try reloadIfNeeded()
        guard let article = articleIndex[articleID],
              try content(articleID: articleID, at: at) != nil else { return }
        guard !article.isRead || article.firstReadAt == nil else { return }
        let wasRead = article.isRead
        article.isRead = true
        if article.firstReadAt == nil { article.firstReadAt = at }
        try save()
        updateUnreadCounts(article, wasRead: wasRead)
    }

    func save() throws {
        // Mutations must resolve models only after recovery has loaded this context.
        guard !needsReload else { throw CocoaError(.fileReadUnknown) }
        do { try saveHook?(); try context.save() }
        catch { rollback(); throw error }
    }

    func rollback() {
        context.rollback()
        // ContentRetentionTests.failedSaveRollsBackAndDoesNotNotify reproduces
        // changed registered models after a failed save on macOS 26.6.2 / Xcode 26.6.
        // Reload committed values using a fresh context for the same store.
        context = ModelContext(container)
        context.autosaveEnabled = false
        try? reload()
    }
}

public enum ReaderNavigation {
    public static func isForward(from: UUID?, to: UUID?, in ids: [UUID]) -> Bool {
        guard let from, let to, let old = ids.firstIndex(of: from), let new = ids.firstIndex(of: to) else { return true }
        return new >= old
    }
    public static func move(_ selected: UUID?, by offset: Int, in ids: [UUID]) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let selected, let index = ids.firstIndex(of: selected) else { return ids.first }
        return ids[min(max(0, index + offset), ids.count - 1)]
    }
}

/// Where an entry's article is, looked up instead of scanned (#131): built once from the library, then kept up to date by every
/// change until a full reload invalidates it. The first article with an identity wins, as the scans did.
final class EntryIndex {
    var changedArticles: [UUID: Article] = [:]
    var newMemberships: [FeedMembership] = []
    private var articleByID: [UUID: Article] = [:]
    private var articleByIdentity: [String: Article] = [:]
    private var priorArticleID: [UUID: [String: UUID]] = [:]
    private var members: [UUID: Set<UUID>] = [:]

    init(articles: [Article], memberships: [FeedMembership]) {
        for article in articles {
            articleByID[article.id] = article
            if let key = article.identityKey, articleByIdentity[key] == nil { articleByIdentity[key] = article }
        }
        for membership in memberships { _ = join(feedID: membership.feedID, articleID: membership.articleID, sourceID: membership.sourceID) }
    }
    /// The article with this identity, or the one this feed last had under the same source ID.
    func article(identity: String, feedID: UUID, sourceID: String) -> Article? {
        articleByIdentity[identity] ?? priorArticleID[feedID]?[sourceID].flatMap { articleByID[$0] }
    }
    func add(_ article: Article) { articleByID[article.id] = article }
    func update(_ article: Article, from oldIdentity: String?) {
        changedArticles[article.id] = article
        guard article.identityKey != oldIdentity else { return }
        if let oldIdentity, articleByIdentity[oldIdentity]?.id == article.id { articleByIdentity[oldIdentity] = nil }
        if let key = article.identityKey, articleByIdentity[key] == nil { articleByIdentity[key] = article }
    }
    /// True when the feed did not have the article yet.
    func join(feedID: UUID, articleID: UUID, sourceID: String) -> Bool {
        guard members[feedID, default: []].insert(articleID).inserted else { return false }
        if priorArticleID[feedID, default: [:]][sourceID] == nil { priorArticleID[feedID, default: [:]][sourceID] = articleID }
        return true
    }
}
