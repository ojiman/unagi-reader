import Foundation
import Testing
@testable import ReaderCore

@Suite(EnglishLanguage()) @MainActor struct FeedClientTests {
    private func endpoint() -> URL { URL(string: "https://\(UUID().uuidString.lowercased()).example/rss")! }
    private var client: FeedClient { FeedClient(http: HTTPClient(protocolClasses: [StubURLProtocol.self])) }

    @Test func successfulFetchAndConditionalRequest() async throws {
        let url = endpoint()
        StubURLProtocol.register(.init(headers: ["ETag": "v1", "Last-Modified": "yesterday"], data: Data(FeedParserTests.rss.utf8)), at: url)
        guard case .modified(let parsed, let etag, let modified) = try await client.fetch(url: url) else {
            Issue.record("Expected a modified feed"); return
        }
        #expect(parsed.entries.count == 1 && parsed.sourceURL == url)
        #expect(etag == "v1" && modified == "yesterday")
        StubURLProtocol.register(.init(status: 304), at: url)
        guard case .notModified = try await client.fetch(url: url, etag: etag, lastModified: modified) else {
            Issue.record("Expected 304"); return
        }
        #expect(StubURLProtocol.request(at: url)?.value(forHTTPHeaderField: "If-None-Match") == "v1")
    }

    @Test func failuresAndNotModifiedPreserveSavedReadingData() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let now = Date.now
        let store = try ReaderStore(url: library.url, now: now)
        let url = endpoint()
        let feed = try store.importFeed(FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: url), receivedAt: now)
        let article = try #require(store.articles.first)
        try store.markDisplayed(articleID: article.id, at: now)
        try store.saveNote(text: "消えない", at: now)
        let refresh = FeedRefreshController(store: store, client: client)
        let replies: [StubURLProtocol.Reply] = [.init(status: 304), .init(status: 401), .init(status: 403),
            .init(error: .timedOut), .init(error: .notConnectedToInternet), .init(data: Data("<rss>".utf8)),
            .init(data: Data(repeating: 65, count: 2 * 1024 * 1024 + 1))]
        for reply in replies {
            StubURLProtocol.register(reply, at: url)
            await refresh.refresh(feedIDs: [feed.id], at: now)
            #expect(article.firstReceivedAt == now && article.firstReadAt == now)
            #expect(try store.content(articleID: article.id, at: now)?.text.contains("本文 & 補足") == true)
            #expect(store.note?.text == "消えない")
        }
    }

    @Test func redirectedBaseDoesNotChangeSubscriptionIdentity() throws {
        let source = endpoint()
        let final = URL(string: "https://cdn.example/feeds/current.xml")!
        let xml = "<rss><channel><title>合成</title><item><guid>one</guid><link>../posts/one</link><description>要約</description></item></channel></rss>"
        let parsed = try FeedParser.parse(Data(xml.utf8), sourceURL: source, baseURL: final)
        #expect(parsed.sourceURL == source)
        #expect(parsed.entries.first?.url?.absoluteString == "https://cdn.example/posts/one")
        #expect(throws: (any Error).self) { try HTTPClient.validateRedirect(from: source, to: URL(fileURLWithPath: "/tmp/synthetic")) }
        #expect(throws: (any Error).self) { try HTTPClient.validateRedirect(from: source, to: URL(string: "http://cdn.example/rss")!) }
        #expect(throws: (any Error).self) { try HTTPClient.validateRedirect(from: source, to: URL(string: "https://name:pass@cdn.example/rss")!) }
    }

    @Test func invalidURLAndOversizeFailBeforeParsing() async throws {
        await #expect(throws: (any Error).self) { try await client.fetch(url: URL(fileURLWithPath: "/tmp/synthetic")) }
        let url = endpoint()
        StubURLProtocol.register(.init(headers: ["Content-Length": "99999999"], data: Data("<rss>".utf8)), at: url)
        await #expect(throws: (any Error).self) { try await client.fetch(url: url) }
    }

    // The limit catches a hang. In CI this suite shares one process with the hosted UI tests, which keep the main thread busy: the test
    // took 46 s and 76 s there while it takes 0.08 s alone (#208).
    @Test(.timeLimit(.minutes(3))) func limitsParallelRefreshAndDiscardsUnsubscribedResponse() async throws {
        let library = try TestLibrary(); defer { library.cleanup() }
        let store = try ReaderStore(url: library.url)
        for _ in 0..<5 { _ = try store.importFeed(FeedParser.parse(Data(FeedParserTests.rss.utf8), sourceURL: endpoint())) }
        let removed = try #require(store.feeds.first)
        let gate = RefreshGate()
        let controller = FeedRefreshController(store: store, client: FeedClient(http: gate))
        let running = Task { await controller.refresh() }
        while await gate.started < 3 { await Task.yield() }
        await controller.refresh() // Reentrant requests must not start another batch.
        #expect(await gate.started == 3)
        try store.unsubscribe(removed)
        await gate.releasePending()
        while await gate.started < 5 { await Task.yield() }
        await gate.releasePending()
        await running.value
        #expect(await gate.peak <= 3)
        #expect(!store.feeds.contains { $0.id == removed.id })
        #expect(!controller.refreshing && controller.errors.isEmpty)
    }
}

private actor RefreshGate: HTTPFetching {
    var started = 0
    var peak = 0
    var pending: [(URL, CheckedContinuation<HTTPResponse, any Error>)] = []
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
        // A feed without an icon also asks for its home page (#441); only the feeds are counted and held.
        if url.path == "/" { return HTTPResponse(data: Data(), finalURL: url, statusCode: 404, headers: [:]) }
        started += 1; peak = max(peak, pending.count + 1)
        return try await withCheckedThrowingContinuation { pending.append((url, $0)) }
    }
    func releasePending() {
        let responses = pending; pending = []
        for (url, continuation) in responses {
            continuation.resume(returning: HTTPResponse(data: Data(FeedParserTests.rss.utf8), finalURL: url, statusCode: 200, headers: [:]))
        }
    }
}
