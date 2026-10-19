import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Reading subscriptions from an OPML file (decision 0041).
// Checks PRD-15 (specification 7).
@Suite(EnglishLanguage()) @MainActor struct OPMLImportTests {
    private func parse(_ opml: String) throws -> OPMLDocument { try OPMLParser.parse(Data(opml.utf8)) }
    private func wrap(_ body: String) -> String { #"<?xml version="1.0"?><opml version="2.0"><head><title>Subscriptions</title></head><body>\#(body)</body></opml>"# }

    // MARK: The parser

    @Test func feedsFoldersAndNamesAreRead() throws {
        let document = try parse(wrap("""
        <outline type="rss" text="Alone" xmlUrl="https://alone.example/feed" htmlUrl="https://alone.example/"/>
        <outline text="Tech"><outline type="rss" text="Text name" title="Title name" xmlUrl="https://tech.example/rss"/>
        <outline type="rss" text="Atom one" xmlUrl="https://tech.example/atom"/></outline>
        """))
        #expect(document.feeds.map(\.url.absoluteString) == ["https://alone.example/feed", "https://tech.example/rss", "https://tech.example/atom"])
        #expect(document.feeds.map(\.folder) == ["", "Tech", "Tech"])
        #expect(document.feeds.map(\.title) == ["Alone", "Title name", "Atom one"])                   // title first, then text
        #expect(document.feeds[0].siteURL?.absoluteString == "https://alone.example/" && document.feeds[1].siteURL == nil)
        #expect(document.skipped == 0)
    }
    @Test func deeperFoldersAreFlattenedToTheTopOneAndSpecialNamesMeanUnfiled() throws {
        let document = try parse(wrap("""
        <outline text="News"><outline text="World"><outline text="Deep"><outline type="rss" text="A" xmlUrl="https://a.example/f"/></outline></outline></outline>
        <outline text="未分類"><outline text="B" xmlUrl="https://b.example/f"/></outline>
        <outline text="  "><outline text="C" xmlUrl="https://c.example/f"/></outline>
        <outline text="Multi
        line"><outline text="D" xmlUrl="https://d.example/f"/></outline>
        """))
        #expect(document.feeds.map(\.folder) == ["News", "", "", "Multi line"])                       // one level of folders, as in the app
    }
    @Test func anOutlineWithoutAFeedAddressIsOnlyAFolderAndBadAddressesAreCounted() throws {
        let document = try parse(wrap("""
        <outline text="Empty folder"/>
        <outline text="x" xmlUrl="ftp://old.example/feed"/><outline text="y" xmlUrl="https://u:p@host.example/f"/><outline text="z" xmlUrl=""/>
        <outline text="Good" xmlUrl="https://good.example/f"/>
        """))
        #expect(document.feeds.map(\.title) == ["Good"] && document.skipped == 3)
    }
    @Test func theSameAddressTwiceIsOneFeedAndTheAttributeNameIsReadWhateverItsCase() throws {
        let document = try parse(wrap("""
        <outline text="One" xmlUrl="https://same.example/f"/>
        <outline text="Folder"><outline text="Two" XMLURL="https://same.example/f"/><outline text="Three" xmlurl="https://other.example/f"/></outline>
        """))
        #expect(document.feeds.map(\.title) == ["One", "Three"] && document.skipped == 0 && document.repeated == 1)
    }
    @Test func aPlainHTTPAddressIsUpgradedToHTTPSBecauseTheAppCannotFetchHTTP() throws {
        let document = try parse(wrap("""
        <outline text="Old" xmlUrl="http://old.example/atom.xml" htmlUrl="http://old.example/"/>
        <outline text="Also https" xmlUrl="https://old.example/atom.xml"/>
        <outline text="Port" xmlUrl="http://port.example:8080/feed"/>
        <outline text="Secure" xmlUrl="https://secure.example/feed"/>
        """))
        #expect(document.feeds.map(\.url.absoluteString) == ["https://old.example/atom.xml", "http://port.example:8080/feed", "https://secure.example/feed"])
        #expect(document.feeds[0].siteURL?.absoluteString == "https://old.example/")             // the site too, for the icon
        #expect(document.upgraded == 1 && document.repeated == 1)                                  // the http and https forms are one feed; a port is left as it is
    }
    @Test func aNameFallsBackToTheHost() throws {
        #expect(try parse(wrap(#"<outline xmlUrl="https://nameless.example/f"/>"#)).feeds.first?.title == "nameless.example")
    }
    @Test func aDoctypeIsFineButEntitiesAndOtherDocumentsAreRefused() throws {
        #expect(try parse(#"<?xml version="1.0"?><!DOCTYPE opml><opml version="1.0"><body><outline text="A" xmlUrl="https://a.example/f"/></body></opml>"#).feeds.count == 1)
        #expect(throws: OPMLError.entities) { try parse(#"<!DOCTYPE opml [<!ENTITY x "y">]><opml><body><outline text="&x;" xmlUrl="https://a.example/f"/></body></opml>"#) }
        #expect(throws: OPMLError.notOPML) { try parse("<rss><channel><title>feed</title></channel></rss>") }
        #expect(throws: OPMLError.invalidXML) { try parse("<opml><body><outline") }
        #expect(throws: OPMLError.notOPML) { try parse("") }
    }
    @Test func nestingBeyondTheLimitHasItsOwnSentence() throws {
        let deep = String(repeating: #"<outline text="f">"#, count: OPMLParser.maximumDepth + 1) + String(repeating: "</outline>", count: OPMLParser.maximumDepth + 1)
        #expect(throws: OPMLError.tooDeep) { try parse(wrap(deep)) }
        #expect(OPMLError.tooDeep.localizedDescription == "The file is nested too deeply (maximum 64 levels).")
    }
    @Test func entitiesAreRefusedWhateverTheEncodingAndNamesAreCapped() throws {
        // UTF-7 hides "<!ENTITY" from a scan of the text, but the parser reports every declaration it meets.
        let utf7 = #"<?xml version="1.0" encoding="UTF-7"?><+ACE-DOCTYPE opml +AFs-<+ACE-ENTITY x +ACI-EXPANDED+ACI-+AD4-+AF0-+AD4-<opml><body><outline text=+ACI-+ACY-x+ADs-+ACI- xmlUrl=+ACI-https://a.example/f+ACI-/+AD4-</body></opml>"#
        #expect(throws: OPMLError.entities) { try OPMLParser.parse(Data(utf7.utf8)) }
        let long = String(repeating: "あ", count: 5_000)
        let document = try parse(wrap(#"<outline text="\#(long)"><outline text="\#(long)" xmlUrl="https://a.example/f"/></outline>"#))
        #expect(document.feeds[0].title.count == OPMLParser.maximumNameLength && document.feeds[0].folder.count == OPMLParser.maximumNameLength)
    }
    @Test func aFolderNameIsTheFirstNonEmptyOfTextAndTitle() throws {
        let document = try parse(wrap(#"<outline text="" title="Tech"><outline text="A" xmlUrl="https://a.example/f"/></outline>"#))
        #expect(document.feeds.first?.folder == "Tech")
    }
    @Test func hugeFilesAndTooManyFeedsAreRefused() throws {
        #expect(throws: OPMLError.tooLarge) { try OPMLParser.parse(Data(repeating: 32, count: 5 * 1024 * 1024 + 1)) }
        let many = (0...OPMLParser.maximumFeeds).map { #"<outline text="f\#($0)" xmlUrl="https://h\#($0).example/f"/>"# }.joined()
        #expect(throws: OPMLError.tooMany) { try parse(wrap(many)) }
    }
    @Test func anEmptyBodyIsNotAnError() throws {
        let document = try parse(wrap(""))
        #expect(document.feeds.isEmpty && document.skipped == 0)
    }

    // MARK: The store

    private func feed(_ title: String, _ url: String, folder: String = "", site: String? = nil) -> OPMLFeed {
        OPMLFeed(title: title, url: URL(string: url)!, siteURL: site.flatMap { URL(string: $0) }, folder: folder)
    }

    @Test func importedSubscriptionsAppearAtOnceWithTheirFoldersAndSurviveReopening() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let result = try store.importSubscriptions([feed("A", "https://a.example/f", folder: " 技術 ", site: "https://a.example/"), feed("B", "https://b.example/f")])
        #expect(result.addedFeedIDs.count == 2 && result.alreadySubscribed == 0)
        #expect(store.feeds.map(\.title).sorted() == ["A", "B"])
        let a = try #require(store.feeds.first { $0.title == "A" })
        #expect(a.folder == "技術" && a.sourceURL == "https://a.example/f" && a.siteURL == "https://a.example/" && !a.customTitle)
        let reopened = try ReaderStore(url: library.url)
        #expect(reopened.feeds.count == 2 && reopened.feed(id: a.id)?.folder == "技術")
    }
    @Test func aSubscriptionThatExistsIsNeitherDuplicatedNorMoved() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let parsed = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: URL(string: "https://Old.example/f")!)
        let existing = try store.importFeed(parsed, folder: "Mine")
        let result = try store.importSubscriptions([feed("Old", "https://old.example/f", folder: "Theirs"), feed("New", "https://new.example/f")])
        #expect(result.addedFeedIDs.count == 1 && result.alreadySubscribed == 1)
        #expect(store.feeds.count == 2 && existing.folder == "Mine")                                   // the host's case does not make a second subscription
    }
    @Test func aFailedSaveAddsNothingAndSaysSo() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "opml-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: url.appending(path: "Reader.store"), cloudKitDatabase: .none)])
        let failSave = TestBox(false)
        let store = try ReaderStore(container: container, now: .now, saveHook: { if failSave.value { throw CocoaError(.fileWriteUnknown) } })
        failSave.value = true
        #expect(throws: (any Error).self) { try store.importSubscriptions([feed("A", "https://a.example/f")]) }
        #expect(store.feeds.isEmpty)                                                                  // nothing half-added
        failSave.value = false
        #expect(try store.importSubscriptions([feed("A", "https://a.example/f")]).addedFeedIDs.count == 1)
    }
    @Test func theStoreDoesNotTrustTheCallerToNormalizeAddresses() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        _ = try store.importSubscriptions([feed("A", "https://a.example/f")])
        let result = try store.importSubscriptions([feed("A again", "https://A.example/f#frag"), feed("Old", "ftp://x.example/f"), feed("Good", "https://g.example/f")])
        #expect(result.addedFeedIDs.count == 1 && result.alreadySubscribed == 1 && result.rejected == 1)
        #expect(store.feeds.map(\.sourceURL).sorted { ($0 ?? "") < ($1 ?? "") } == ["https://a.example/f", "https://g.example/f"])
    }
    /// A store whose list reload fails while `failReload.value` is true.
    private final class ReloadSwitch: @unchecked Sendable { nonisolated(unsafe) var failing = false }
    private func storeWithReloadSwitch(_ directory: URL, _ reloadSwitch: ReloadSwitch) throws -> ReaderStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = ReaderStore.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Reader", schema: schema, url: directory.appending(path: "Reader.store"), cloudKitDatabase: .none)])
        return try ReaderStore(container: container, now: .now, saveHook: nil, reloadHook: { if reloadSwitch.failing { throw CocoaError(.fileReadUnknown) } })
    }

    @Test func aReloadThatFailsAfterASuccessfulSaveStillCountsTheFeedsAsAdded() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "opml-reload-" + UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reloadSwitch = ReloadSwitch()
        let store = try storeWithReloadSwitch(directory, reloadSwitch)
        reloadSwitch.failing = true
        let result = try store.importSubscriptions([feed("A", "https://a.example/f")])
        #expect(result.addedFeedIDs.count == 1 && result.listRefreshFailed)                            // saved, so not reported as a failure
        reloadSwitch.failing = false
        #expect(try ReaderStore(url: directory.appending(path: "Reader.store")).feeds.count == 1)
    }
    @Test func theReportSaysSoWhenTheListCouldNotBeLoadedAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "opml-reload2-" + UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reloadSwitch = ReloadSwitch()
        let store = try storeWithReloadSwitch(directory, reloadSwitch)
        let opml = try file(wrap(#"<outline text="B" xmlUrl="https://b.example/f"/>"#))
        defer { try? FileManager.default.removeItem(at: opml) }
        reloadSwitch.failing = true
        let report = await OPMLImporter(store: store).importFile(at: opml)
        #expect(report.title == "Subscriptions added: 1" && report.message == "The list could not be refreshed. Reopen the app." && report.addedFeedIDs.isEmpty)
    }
    @Test func importingNothingChangesNothing() throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let result = try store.importSubscriptions([])
        #expect(result.addedFeedIDs.isEmpty && result.alreadySubscribed == 0 && store.feeds.isEmpty)
    }

    // MARK: The importer (the file, the store and the words for the person)

    private func file(_ opml: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "opml-test-" + UUID().uuidString + ".opml")
        try Data(opml.utf8).write(to: url)
        return url
    }

    @Test func aFileBecomesSubscriptionsAndAPlainReport() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let url = try file(wrap("""
        <outline text="Tech"><outline text="A" xmlUrl="https://a.example/f"/><outline text="B" xmlUrl="https://b.example/f"/></outline>
        <outline text="Bad" xmlUrl="ftp://c.example/f"/><outline text="A again" xmlUrl="https://a.example/f"/>
        """))
        defer { try? FileManager.default.removeItem(at: url) }
        let report = await OPMLImporter(store: store).importFile(at: url)
        #expect(report.title == "Subscriptions added: 2" && report.addedFeedIDs.count == 2)                   // the result is the title
        #expect(report.message == "• Failed: 1")                                // only what is not plain success; the repeated A is one feed, not "already subscribed"
        let clean = OPMLImporter.report(added: [UUID()], alreadySubscribed: 0, unusable: 0)
        #expect(clean.title == "Subscriptions added: 1" && clean.message.isEmpty)                            // all well: nothing more to say
        let mixed = OPMLImporter.report(added: [UUID()], alreadySubscribed: 2, unusable: 1, upgraded: 9)
        #expect(mixed.message == "• Already subscribed: 2\n• Changed to HTTPS: 9\n• Failed: 1")
        #expect(store.feeds.count == 2 && Set(store.feeds.map(\.folder)) == ["Tech"])
    }
    @Test func theReportSaysWhatHappenedWhenNothingWasAdded() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let body = wrap(#"<outline text="A" xmlUrl="https://a.example/f"/>"#)
        let first = try file(body), empty = try file(wrap(""))
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: empty) }
        _ = await OPMLImporter(store: store).importFile(at: first)
        let again = await OPMLImporter(store: store).importFile(at: first)
        #expect(again.addedFeedIDs.isEmpty && again.title == "No new subscriptions" && again.message == "• Already subscribed: 1")
        let none = await OPMLImporter(store: store).importFile(at: empty)
        #expect(none.addedFeedIDs.isEmpty && none.title == "No subscriptions were found in this file" && none.message.isEmpty)
    }
    @Test func onlyARegularFileIsReadAndAtMostTheLimit() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let importer = OPMLImporter(store: store)
        let directory = FileManager.default.temporaryDirectory.appending(path: "opml-special-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipe = directory.appending(path: "pipe.opml")
        #expect(mkfifo(pipe.path, 0o600) == 0)
        #expect(await importer.importFile(at: pipe).message == "The file could not be opened.")             // a pipe would wait for ever
        #expect(await importer.importFile(at: URL(fileURLWithPath: "/dev/zero")).message == "The file could not be opened.")
        #expect(await importer.importFile(at: directory).message == "The file could not be opened.")
        let big = directory.appending(path: "big.opml"), link = directory.appending(path: "link.opml")
        try Data(repeating: 32, count: OPMLParser.maximumBytes + 10).write(to: big)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: big)
        #expect(await importer.importFile(at: link).message == "The file is too large (maximum 5 MB).")       // the size of the link is not the size of the file
        let small = directory.appending(path: "small.opml"), smallLink = directory.appending(path: "small-link.opml")
        try Data(wrap(#"<outline text="A" xmlUrl="https://a.example/f"/>"#).utf8).write(to: small)
        try FileManager.default.createSymbolicLink(at: smallLink, withDestinationURL: small)
        #expect(await importer.importFile(at: smallLink).addedFeedIDs.count == 1)
    }
    @Test func aFileThatCannotBeUsedGivesAReasonAndChangesNothing() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let importer = OPMLImporter(store: store)
        let rss = try file("<rss><channel><title>x</title></channel></rss>")
        defer { try? FileManager.default.removeItem(at: rss) }
        let notOPML = await importer.importFile(at: rss)
        #expect(notOPML.title == "Could not import the OPML file" && notOPML.message == "This is not an OPML file." && notOPML.addedFeedIDs.isEmpty)
        let missing = await importer.importFile(at: FileManager.default.temporaryDirectory.appending(path: "no-such-" + UUID().uuidString + ".opml"))
        #expect(missing.title == "Could not import the OPML file" && !missing.message.isEmpty)
        let huge = FileManager.default.temporaryDirectory.appending(path: "opml-huge-" + UUID().uuidString + ".opml")
        try Data(repeating: 32, count: OPMLParser.maximumBytes + 1).write(to: huge)
        defer { try? FileManager.default.removeItem(at: huge) }
        #expect(await importer.importFile(at: huge).message == "The file is too large (maximum 5 MB).")
        #expect(store.feeds.isEmpty)
    }

    // MARK: The whole flow (choose, import, report, then fetch the new subscriptions)

    private func flow(_ store: ReaderStore, urls: [URL], choose: @escaping @MainActor () async -> URL?) -> OPMLImportFlow {
        let client = FeedClient(http: HTTPClient(protocolClasses: [StubURLProtocol.self]))
        for url in urls { StubURLProtocol.register(.init(data: Data(FeedParserTests.rss.utf8)), at: url) }
        return OPMLImportFlow(store: store, refresh: FeedRefreshController(store: store, client: client), chooseFile: choose)
    }

    @Test func choosingAFileAddsTheSubscriptionsThenFetchesTheirArticles() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let address = "https://\(UUID().uuidString.lowercased()).example/feed"
        let opml = try file(wrap(#"<outline text="Tech"><outline text="A" xmlUrl="\#(address)"/></outline>"#))
        defer { try? FileManager.default.removeItem(at: opml) }
        let flow = flow(store, urls: [URL(string: address)!], choose: { opml })
        await flow.start()
        #expect(flow.report?.title == "Subscriptions added: 1")
        let added = try #require(store.feeds.first)
        #expect(added.folder == "Tech" && added.lastFetchedAt != nil && !store.articles.isEmpty)       // the articles came, so the person is not left with empty rows
        flow.dismissReport()
        #expect(flow.report == nil)
    }
    @Test func newSubscriptionsWaitForARefreshThatIsAlreadyRunningThenAreFetched() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let busy = URL(string: "https://\(UUID().uuidString.lowercased()).example/busy")!
        let fresh = URL(string: "https://\(UUID().uuidString.lowercased()).example/fresh")!
        let parsedBusy = try FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: busy)
        _ = try store.importFeed(parsedBusy)
        StubURLProtocol.register(.init(data: Data(FeedParserTests.rss.utf8)), at: busy)
        StubURLProtocol.register(.init(data: Data(FeedParserTests.rss.utf8)), at: fresh)
        let gate = SlowGate()
        let http = GatedHTTP(blocked: busy, gate: gate, inner: HTTPClient(protocolClasses: [StubURLProtocol.self]))
        let refresh = FeedRefreshController(store: store, client: FeedClient(http: http))
        let opml = try file(wrap(#"<outline text="N" xmlUrl="\#(fresh.absoluteString)"/>"#))
        defer { try? FileManager.default.removeItem(at: opml) }
        let flow = OPMLImportFlow(store: store, refresh: refresh, chooseFile: { opml })
        let running = Task { await refresh.refresh() }
        while !refresh.refreshing { await Task.yield() }
        let importing = Task { await flow.start() }
        while flow.report == nil { await Task.yield() }
        let added = try #require(store.feeds.first { $0.sourceURL == fresh.absoluteString })
        #expect(added.lastFetchedAt == nil)                                                           // the running refresh does not take it, so it waits
        await gate.open(); await running.value; await importing.value
        #expect(try #require(store.feed(id: added.id)).lastFetchedAt != nil)
    }
    @Test func cancellingTheFilePanelDoesNothing() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let flow = flow(store, urls: [], choose: { nil })
        await flow.start()
        #expect(flow.report == nil && store.feeds.isEmpty && !flow.choosing)
    }
    @Test func aSecondRequestWhileThePanelIsOpenIsIgnored() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let gate = SlowGate()
        let asked = Recorder<Int>()
        let flow = flow(store, urls: [], choose: { asked.add(1); await gate.wait(); return nil })
        let first = Task { await flow.start() }
        while !flow.choosing { await Task.yield() }
        await flow.start()                                                                           // returns at once
        #expect(asked.values.count == 1)
        await gate.open(); await first.value
        #expect(!flow.choosing)
    }
}

/// Holds back one address until the test opens the gate; every other address goes to the stub.
struct GatedHTTP: HTTPFetching {
    let blocked: URL
    let gate: SlowGate
    let inner: HTTPClient
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
        if url == blocked { await gate.wait() }
        return try await inner.fetch(url: url, headers: headers, maximumBytes: maximumBytes)
    }
}
