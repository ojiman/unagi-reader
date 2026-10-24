import AppKit
import SwiftUI
import Testing
@testable import ReaderCore
@testable import UnagiReader

/// An icon found on the home page after a refresh (#441) reaches the sidebar row at once, while the subscription stays selected: the save
/// changes the feed's model without giving the store a new list of feeds, which is what rebuilds the rows.
@Suite(EnglishLanguage()) @MainActor struct SubscriptionIconRefreshTests {
    /// The feed (no entries, no icon), its home page (naming `/icon.png`, held until released) and a record of every address asked for.
    /// No article of the subscription is listed, so only its sidebar row asks for its icon.
    private actor Site: HTTPFetching {
        private(set) var urls: [URL] = []
        private var held: [CheckedContinuation<Void, Never>] = []
        private var released = false
        func release() { released = true; held.forEach { $0.resume() }; held = [] }
        func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
            urls.append(url)
            if url.path == "/" && !released { await withCheckedContinuation { held.append($0) } }
            let body = switch url.path {
            case "/feed": "<rss><channel><title>合成購読</title><link>https://icon.example/</link></channel></rss>"
            case "/": #"<html><head><link rel="icon" href="/icon.png"></head></html>"#
            default: ""
            }
            return HTTPResponse(data: Data(body.utf8), finalURL: url, statusCode: body.isEmpty ? 404 : 200, headers: [:])
        }
    }
    private func asked(_ requests: Site, for url: URL, host: NSView) async throws -> Bool {
        for _ in 0..<300 {
            if await requests.urls.contains(url) { return true }
            host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func anIconSavedAfterARefreshReachesTheSelectedSidebarRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
        let feed = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "https://icon.example/feed")!, entries: [], skippedEntries: 0))
        let site = Site()
        let refresh = FeedRefreshController(store: store, client: FeedClient(http: site))
        let reader = ReaderView(store: store, refresh: refresh,
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"), client: site), initialScope: .feed(feed.id))
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.orderFront(nil); defer { window.close() }
        #expect(try await asked(site, for: URL(string: "https://icon.example/favicon.ico")!, host: host))   // the row is shown, with today's icon
        // The page answers after the refresh has ended and the window has settled, as a slow site does.
        await refresh.refresh(feedIDs: [feed.id])
        for _ in 0..<25 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(20)) }
        await site.release()
        await refresh.iconLookupsFinished()
        #expect(store.feed(id: feed.id)?.iconURL == "https://icon.example/icon.png")
        #expect(try await asked(site, for: URL(string: "https://icon.example/icon.png")!, host: host))
    }
}
