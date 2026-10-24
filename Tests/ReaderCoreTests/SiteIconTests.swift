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
    private func parsed(_ result: FeedFetchResult) -> ParsedFeed? { if case .modified(let parsed, _, _) = result { parsed } else { nil } }

    @Test func aFeedWithoutAnIconTakesTheOneItsHomePageNames() async throws {
        let home = site(), feed = home.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: home)), at: feed)
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png" sizes="32x32">"#)), at: home)
        #expect(parsed(try await client.fetch(url: feed, findsPageIcon: true))?.iconURL == home.appending(path: "icon.png"))
        // A page that names none settles on its /favicon.ico, so it is not read again.
        let bare = site(), bareFeed = bare.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: bare)), at: bareFeed)
        StubURLProtocol.register(.init(data: html("<title>Home</title>")), at: bare)
        #expect(parsed(try await client.fetch(url: bareFeed, findsPageIcon: true))?.iconURL == bare.appending(path: "favicon.ico"))
    }
    @Test func aMissingPageNeverStopsTheFeed() async throws {
        for reply in [StubURLProtocol.Reply(status: 404), .init(error: .timedOut), .init(data: Data(repeating: 65, count: 3 * 1024 * 1024))] {
            let home = site(), feed = home.appending(path: "feed")
            StubURLProtocol.register(.init(data: rss(site: home)), at: feed)
            StubURLProtocol.register(reply, at: home)
            let result = try #require(parsed(try await client.fetch(url: feed, findsPageIcon: true)))
            #expect(result.entries.count == 1 && result.iconURL == nil)          // nothing decided: the next refresh asks again
        }
    }
    @Test func thePageIsReadOnlyWhenTheIconIsUnknown() async throws {
        let home = site(), feed = home.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: home)), at: feed)
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png">"#)), at: home)
        #expect(parsed(try await client.fetch(url: feed))?.iconURL == nil)
        #expect(StubURLProtocol.request(at: home) == nil)
        let own = site(), ownFeed = own.appending(path: "feed")
        StubURLProtocol.register(.init(data: rss(site: own, image: own.appending(path: "logo.png").absoluteString)), at: ownFeed)
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/icon.png">"#)), at: own)
        #expect(parsed(try await client.fetch(url: ownFeed, findsPageIcon: true))?.iconURL == own.appending(path: "logo.png"))
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
        #expect(store.feeds.first?.iconURL == home.appending(path: "icon.png").absoluteString)
        // Known now: the next refresh does not read the page, and keeps the icon.
        StubURLProtocol.register(.init(data: html(#"<link rel="icon" href="/other.png">"#)), at: home)
        await refresh.refresh(feedIDs: [feed.id])
        #expect(store.feeds.first?.iconURL == home.appending(path: "icon.png").absoluteString)
    }
}
