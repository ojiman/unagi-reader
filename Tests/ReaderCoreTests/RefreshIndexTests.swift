import Foundation
import SwiftData
import Observation
import Testing
@testable import ReaderCore

@MainActor struct RefreshIndexTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)
    private func entry(_ source: String, _ path: String, _ time: Double, title: String = "Article") -> ParsedEntry {
        ParsedEntry(sourceID: source, title: title, url: URL(string: "https://article.example/" + path),
                    summary: title, body: title, coverage: .feedProvided, publishedAt: Date(timeIntervalSince1970: time))
    }
    private func apply(_ store: ReaderStore, _ feed: Feed, _ entries: [ParsedEntry], title: String = "Feed") throws {
        let source = try #require(feed.sourceURL)
        let parsed = ParsedFeed(title: title, sourceURL: try #require(URL(string: source)), entries: entries, skippedEntries: 0)
        #expect(store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source,
                                                result: .modified(parsed, etag: "v1", lastModified: nil))], at: at).isEmpty)
    }

    /// #303: a refresh batch is written through a small context, so its save does not walk the whole library or commit anything else.
    @Test func aBatchDoesNotCommitAnUnrelatedPendingChange() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1), entry("b", "b", 2)], skippedEntries: 0), receivedAt: at)
        let other = try #require(store.articles.first { $0.originalURL == "https://article.example/b" })
        let otherID = other.id
        other.isRead = true                                                         // unsaved, and not part of the refresh
        try apply(store, feed, [entry("a", "a", 1, title: "Changed"), entry("c", "c", 3)])
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.article(id: otherID)?.isRead == false)
        #expect(reopened.articles.count == 3 && reopened.articles.contains { $0.title == "Changed" })
    }

    /// The library context's instances take the batch's saved values (the shown article and feed are the same objects), and it is left
    /// with no unsaved change.
    @Test func aBatchShowsItsValuesWithoutLeavingChanges() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1)], skippedEntries: 0), receivedAt: at)
        let article = try #require(store.articles.first)
        let source = try #require(feed.sourceURL)
        let parsed = ParsedFeed(title: "Renamed", sourceURL: try #require(URL(string: source)), entries: [entry("a", "a", 1, title: "Changed")],
                                skippedEntries: 0, iconURL: URL(string: "https://feed.example/icon.png"))
        #expect(store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: source, result: .modified(parsed, etag: "v2", lastModified: nil))], at: at).isEmpty)
        #expect(store.article(id: article.id) === article && article.title == "Changed")
        #expect(store.feed(id: feed.id) === feed && feed.title == "Renamed" && feed.iconURL == "https://feed.example/icon.png" && feed.etag == "v2")
        #expect(feed.lastFetchedAt == at && !store.context.hasChanges)
    }

    /// #303: a feed that answers 200 with the same content as before writes nothing: SwiftData counts an assignment of the same value as a
    /// change, and every saved change costs (the bodies most of all).
    @Test func aFeedWithUnchangedContentWritesNothing() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let entries = [entry("a", "a", 1), entry("b", "b", 2)]
        let parsed = ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!, entries: entries, skippedEntries: 0,
                                siteURL: URL(string: "https://feed.example/"), iconURL: URL(string: "https://feed.example/icon.png"))
        let feed = try store.importFeed(parsed, receivedAt: at)
        let context = ModelContext(store.container)
        context.autosaveEnabled = false
        let feedID = feed.id
        let stored = try #require(try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedID })).first)
        _ = try store.merge(parsed, receivedAt: at.addingTimeInterval(60), folder: nil,
                            index: EntryIndex(articles: store.articles, memberships: store.memberships), into: context, feed: stored)
        #expect(!context.hasChanges)
        // A changed title is still written.
        _ = try store.merge(ParsedFeed(title: "Feed", sourceURL: parsed.sourceURL, entries: [entry("a", "a", 1, title: "Changed"), entries[1]],
                                       skippedEntries: 0, siteURL: parsed.siteURL, iconURL: parsed.iconURL), receivedAt: at.addingTimeInterval(120),
                            folder: nil, index: EntryIndex(articles: store.articles, memberships: store.memberships), into: context, feed: stored)
        #expect(context.hasChanges)
    }

    /// #346: a formatted body (links, quotes) with the same paragraphs is not written again, even when the saved JSON has its keys in
    /// another order (the encoder does not sort them); a change of format only is still written.
    @Test func aFormattedBodyWithTheSameParagraphsWritesNothing() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: at)
        let text = "最初の段落とリンク。\n\n引用の段落。"
        let paragraphs = [BodyParagraph(text: "最初の段落とリンク。", links: [BodyLink(location: 6, length: 3, url: "https://link.example/")]),
                          BodyParagraph(text: "引用の段落。", quoteDepth: 1)]
        func feed(_ paragraphs: [BodyParagraph]) -> ParsedFeed {
            ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!, entries: [
                ParsedEntry(sourceID: "a", title: "A", url: URL(string: "https://article.example/a"), summary: "要約", body: text,
                            coverage: .feedProvided, publishedAt: Date(timeIntervalSince1970: 1), bodyParagraphs: paragraphs)], skippedEntries: 0)
        }
        let stored = try store.importFeed(feed(paragraphs), receivedAt: at)
        let articleID = try #require(store.articles.first?.id)
        // The same values, saved with the keys of every object in another order.
        let reordered = #"[{"quoteDepth":0,"links":[{"url":"https://link.example/","length":3,"location":6}],"text":"最初の段落とリンク。"},{"links":[],"text":"引用の段落。","quoteDepth":1}]"#
        let snapshot = try #require(try store.context.fetch(FetchDescriptor<ContentSnapshot>(predicate: #Predicate { $0.articleID == articleID })).first)
        snapshot.bodyFormatData = Data(reordered.utf8)
        try store.context.save()
        let context = ModelContext(store.container)
        context.autosaveEnabled = false
        let feedID = stored.id
        let model = try #require(try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.id == feedID })).first)
        func merge(_ paragraphs: [BodyParagraph]) throws {
            _ = try store.merge(feed(paragraphs), receivedAt: at, folder: nil, index: EntryIndex(articles: store.articles, memberships: store.memberships),
                                into: context, feed: model)
        }
        try merge(paragraphs)
        #expect(!context.hasChanges)
        // Only the quote depth changes: the format is written and saved.
        try merge([paragraphs[0], BodyParagraph(text: "引用の段落。", quoteDepth: 2)])
        #expect(context.hasChanges)
        try context.save()
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(try reopened.content(articleID: articleID, at: at)?.bodyParagraphs.last?.quoteDepth == 2)
    }

    @Test func notModifiedKeepsTheDisplayedArticleLists() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let feed = try store.importFeed(ParsedFeed(title: "Feed", sourceURL: URL(string: "https://feed.example/rss")!,
                                                  entries: [entry("a", "a", 1)], skippedEntries: 0), receivedAt: at)
        let changes = Recorder<Bool>()
        withObservationTracking {
            _ = store.articleIDs; _ = store.contentRevision; _ = store.unreadCount; _ = store.feeds
        } onChange: { changes.add(true) }
        let later = at.addingTimeInterval(60)
        #expect(store.applyRefreshes([FetchedFeed(feedID: feed.id, sourceURL: feed.sourceURL!, result: .notModified)], at: later).isEmpty)
        #expect(feed.lastFetchedAt == later)
        #expect(changes.values.isEmpty)
    }

    // Checks PRD-01, PRD-04 and PRD-09: every committed batch is fully visible without losing reading history or Stars.
    @Test func committedBatchesMatchFullReloadAfterSharedAndMovedEntries() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let ids = try store.importSubscriptions([
            OPMLFeed(title: "A", url: URL(string: "https://a.example/rss")!, siteURL: nil, folder: "Work"),
            OPMLFeed(title: "B", url: URL(string: "https://b.example/rss")!, siteURL: nil, folder: "Work")
        ]).addedFeedIDs
        let a = try #require(store.feed(id: ids[0])), b = try #require(store.feed(id: ids[1]))
        try apply(store, a, [entry("a", "shared", 20), entry("b", "b", 10)], title: "Z")
        let shared = try #require(store.articles.first { $0.originalURL == "https://article.example/shared" })
        try store.markDisplayed(articleID: shared.id, at: at)
        try store.setStar(articleID: shared.id, isStarred: true, at: at)
        try store.saveNote(text: "Keep this note", at: at)
        #expect(store.filteredIDs(store.articleIDs, matching: "Changed").isEmpty)
        let feedChanges = Recorder<Bool>(), folderChanges = Recorder<Bool>()
        withObservationTracking {
            _ = store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil)
        } onChange: { feedChanges.add(true) }
        withObservationTracking {
            _ = store.folderArticleIDs(folder: "Work", keeping: nil)
        } onChange: { folderChanges.add(true) }
        try apply(store, b, [entry("shared-in-b", "shared", 20), entry("c", "c", 30)], title: "A")
        #expect(feedChanges.values == [true] && folderChanges.values == [true])
        try apply(store, a, [entry("a", "moved", 40, title: "Changed")], title: "Z")
        // B's entry with A's address is B's own article (decision 0067).
        #expect(store.articles.count == 4 && store.memberships.count == 4)
        #expect(store.articleIDs.first == shared.id && store.articles.map(\.id) == store.articleIDs)
        #expect(store.filteredIDs(store.articleIDs, matching: "Changed") == [shared.id])
        #expect(store.unreadCount == 3 && store.feedUnreadCounts[a.id] == 1 && store.feedUnreadCounts[b.id] == 2)
        #expect(store.folderUnreadCount(folder: "Work") == 3 && store.folderArticleIDs(folder: "Work", keeping: nil).count == 4)
        #expect(store.starredArticleIDs(keeping: nil) == [shared.id] && shared.firstReadAt == at && shared.starredAt == at)
        #expect(store.note?.text == "Keep this note")
        #expect(store.feeds.map(\.title) == ["A", "Z"])
        let ordered = store.articleIDs
        let perFeed = ids.map { store.visibleArticleIDs(feedID: $0, unreadOnly: false, keeping: nil) }
        let folder = store.folderArticleIDs(folder: "Work", keeping: nil)
        let reopened = try ReaderStore(url: library.url, now: at)
        #expect(reopened.articleIDs == ordered)
        #expect(ids.map { reopened.visibleArticleIDs(feedID: $0, unreadOnly: false, keeping: nil) } == perFeed)
        #expect(reopened.folderArticleIDs(folder: "Work", keeping: nil) == folder)
        #expect(reopened.feedUnreadCounts == store.feedUnreadCounts && reopened.folderUnreadCounts == store.folderUnreadCounts)
    }

    @Test func anotherFeedsEntryWithTheSameAddressIsANewArticleInItsLists() throws {   // decision 0067
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let ids = try store.importSubscriptions([
            OPMLFeed(title: "A", url: URL(string: "https://a.example/rss")!, siteURL: nil, folder: "Work"),
            OPMLFeed(title: "B", url: URL(string: "https://b.example/rss")!, siteURL: nil, folder: "Other")
        ]).addedFeedIDs
        let a = try #require(store.feed(id: ids[0])), b = try #require(store.feed(id: ids[1]))
        try apply(store, a, [entry("a", "shared", 20)], title: "A")
        let id = try #require(store.articleIDs.first)
        let globalChanges = Recorder<Bool>(), feedChanges = Recorder<Bool>(), folderChanges = Recorder<Bool>()
        withObservationTracking { _ = store.articleIDs } onChange: { globalChanges.add(true) }
        withObservationTracking {
            _ = store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil)
        } onChange: { feedChanges.add(true) }
        withObservationTracking {
            _ = store.folderArticleIDs(folder: "Other", keeping: nil)
        } onChange: { folderChanges.add(true) }
        try apply(store, b, [entry("b", "shared", 20)], title: "B")
        #expect(globalChanges.values == [true] && feedChanges.values == [true] && folderChanges.values == [true])
        let own = try #require(store.visibleArticleIDs(feedID: b.id, unreadOnly: false, keeping: nil).first)
        #expect(own != id && Set(store.articleIDs) == [id, own] && store.visibleArticleIDs(feedID: a.id, unreadOnly: false, keeping: nil) == [id])
        #expect(store.folderArticleIDs(folder: "Other", keeping: nil) == [own])
        #expect(store.unreadCount == 2 && store.feedUnreadCounts == [a.id: 1, b.id: 1])
        #expect(store.folderUnreadCounts == ["Work": 1, "Other": 1])
    }

    @Test func subscriptionChangesInvalidateMembershipLookups() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let source = URL(string: "https://a.example/rss")!
        let id = try #require(store.importSubscriptions([OPMLFeed(title: "A", url: source, siteURL: nil, folder: "Old")]).addedFeedIDs.first)
        let feed = try #require(store.feed(id: id))
        try apply(store, feed, [entry("a", "a", 1)])
        try store.moveFeed(id: id, toFolder: "New")
        try apply(store, feed, [entry("b", "b", 2)])
        #expect(store.folderArticleIDs(folder: "Old", keeping: nil).isEmpty)
        #expect(store.folderUnreadCount(folder: "New") == 2)
        try store.unsubscribe(feed)
        let newID = try #require(store.importSubscriptions([OPMLFeed(title: "A", url: source, siteURL: nil, folder: "Again")]).addedFeedIDs.first)
        try apply(store, try #require(store.feed(id: newID)), [entry("a", "a", 1)])
        #expect(store.articles.count == 2 && store.memberships.count == 1)
        #expect(store.feedUnreadCounts[newID] == 1 && store.folderUnreadCount(folder: "Again") == 1)
    }
}
