import AppKit
import SwiftUI
import Testing
@testable import ReaderCore
@testable import UnagiReader

/// An icon found on the home page after a refresh (#441) reaches the selected sidebar row at once, as it reaches the article list: the
/// subscription and its article stay selected. A review of #443 reported the selected row stale from window captures; it was not
/// reproduced, and this test guards it.
@Suite(EnglishLanguage()) @MainActor struct SubscriptionIconRefreshTests {
    /// The feed (one entry, no icon), its home page (naming `/icon.png`, held until released) and a magenta icon.
    private actor Site: HTTPFetching {
        private var held: [CheckedContinuation<Void, Never>] = []
        private var released = false
        func release() { released = true; held.forEach { $0.resume() }; held = [] }
        func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
            if url.path == "/" && !released { await withCheckedContinuation { held.append($0) } }
            let body: Data? = switch url.path {
            case "/feed": Data(#"<rss><channel><title>合成購読</title><link>https://icon.example/</link><item><guid>1</guid><title>合成記事</title><description>合成要約</description></item></channel></rss>"#.utf8)
            case "/": Data(#"<html><head><link rel="icon" href="/icon.png"></head></html>"#.utf8)
            case "/icon.png": SubscriptionIconRefreshTests.magenta
            default: nil
            }
            return HTTPResponse(data: body ?? Data(), finalURL: url, statusCode: body == nil ? 404 : 200, headers: [:])
        }
    }
    nonisolated static let magenta: Data = {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<32 { for y in 0..<32 { image.setColor(NSColor(deviceRed: 1, green: 0, blue: 1, alpha: 1), atX: x, y: y) } }
        return image.representation(using: .png, properties: [:])!
    }()

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
    private func outerSplit(in view: NSView) -> NSSplitViewController? {
        if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController, controller.splitViewItems.count == 3 { return controller }
        return view.subviews.lazy.compactMap { outerSplit(in: $0) }.first
    }
    private func pump(_ host: NSView, _ milliseconds: Int) async throws {
        var left = milliseconds
        while left > 0 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)); left -= 10 }
    }
    /// Whether the column's drawn pixels include the icon's magenta.
    private func showsIcon(_ column: NSView) -> Bool {
        guard let image = column.bitmapImageRepForCachingDisplay(in: column.bounds) else { return false }
        column.cacheDisplay(in: column.bounds, to: image)
        for x in stride(from: 0, to: image.pixelsWide, by: 3) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 3) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.75 && color.blueComponent > 0.75 && color.greenComponent < 0.45 { return true }
            }
        }
        return false
    }

    @Test func anIconSavedAfterARefreshReachesTheSelectedSidebarRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
        let site = Site()
        let client = FeedClient(http: site)
        guard case .modified(let parsed, _, _) = try await client.fetch(url: URL(string: "https://icon.example/feed")!) else { Issue.record("no feed"); return }
        let feed = try store.importFeed(parsed)
        let refresh = FeedRefreshController(store: store, client: client)
        let reader = ReaderView(store: store, refresh: refresh,
            imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"), client: site), initialScope: .feed(feed.id))
        let host = NSHostingView(rootView: reader)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.toolbar = NSToolbar(identifier: "synthetic-subscription-icon")
        window.contentView = host
        window.orderFront(nil); defer { window.close() }
        try await pump(host, 800)
        let table = try #require(find(NativeArticleList.Table.self, in: host))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await pump(host, 600)
        let columns = try #require(outerSplit(in: host)).splitViewItems.map(\.viewController.view)
        #expect(!showsIcon(columns[0]) && !showsIcon(columns[1]))                    // the fallback symbol and the default favicon (404)
        // The page answers after the refresh has ended and the window has settled, as a slow site does.
        await refresh.refresh(feedIDs: [feed.id])
        try await pump(host, 500)
        await site.release()
        await refresh.iconLookupsFinished()
        #expect(store.feed(id: feed.id)?.iconURL == "https://icon.example/icon.png")
        var sidebar = false, list = false
        for _ in 0..<50 where !(sidebar && list) {
            try await pump(host, 20)
            sidebar = showsIcon(columns[0]); list = showsIcon(columns[1])
        }
        #expect(list, "the article list shows the icon")
        #expect(sidebar, "the selected sidebar row shows the icon")
    }
}
