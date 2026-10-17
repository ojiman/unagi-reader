import Darwin
import Foundation
import Testing
@testable import ReaderCore

/// Run each size in a separate Release process; setup and validation are outside the refresh timers.
@MainActor struct FirstRefreshPerformanceTests {
    @Test func benchmarkFeedsHaveDistinctArticlesAndSupportNotModified() async throws {
        let client = FeedClient(http: FirstRefreshHTTP())
        var links: Set<URL> = []
        for f in 0..<2 {
            let url = URL(string: "https://f\(f).example/feed")!
            let result = try await client.fetch(url: url)
            guard case .modified(let feed, let etag, _) = result else { Issue.record("Expected a modified feed"); return }
            #expect(feed.entries.count == 25 && etag == "v1")
            for entry in feed.entries {
                #expect(entry.body.utf8.count >= 2_048)
                #expect(links.insert(try #require(entry.url)).inserted)
            }
            guard case .notModified = try await client.fetch(url: url, etag: etag) else { Issue.record("Expected 304"); return }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UNAGI_READER_FIRST_REFRESH_FEEDS"] != nil), .timeLimit(.minutes(30)))
    func firstRefreshAfterOPMLImport() async throws {
        let count = try #require(Int(ProcessInfo.processInfo.environment["UNAGI_READER_FIRST_REFRESH_FEEDS"] ?? ""))
        try #require([200, 1_000, 2_000].contains(count))
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        let opml = "<opml version=\"2.0\"><body>" + (0..<count).map { "<outline text=\"F\($0)\" type=\"rss\" xmlUrl=\"https://f\($0).example/feed\"/>" }.joined() + "</body></opml>"
        let file = library.directory.appending(path: "Synthetic.opml")
        try Data(opml.utf8).write(to: file)
        let importer = OPMLImporter(store: store)
        let report = await importer.importFile(at: file)
        try #require(report.addedFeedIDs.count == count)
        #expect(store.articles.isEmpty)
        // Keep production's 0.5 s delay; the regular refresh controller still fetches at most three feeds at once.
        let refresh = FeedRefreshController(store: store, client: FeedClient(http: FirstRefreshHTTP()))
        let first = await measure { await importer.fetchArticles(of: report.addedFeedIDs, using: refresh) }
        #expect(refresh.errors.isEmpty && store.articles.count == count * 25)
        #expect(store.memberships.count == count * 25)
        #expect(store.feeds.allSatisfy { $0.lastFetchedAt != nil && $0.etag == "v1" })
        #expect(store.unreadCount == count * 25)
        print("FIRST_REFRESH feeds=\(count) articles=\(store.articles.count) first=\(first.elapsed) firstGap=\(first.gap) firstMaxRSSMiB=\(first.memory)")
    }

    private func measure(_ run: () async -> Void) async -> (elapsed: Duration, gap: Duration, memory: Double) {
        let clock = ContinuousClock()
        var longest = Duration.zero
        var ready = false
        let heartbeat = Task { @MainActor in
            var previous = clock.now
            ready = true
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
                let now = clock.now
                longest = max(longest, previous.duration(to: now) - .milliseconds(10))
                previous = now
            }
        }
        while !ready { await Task.yield() }
        let start = clock.now
        await run()
        let elapsed = start.duration(to: clock.now)
        // Let a heartbeat delayed by the final batch run before cancelling it.
        try? await Task.sleep(for: .milliseconds(20))
        heartbeat.cancel(); await heartbeat.value
        var usage = rusage()
        #expect(getrusage(RUSAGE_SELF, &usage) == 0)
        return (elapsed, longest, Double(usage.ru_maxrss) / 1_048_576)
    }
}

private struct FirstRefreshHTTP: HTTPFetching {
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
        if headers["If-None-Match"] == "v1" { return HTTPResponse(data: Data(), finalURL: url, statusCode: 304, headers: [:]) }
        let host = url.host ?? "synthetic.example"
        let body = String(repeating: "Synthetic article body. ", count: 90)
        let items = (0..<25).map { "<item><guid>\(host)-\($0)</guid><title>Article \($0)</title><link>https://\(host)/a\($0)</link><description>\(body)</description></item>" }.joined()
        let xml = "<rss version=\"2.0\"><channel><title>Feed \(host)</title>\(items)</channel></rss>"
        return HTTPResponse(data: Data(xml.utf8), finalURL: url, statusCode: 200, headers: ["etag": "v1"])
    }
}
