import Foundation
import Testing
@testable import ReaderCore

/// The add-subscription sheet checks the address while the person types (decision 0036).
// Checks PRD-14 (specification 7).
@Suite(EnglishLanguage()) @MainActor struct FeedCheckTests {
    // MARK: What is worth fetching

    @Test func onlyACompleteAddressIsChecked() {
        func request(_ source: String) -> FeedCheckRequest? { FeedCheckRequest.make(source: source, xml: "", manual: false) }
        #expect(request("https://example.com/feed.xml") == .url(URL(string: "https://example.com/feed.xml")!))
        #expect(request("  https://example.com/feed.xml \n") != nil)                  // pasted with spaces
        #expect(request("https://example.co.uk/feed") != nil && request("https://192.168.10.5/feed") != nil)
        for partial in ["", "h", "https://", "https://exa", "https://example", "https://example.c", "https://example.",
                        "https://foo.12", "https://192.16", "https://192.168.10", "https://192.168.10.",
                        "example.com/feed", "ftp://example.com/feed", "https://name:secret@example.com/feed"] {
            #expect(request(partial) == nil, "\(partial)")                           // nothing is sent to a host that does not look complete
        }
    }
    @Test func aPlainHTTPAddressIsCheckedAsHTTPSBecauseTheAppCannotFetchHTTP() async throws {
        func request(_ source: String) -> FeedCheckRequest? { FeedCheckRequest.make(source: source, xml: "", manual: false) }
        #expect(request("http://example.com/feed.xml") == .url(URL(string: "https://example.com/feed.xml")!))
        #expect(request("HTTP://Example.com/feed.xml?x=1") == .url(URL(string: "https://example.com/feed.xml?x=1")!))
        #expect(request("http://example.com:8080/feed") == .url(URL(string: "http://example.com:8080/feed")!))     // a port is for http: left as typed
        #expect(request("https://example.com/feed") == .url(URL(string: "https://example.com/feed")!))
        let fetched = Recorder<FeedCheckRequest>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() }, sleep: { _ in })
        checker.update(source: "http://example.com/feed.xml", delay: .zero); try await waitForResult(checker)
        #expect(fetched.values == [.url(URL(string: "https://example.com/feed.xml")!)])                       // plain http is never sent
    }
    @Test func theSheetShowsTheAddressOnlyWhenItIsNotTheOneTyped() {
        let feed = Self.checked()                                                                              // https://example.com/feed.xml
        #expect(feed.subscribedAddress(whenTyped: "https://example.com/feed.xml") == nil)
        #expect(feed.subscribedAddress(whenTyped: " HTTPS://Example.com/feed.xml ") == nil)                    // same address, written differently
        #expect(feed.subscribedAddress(whenTyped: "http://example.com/feed.xml") == "https://example.com/feed.xml")
        #expect(feed.subscribedAddress(whenTyped: "https://example.com/") == "https://example.com/feed.xml")  // a page that led to its feed
    }
    @Test func returnAcceptsAnyValidAddressSuchAsALocalName() {
        func request(_ source: String, asked: Bool) -> FeedCheckRequest? { FeedCheckRequest.make(source: source, xml: "", manual: false, asked: asked) }
        for local in ["https://localhost/feed", "https://nas/feed", "https://[::1]/feed"] {
            #expect(request(local, asked: false) == nil, "\(local)")                 // not while typing
            #expect(request(local, asked: true) != nil, "\(local)")                  // but the person pressed Return
        }
        #expect(request("https://name:secret@example.com/feed", asked: true) == nil)
    }
    @Test func manualXMLIsParsedLocallyAndNeedsAnAddressAndText() {
        #expect(FeedCheckRequest.make(source: "https://example.com/rss", xml: "<rss/>", manual: true) != nil)
        #expect(FeedCheckRequest.make(source: "https://example.com/rss", xml: "  ", manual: true) == nil)
        #expect(FeedCheckRequest.make(source: "https://exa", xml: "<rss/>", manual: true) == nil)
    }
    @Test func aHintIsGivenOnlyWhenTheTextCannotBecomeAnAddress() {
        #expect(FeedCheckRequest.hint(source: "") == nil)
        #expect(FeedCheckRequest.hint(source: "https://exa") == nil)
        #expect(FeedCheckRequest.hint(source: "example.com/feed") == "Enter a URL starting with http:// or https://.")
        for typingTheScheme in ["h", "http", "https:", "https:/", "HTTPS://"] { #expect(FeedCheckRequest.hint(source: typingTheScheme) == nil, "\(typingTheScheme)") }
        #expect(FeedCheckRequest.hint(source: "ftp://example.com/feed") == "Enter a URL starting with http:// or https://.")
    }
    @Test func returnOnAnAddressThatCannotBeUsedSaysWhy() {
        #expect(FeedCheckRequest.hint(source: "https://", asked: true) == "Enter the complete URL.")
        #expect(FeedCheckRequest.hint(source: "https://name:secret@example.com/feed", asked: true) == FeedImportError.invalidURL.localizedDescription)
        #expect(FeedCheckRequest.hint(source: "ftp://example.com/feed", asked: true) == "Enter a URL starting with http:// or https://.")
        #expect(FeedCheckRequest.hint(source: "", asked: true) == nil)
    }
    @Test func pastingChecksAtOnceAndTypingWaits() {
        #expect(FeedCheckRequest.delay(from: "https://example.com/fee", to: "https://example.com/feed") == .milliseconds(800))
        #expect(FeedCheckRequest.delay(from: "", to: "https://example.com/feed.xml") == .milliseconds(50))
        #expect(FeedCheckRequest.delay(from: "https://example.com/feed", to: "") == .milliseconds(800))
    }

    // MARK: The checker

    private nonisolated static func checked(_ title: String = "合成") -> CheckedFeed {
        let url = URL(string: "https://example.com/feed.xml")!
        return CheckedFeed(parsed: ParsedFeed(title: title, sourceURL: url, entries: [], skippedEntries: 0), etag: "v1", lastModified: nil, fetched: true)
    }
    private func settle(_ checker: FeedChecker) async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(60))               // deliberately blocked checks and ignored late answers
    }

    private func waitForResult(_ checker: FeedChecker, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while checker.state == .idle || checker.state == .checking {
            try #require(ContinuousClock.now < deadline, "Timed out waiting for a feed check: \(checker.state)", sourceLocation: sourceLocation)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test(arguments: [Duration.zero, .milliseconds(200)])
    func aReadableFeedBecomesReadyAfterTheDelay(responseDelay: Duration) async throws {
        let waits = Recorder<Duration>()
        let checker = FeedChecker(fetch: { _ in
            // #304: deliver the answer on the main actor after the old 60 ms wait would have ended.
            try await Task { @MainActor in
                try await Task.sleep(for: responseDelay)
                return Self.checked("読書ラボ")
            }.value
        }, sleep: { waits.add($0) })
        checker.update(source: "https://example.com/feed.xml", delay: .milliseconds(800))
        #expect(checker.state == .idle)                                              // nothing yet: the person may still be typing
        try await waitForResult(checker)
        guard case .ready(let feed) = checker.state else { Issue.record("expected ready, got \(checker.state)"); return }
        #expect(feed.parsed.title == "読書ラボ")
        #expect(waits.values == [.milliseconds(800)])
    }
    @Test func aHalfTypedAddressNeverReachesTheNetwork() async {
        let fetched = Recorder<FeedCheckRequest>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() }, sleep: { _ in })
        for partial in ["h", "https://exa", "https://example.c"] {
            checker.update(source: partial, delay: .zero); await settle(checker)
        }
        #expect(fetched.values.isEmpty)
    }
    @Test func aFailureIsShownInPlainWordsAndTheButtonStaysOff() async throws {
        let checker = FeedChecker(fetch: { _ in throw HTTPError.status(404) }, sleep: { _ in })
        checker.update(source: "https://example.com/missing", delay: .zero); try await waitForResult(checker)
        #expect(checker.state == .failed("Page not found (404). Check the URL."))
    }
    @Test func textWithoutASchemeGetsAHintAfterTheDelayAndEmptyTextIsQuiet() async throws {
        let checker = FeedChecker(fetch: { _ in Self.checked() }, sleep: { _ in })
        checker.update(source: "example.com/feed", delay: .zero); try await waitForResult(checker)
        #expect(checker.state == .failed("Enter a URL starting with http:// or https://."))
        checker.update(source: "", delay: .zero); await settle(checker)
        #expect(checker.state == .idle)
    }
    @Test func pressingReturnFetchesALocalNameThatTypingWouldNotSend() async throws {
        let fetched = Recorder<FeedCheckRequest>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() }, sleep: { _ in })
        checker.update(source: "https://localhost/feed", delay: .milliseconds(800)); await settle(checker)
        #expect(fetched.values.isEmpty)
        checker.update(source: "https://localhost/feed", delay: .zero, asked: true); try await waitForResult(checker)
        #expect(fetched.values == [.url(URL(string: "https://localhost/feed")!)])
    }
    @Test func anEditDuringTheWaitCancelsTheOldCheckBeforeItFetches() async {
        let gate = SlowGate()
        let fetched = Recorder<FeedCheckRequest>()
        let finishedWaits = Recorder<Bool>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() }, sleep: { _ in
            await gate.wait()
            finishedWaits.add(Task.isCancelled)
        })
        checker.update(source: "https://example.com/old", delay: .milliseconds(800)); await settle(checker)
        checker.update(source: "https://example.com/new", delay: .milliseconds(800)); await settle(checker)
        await gate.open(); await settle(checker)                                  // both waits end; only the newest may fetch
        #expect(finishedWaits.values.count == 2)
        #expect(finishedWaits.values.filter { $0 }.count == 1)
        #expect(fetched.values == [.url(URL(string: "https://example.com/new")!)])
    }
    @Test func theStateSaysWhatReturnAndAnAnswerShouldDo() {
        let feed = Self.checked()
        #expect(FeedChecker.State.ready(feed).onReturn == .add(feed))
        #expect(FeedChecker.State.checking.onReturn == .waitForAnswer)
        #expect(FeedChecker.State.idle.onReturn == .checkAgain && FeedChecker.State.failed("x").onReturn == .checkAgain)
        #expect(FeedChecker.State.ready(feed).whileWaitingForReturn == .add(feed))
        #expect(FeedChecker.State.failed("x").whileWaitingForReturn == .giveUp)
        #expect(FeedChecker.State.checking.whileWaitingForReturn == .keepWaiting && FeedChecker.State.idle.whileWaitingForReturn == .keepWaiting)
    }
    @Test func pressingReturnOnAnUnfinishedAddressSaysSo() async throws {
        let fetched = Recorder<FeedCheckRequest>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() }, sleep: { _ in })
        checker.update(source: "https://", delay: .zero, asked: true); try await waitForResult(checker)
        #expect(checker.state == .failed("Enter the complete URL."))
        checker.update(source: "", delay: .zero, asked: true); await settle(checker)
        #expect(checker.state == .idle && fetched.values.isEmpty)
    }
    @Test func cancelStopsTheCheckAndForgetsIt() async {
        let gate = SlowGate()
        let checker = FeedChecker(fetch: { _ in await gate.wait(); return Self.checked() }, sleep: { _ in })
        checker.update(source: "https://example.com/feed.xml", delay: .zero); await settle(checker)
        #expect(checker.state == .checking)
        checker.cancel(); await gate.open(); await settle(checker)
        #expect(checker.state == .idle)
    }
    @Test func anEditDropsTheOldResultAtOnce() async throws {
        let checker = FeedChecker(fetch: { _ in Self.checked() }, sleep: { _ in })
        checker.update(source: "https://example.com/feed.xml", delay: .zero); try await waitForResult(checker)
        guard case .ready = checker.state else { Issue.record("expected ready"); return }
        checker.update(source: "https://example.com/feed.xm", delay: .milliseconds(800))
        #expect(checker.state == .idle)                                              // the add button cannot use a result for another address
    }
    @Test func aSlowAnswerForAnOldAddressIsIgnored() async throws {
        let gate = SlowGate()
        let checker = FeedChecker(fetch: { request in
            guard case .url(let url) = request else { throw HTTPError.invalidResponse }
            if url.path == "/old" { await gate.wait() }
            return Self.checked(url.path)
        }, sleep: { _ in })
        checker.update(source: "https://example.com/old", delay: .zero); await settle(checker)
        #expect(checker.state == .checking)
        checker.update(source: "https://example.com/new", delay: .zero); try await waitForResult(checker)
        await gate.open(); await settle(checker)
        guard case .ready(let feed) = checker.state else { Issue.record("expected ready, got \(checker.state)"); return }
        #expect(feed.parsed.title == "/new")
    }
    @Test func checkingNowSkipsTheDelay() async throws {
        let waits = Recorder<Duration>()
        let checker = FeedChecker(fetch: { _ in Self.checked() }, sleep: { waits.add($0) })
        checker.update(source: "https://example.com/feed.xml", delay: .zero); try await waitForResult(checker)
        #expect(waits.values.isEmpty)
        guard case .ready = checker.state else { Issue.record("expected ready"); return }
    }

    // MARK: Words for each cause

    @Test func eachCauseHasItsOwnPlainSentence() {
        func text(_ error: any Error) -> String { FeedCheckMessage.text(for: error) }
        #expect(text(HTTPError.status(404)) == "Page not found (404). Check the URL.")
        #expect(text(HTTPError.status(403)) == "This URL could not be read (403). You may need to log in.")
        #expect(text(HTTPError.status(503)) == "The server returned an error (503). Try again later.")
        #expect(text(HTTPError.status(418)) == "The server returned an error (418).")
        #expect(text(URLError(.notConnectedToInternet)) == "You are not connected to the network.")
        #expect(text(URLError(.timedOut)) == "The server did not respond.")
        #expect(text(URLError(.cannotFindHost)) == "The server could not be found. Check the URL.")
        #expect(text(URLError(.serverCertificateUntrusted)) == "A secure connection could not be made.")
        #expect(text(URLError(.cannotConnectToHost)) == "Could not connect.")
        #expect(text(URLError(.appTransportSecurityRequiresSecureConnection)) == "HTTP connections are not supported. Enter an https:// URL.")
        #expect(text(HTTPError.tooLarge) == "The data is too large (maximum 2 MB).")
        #expect(text(FeedImportError.htmlPage) == "This is a web page, not a feed. Enter the feed URL.")
        #expect(text(FeedImportError.noFeedInPage) == "No feed was found on this page. Enter the feed URL.")
        #expect(text(FeedImportError.invalidXML) == "The feed XML could not be read. There may be a problem with the source.")
        #expect(FeedCheckMessage.text(for: FeedImportError.invalidXML, pastedXML: true) == "The pasted XML could not be read because it contains errors.")
    }

    @Test func aFeedTypedWithHttpThatHttpsCannotLoadSaysThatHttpIsNotSupported() {
        let httpOnly = "Could not load over HTTPS. HTTP is not supported."
        func text(_ error: any Error) -> String { FeedCheckMessage.text(for: error, plainHTTP: true) }
        for code: URLError.Code in [.cannotConnectToHost, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate] {
            #expect(text(URLError(code)) == httpOnly)
        }
        // A cause that does not depend on the scheme keeps its own sentence.
        #expect(text(URLError(.notConnectedToInternet)) == "You are not connected to the network.")
        #expect(text(URLError(.timedOut)) == "The server did not respond.")
        #expect(text(URLError(.cannotFindHost)) == "The server could not be found. Check the URL.")
        #expect(text(HTTPError.status(404)) == "Page not found (404). Check the URL.")
        #expect(text(URLError(.appTransportSecurityRequiresSecureConnection)) == "HTTP connections are not supported. Enter an https:// URL.")   // a port: https was not tried
        #expect(text(FeedImportError.htmlPage) == "This is a web page, not a feed. Enter the feed URL.")
        // An address typed with https is not blamed on http.
        #expect(FeedCheckMessage.text(for: URLError(.cannotConnectToHost)) == "Could not connect.")
    }
    @Test func theCheckerTellsAnHttpAddressApartFromAnHttpsOne() async throws {
        let httpOnly = "Could not load over HTTPS. HTTP is not supported."
        let checker = FeedChecker(fetch: { _ in throw URLError(.cannotConnectToHost) }, sleep: { _ in })
        checker.update(source: "http://example.com/feed.xml", delay: .zero); try await waitForResult(checker)
        #expect(checker.state == .failed(httpOnly))
        checker.update(source: "https://example.com/feed.xml", delay: .zero); try await waitForResult(checker)
        #expect(checker.state == .failed("Could not connect."))
        checker.update(source: "  HTTP://example.com/feed.xml", delay: .zero); try await waitForResult(checker)      // pasted with spaces and capitals
        #expect(checker.state == .failed(httpOnly))
    }

    @Test func theDefaultFetchReadsTheRealResponse() async throws {
        let url = URL(string: "https://\(UUID().uuidString.lowercased()).example/rss")!
        let client = FeedClient(http: HTTPClient(protocolClasses: [StubURLProtocol.self]))
        StubURLProtocol.register(.init(headers: ["ETag": "v9"], data: Data(FeedParserTests.rss.utf8)), at: url)
        let feed = try await FeedChecker.fetch(.url(url), client: client)
        #expect(feed.parsed.title == "合成ニュース" && feed.etag == "v9" && feed.fetched)
        StubURLProtocol.register(.init(data: Data("<!doctype html><html><body>top page</body></html>".utf8)), at: url)
        await #expect(throws: FeedImportError.noFeedInPage) { try await FeedChecker.fetch(.url(url), client: client) }       // a page with no feed in it
        let site = URL(string: "https://\(UUID().uuidString.lowercased()).example/")!
        StubURLProtocol.register(.init(data: Data("<!doctype html><html><head><link rel=\"alternate\" type=\"application/atom+xml\" href=\"/a.atom\"></head></html>".utf8)), at: site)
        StubURLProtocol.register(.init(data: Data(FeedParserTests.rss.utf8)), at: site.appending(path: "a.atom"))
        let found = try await FeedChecker.fetch(.url(site), client: client)
        #expect(found.parsed.sourceURL == site.appending(path: "a.atom") && found.foundOnPage == site)
        let manual = try await FeedChecker.fetch(.xml(Data(FeedParserTests.rss.utf8), url), client: client)
        #expect(!manual.fetched && manual.etag == nil)
    }

    /// #266: typing an address cancels the check that is still waiting for the person to pause. The real wait (not a stub)
    /// is cancelled again and again, as in the sheet; the app aborted in `swift_task_dealloc` on the CI toolchain in Debug.
    @Test func typingCancelsTheRealWaitManyTimesWithoutEndingTheApp() async {
        let fetched = Recorder<FeedCheckRequest>()
        let checker = FeedChecker(fetch: { fetched.add($0); return Self.checked() })      // the default sleep: `Task.sleep`
        let address = "https://127.0.0.1:"
        for port in 1000..<1200 {
            checker.update(source: address + "\(port)/feed.xml", delay: FeedCheckRequest.delay(from: address, to: address + "1"))
            for _ in 0..<3 { await Task.yield() }                                          // the old check is now inside its wait
        }
        checker.update(source: "https://127.0.0.1:1200/feed.xml", delay: .milliseconds(10))
        for _ in 0..<500 { if case .ready = checker.state { break }; try? await Task.sleep(for: .milliseconds(20)) }   // a loaded runner is slow
        // A slow runner can let an early wait end before the next edit, as a person who paused would; the last edit always wins.
        #expect(fetched.values.last == .url(URL(string: "https://127.0.0.1:1200/feed.xml")!))
        guard case .ready = checker.state else { Issue.record("expected ready, got \(checker.state)"); return }
    }
}

/// Collects values from `@Sendable` closures.
final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Value] = []
    func add(_ value: Value) { lock.withLock { items.append(value) } }
    var values: [Value] { lock.withLock { items } }
}

/// Holds all callers, including cancelled ones, until the test opens it.
actor SlowGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        isOpen = true
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }
}
