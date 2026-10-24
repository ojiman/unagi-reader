import Foundation
import Testing
@testable import ReaderCore

/// A feed without an icon of its own takes the one its site's home page names, as browsers do (#441).
@MainActor struct SiteIconTests {
    private let page = URL(string: "https://blog.example/")!
    private func icon(_ head: String, base: URL? = nil) -> String? {
        FeedDiscovery.iconURL(inHTML: Data("<html><head>\(head)</head></html>".utf8), baseURL: base ?? page)?.absoluteString
    }

    @Test func theSizeNearestTheRowIsChosenAndReferencesAreDecoded() {
        // The Futurism page: a WordPress address with `&#038;`, in two sizes and as a touch icon.
        let head = """
        <link rel="icon" href="https://blog.example/icon.png?quality=85&#038;w=192" sizes="192x192" />
        <link rel="icon" href="https://blog.example/icon.png?quality=85&#038;w=32" sizes="32x32" />
        <link rel="apple-touch-icon" href="https://blog.example/icon.png?quality=85&#038;w=180" />
        """
        #expect(icon(head) == "https://blog.example/icon.png?quality=85&w=32")
        #expect(icon(#"<link rel="icon" href="/s.png" sizes="16x16"><link rel="icon" href="/m.png" sizes="48x48">"#) == "https://blog.example/m.png")
        #expect(icon(#"<link rel="icon" href="/s.png" sizes="16x16">"#) == "https://blog.example/s.png")
    }
    @Test func relIsReadLikeTheBrowsersDo() {
        #expect(icon(#"<link rel="Shortcut Icon" href="favicon.png">"#, base: URL(string: "https://blog.example/posts/")!) == "https://blog.example/posts/favicon.png")
        #expect(icon(#"<link rel="apple-touch-icon-precomposed" href="/touch.png">"#) == "https://blog.example/touch.png")
        #expect(icon(#"<link rel="icon" href="/plain.ico"><link rel="apple-touch-icon" href="/touch.png">"#) == "https://blog.example/plain.ico")
        #expect(icon(#"<link rel="stylesheet" href="/icon.css"><link rel="mask-icon" href="/mask.svg">"#) == nil)
    }
    @Test func onlyImagesTheAppCanShowAndSafeAddressesAreTaken() {
        #expect(icon(#"<link rel="icon" type="image/svg+xml" href="/i"><link rel="icon" href="/v.svg"><link rel="icon" href="/p.png">"#) == "https://blog.example/p.png")
        #expect(icon(#"<link rel="icon" href="http://blog.example/i.png">"#) == nil)            // a secure page never leads to plain http
        #expect(icon(#"<link rel="icon" href="javascript:alert(1)"><link rel="icon" href="data:image/png;base64,AA==">"#) == nil)
        #expect(icon(#"<link rel="icon" href="  ">"#) == nil)
    }

    // MARK: The client

    private func site() -> URL { URL(string: "https://\(UUID().uuidString.lowercased()).example/")! }
    private var client: FeedClient { FeedClient(http: HTTPClient(protocolClasses: [StubURLProtocol.self])) }
    private func rss(site: URL, image: String? = nil) -> Data {
        Data("<rss><channel><title>T</title><link>\(site.absoluteString)</link>\(image.map { "<image><url>\($0)</url></image>" } ?? "")<item><guid>1</guid><title>A</title></item></channel></rss>".utf8)
    }
    private func html(_ head: String) -> Data { Data("<!doctype html><html><head>\(head)</head><body>home</body></html>".utf8) }
    private func feed(site: URL, image: String? = nil) throws -> ParsedFeed { try FeedParser.parse(rss(site: site, image: image), sourceURL: site.appending(path: "feed")) }

    @Test func aFeedWithoutAnIconTakesTheOneItsHomePageNames() async throws {
        let home = site()
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png" sizes="32x32">"#)), at: home)
        #expect(await client.pageIcon(for: try feed(site: home)) == home.appending(path: "icon.png"))
        // A page that names none settles on its /favicon.ico, so it is not read again.
        let bare = site()
        StubURLProtocol.register(.init(data: html("<title>Home</title>")), at: bare)
        #expect(await client.pageIcon(for: try feed(site: bare)) == bare.appending(path: "favicon.ico"))
    }
    @Test func aPageThatCannotBeReadDecidesNothing() async throws {
        for reply in [StubURLProtocol.Reply(status: 404), .init(error: .timedOut), .init(data: Data(repeating: 65, count: 3 * 1024 * 1024))] {
            let home = site()
            StubURLProtocol.register(reply, at: home)
            #expect(await client.pageIcon(for: try feed(site: home)) == nil)        // the next refresh asks again
        }
    }
    @Test func aRefreshReadsThePageOnlyWhenTheIconIsUnknown() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: .now)
        let own = site(), ownURL = own.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: own, image: own.appending(path: "logo.png").absoluteString)), at: ownURL)
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png">"#)), at: own)
        let ownFeed = try store.importFeed(FeedParser.parse(rss(site: own), sourceURL: ownURL))
        let refresh = FeedRefreshController(store: store, client: client)
        await refresh.refresh(feedIDs: [ownFeed.id])
        await refresh.iconLookupsFinished()
        #expect(store.feed(id: ownFeed.id)?.iconURL == own.appending(path: "logo.png").absoluteString)
        #expect(StubURLProtocol.request(at: own) == nil)                         // the feed's own icon comes first
    }
    @Test func aSiteAddressGivesItsIconWithItsFeed() async throws {
        let home = site(), feed = home.appending(path: "feed")
        StubURLProtocol.register(.init(data: html(#"<link rel="alternate" type="application/rss+xml" href="/feed"><link rel="icon" href="/icon.png">"#)), at: home)
        StubURLProtocol.register(.init(data: rss(site: home)), at: feed)
        #expect(try await client.fetchOrDiscover(url: home).parsed.iconURL == home.appending(path: "icon.png"))
    }
    @Test func aRefreshKeepsTheIconItFound() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: .now)
        let home = site(), url = home.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: home)), at: url)
        let feed = try store.importFeed(FeedParser.parse(rss(site: home), sourceURL: url))
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png">"#)), at: home)
        let refresh = FeedRefreshController(store: store, client: client)
        await refresh.refresh(feedIDs: [feed.id])
        await refresh.iconLookupsFinished()
        #expect(store.feeds.first?.iconURL == home.appending(path: "icon.png").absoluteString)
        // Known now: the next refresh does not read the page, and keeps the icon.
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/other.png">"#)), at: home)
        await refresh.refresh(feedIDs: [feed.id])
        await refresh.iconLookupsFinished()
        #expect(store.feeds.first?.iconURL == home.appending(path: "icon.png").absoluteString)
    }
    @Test func aSlowHomePageNeverHoldsBackTheRefresh() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url, now: .now)
        let list = (0..<4).map { OPMLFeed(title: "F\($0)", url: URL(string: "https://p\($0).example/feed")!, siteURL: nil, folder: "") }
        let ids = try store.importSubscriptions(list).addedFeedIDs
        let pages = HeldPages()
        let refresh = FeedRefreshController(store: store, client: FeedClient(http: pages))
        let running = Task { await refresh.refresh(feedIDs: ids) }
        // Four feeds and three request slots: the fourth starts only when a slot is free, so all four articles mean the held pages took none.
        let deadline = ContinuousClock.now + .seconds(30)
        while store.articles.count < 4 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(store.articles.count == 4 && store.feeds.allSatisfy { $0.iconURL == nil })
        await pages.release()
        await running.value
        await refresh.iconLookupsFinished()
        #expect(store.feeds.allSatisfy { $0.iconURL == "https://\(URL(string: $0.sourceURL ?? "")?.host ?? "")/icon.png" })
    }
}

/// Feeds answer at once; home pages wait until they are released, then name `/icon.png`.
private actor HeldPages: HTTPFetching {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func release() { released = true; held.forEach { $0.resume() }; held = [] }
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
        let host = url.host ?? ""
        if url.path == "/" {
            if !released { await withCheckedContinuation { held.append($0) } }
            return HTTPResponse(data: Data(#"<html><head><link rel="icon" href="/icon.png"></head></html>"#.utf8), finalURL: url, statusCode: 200, headers: [:])
        }
        let xml = "<rss><channel><title>\(host)</title><item><guid>\(host)</guid><title>A</title></item></channel></rss>"
        return HTTPResponse(data: Data(xml.utf8), finalURL: url, statusCode: 200, headers: [:])
    }
}
