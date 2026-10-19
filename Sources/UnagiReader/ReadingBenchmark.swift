import AppKit
import ReaderCore

/// Opt-in replay for issue #164. Only a marked, temporary BenchmarkFixtureTests library may be changed.
@MainActor enum ReadingBenchmark {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--reading-benchmark") }
    /// What the measured refresh brings (`--refresh-scenario`, #303). `changed`, the default, is the original replay: every feed answers
    /// its 100 entries with bodies that differ from the fixture's. The others first refresh once unmeasured, to the stub's own content
    /// (etag "base"), and then measure a second refresh: `unchanged` answers the same content again with 200; `morning` adds 10 new
    /// entries to every feed; `typical` answers 304 for 6 feeds in 10, the same content for 3, and 3 new entries for 1.
    enum RefreshScenario: String, Sendable { case changed, unchanged, morning, typical }
    nonisolated static var scenario: RefreshScenario {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--refresh-scenario"), args.indices.contains(index + 1) else { return .changed }
        return RefreshScenario(rawValue: args[index + 1]) ?? .changed
    }
    /// New articles the measured refresh of a scenario adds to the 10,000.
    nonisolated static func newArticles(_ scenario: RefreshScenario) -> Int {
        switch scenario { case .changed, .unchanged: 0; case .morning: 100 * 10; case .typical: 10 * 3 }
    }
    private(set) static var completed = false
    private(set) static var failure: String?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func validateFixture(at directory: URL, explicit: Bool) throws {
        let target = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let library = URL.applicationSupportDirectory.appending(path: "UnagiReader").resolvingSymlinksInPath().path
        guard explicit, target.caseInsensitiveCompare(library) != .orderedSame,
              !target.lowercased().hasPrefix(library.lowercased() + "/"),
              (try? String(contentsOf: directory.appending(path: ".reading-benchmark"), encoding: .utf8)) == "BenchmarkFixtureTests\n" else {
            throw Failure(message: "The reading benchmark needs an explicit, marked synthetic fixture directory.")
        }
    }

    struct SyntheticHTTP: HTTPFetching {
        var scenario: RefreshScenario = ReadingBenchmark.scenario
        func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> HTTPResponse {
            guard url.scheme == "https", url.host == "synthetic.example", url.user == nil, url.password == nil, url.port == nil,
                  url.deletingLastPathComponent().path == "/feeds", let feed = Int(url.lastPathComponent), (0..<100).contains(feed) else {
                throw HTTPError.invalidURL
            }
            let body = (1...80).map { "合成段落 \($0)。更新計測のための本文です。これは現実の記事ではありません。" }.joined(separator: "\n\n")
            func item(_ guid: String, _ title: String) -> String {
                "<item><guid>\(guid)</guid><title>\(title)</title><description>負荷試験のための合成要約です。</description><content:encoded><![CDATA[\(body)]]></content:encoded></item>"
            }
            var entries = stride(from: feed, to: 10_000, by: 100).map { item("\($0)", "合成記事 \($0)") }
            var etag: String?
            // The measured round of a scenario: the feed already has the stub's content and its etag.
            if scenario != .changed, headers["If-None-Match"] == "base" {
                etag = "base"
                switch scenario {
                case .changed, .unchanged: break
                case .morning: entries = (0..<10).map { item("new-\(feed)-\($0)", "合成新着 \(feed)-\($0)") } + entries
                case .typical:
                    if feed % 10 < 6 { return HTTPResponse(data: Data(), finalURL: url, statusCode: 304, headers: ["etag": "base"]) }
                    if feed % 10 == 9 { entries = (0..<3).map { item("new-\(feed)-\($0)", "合成新着 \(feed)-\($0)") } + entries }
                }
            } else if scenario != .changed { etag = "base" }
            let data = Data("<rss version=\"2.0\" xmlns:content=\"http://purl.org/rss/1.0/modules/content/\"><channel><title>合成購読 \(feed)</title>\(entries.joined())</channel></rss>".utf8)
            guard data.count <= maximumBytes else { throw HTTPError.tooLarge }
            return HTTPResponse(data: data, finalURL: url, statusCode: 200, headers: etag.map { ["etag": $0] } ?? [:])
        }
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private static func wait(until ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(120)
        while !ready() {
            guard ContinuousClock.now < deadline else { throw Failure(message: "The reading benchmark timed out.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func key(_ text: String, code: UInt16, in window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else {
            throw Failure(message: "Could not create a benchmark key event.")
        }
        NSApp.postEvent(event, atStart: false)
    }

    static func run(store: ReaderStore, refresh: FeedRefreshController) async {
        do {
            guard ReaderPerformance.output != nil, store.feeds.count == 100, store.articles.count == 10_000,
                  store.feeds.enumerated().allSatisfy({ $0.element.title == String(format: "合成購読 %03d", $0.offset) && $0.element.sourceURL == nil }) else {
                throw Failure(message: "Expected --performance-output and the 100-feed, 10,000-article synthetic fixture.")
            }
            try await Task.sleep(for: .seconds(1))
            try await wait { !refresh.refreshing }
            guard refresh.errors.isEmpty, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let content = window.contentView, let table = find(NativeArticleList.Table.self, in: content) else {
                throw Failure(message: "The synthetic reader window or initial refresh was not ready.")
            }
            NSApp.activate(); window.makeKeyAndOrderFront(nil)
            ReaderPerformance.columnWidths["reading"] = MotionBenchmark.columnWidths(in: content)
            ReaderPerformance.beginPhase("reading")
            let initial = ReaderPerformance.selectionCount
            // The first j selects row zero; leave one row before the start so every k changes the selection.
            for (index, letter) in (Array(repeating: "j", count: 51) + Array(repeating: "k", count: 49)).enumerated() {
                window.makeFirstResponder(table)
                try key(letter, code: letter == "j" ? 38 : 40, in: window)
                try await wait { ReaderPerformance.selectionCount == initial + index + 1 }
                try await Task.sleep(for: .milliseconds(300))
            }
            ReaderPerformance.beginPhase(nil)
            try key("n", code: 45, in: window)
            try await wait { find(NoteTextView.self, in: content) != nil }
            try await Task.sleep(for: .seconds(1))
            guard let note = find(NoteTextView.self, in: content) else { throw Failure(message: "The note did not open.") }
            ReaderPerformance.columnWidths["noteOpen"] = MotionBenchmark.columnWidths(in: content)
            window.makeFirstResponder(note)
            let original = note.string
            note.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
            ReaderPerformance.beginPhase("typing")
            let typed = String(repeating: "Synthetic note. ", count: 4)
            for character in typed {
                note.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                try await Task.sleep(for: .milliseconds(50))
            }
            guard store.note?.text == original + typed else { throw Failure(message: "Synthetic typing was not saved exactly.") }
            ReaderPerformance.beginPhase(nil)
            // The canonical fixture has no feed URLs. Keep ordinary startup, then prepare only the explicit refresh.
            for (index, feed) in store.feeds.enumerated() { feed.sourceURL = "https://synthetic.example/feeds/\(index)" }
            if let first = store.feeds.first { try store.recordFetch(first, etag: nil, lastModified: nil, at: .now) }
            let scenario = Self.scenario
            ReaderPerformance.refreshScenario = scenario.rawValue
            if scenario != .changed {
                await refresh.refresh()                                    // unmeasured: the feeds take the stub's content and etag
                guard refresh.errors.isEmpty, store.feeds.allSatisfy({ $0.etag == "base" }) else {
                    throw Failure(message: "The scenario's first refresh did not finish every feed.")
                }
                try await Task.sleep(for: .seconds(1))
            }
            ReaderPerformance.beginPhase("refresh")
            let started = Date.now
            await refresh.refresh()
            guard refresh.errors.isEmpty, store.feeds.allSatisfy({ ($0.lastFetchedAt ?? .distantPast) >= started }),
                  store.articles.count == 10_000 + Self.newArticles(scenario) else { throw Failure(message: "The synthetic refresh did not finish every feed.") }
            // Include the screen work queued by the last reload, not just the synchronous store calls.
            try await Task.sleep(for: .seconds(1))
            content.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            ReaderPerformance.beginPhase(nil)
            completed = true
        } catch {
            ReaderPerformance.beginPhase(nil)
            failure = error.localizedDescription
            NSLog("Unagi Reader reading benchmark failed: %@", error.localizedDescription)
        }
        ReaderPerformance.write()
        NSApp.terminate(nil)
    }
}
