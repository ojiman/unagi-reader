import Foundation
import ReaderCore
import Testing
@testable import UnagiReader

@Suite(EnglishLanguage()) @MainActor struct ReadingBenchmarkTests {
    @Test func automationRefusesAnUnmarkedLibraryAndAnImplicitDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) { try ReadingBenchmark.validateFixture(at: directory, explicit: true) }
        try Data("BenchmarkFixtureTests\n".utf8).write(to: directory.appending(path: ".reading-benchmark"))
        #expect(throws: (any Error).self) { try ReadingBenchmark.validateFixture(at: directory, explicit: false) }
        try ReadingBenchmark.validateFixture(at: directory, explicit: true)
    }

    @Test func syntheticRefreshParsesOneHundredEntriesWithoutNetwork() async throws {
        let client = FeedClient(http: ReadingBenchmark.SyntheticHTTP())
        let url = URL(string: "https://synthetic.example/feeds/3")!
        guard case .modified(let feed, _, _) = try await client.fetch(url: url) else {
            Issue.record("Expected a synthetic modified feed"); return
        }
        #expect(feed.sourceURL == url && feed.entries.count == 100)
        #expect(feed.entries.first?.sourceID == "3" && feed.entries.last?.sourceID == "9903")
        #expect(feed.entries.allSatisfy { $0.body.contains("合成段落 80") })
        await #expect(throws: (any Error).self) {
            _ = try await client.fetch(url: URL(string: "https://other.example/feeds/3")!)
        }
    }

    /// #303: the refresh scenarios. The first round has the stub's own content and etag; the measured round depends on the scenario.
    @Test func refreshScenariosAnswerTheirMeasuredRound() async throws {
        func fetch(_ scenario: ReadingBenchmark.RefreshScenario, feed: Int, etag: String?) async throws -> FeedFetchResult {
            try await FeedClient(http: ReadingBenchmark.SyntheticHTTP(scenario: scenario))
                .fetch(url: URL(string: "https://synthetic.example/feeds/\(feed)")!, etag: etag)
        }
        guard case .modified(let first, let etag, _) = try await fetch(.unchanged, feed: 3, etag: nil) else { Issue.record("first round"); return }
        #expect(etag == "base" && first.entries.count == 100)
        guard case .modified(let same, _, _) = try await fetch(.unchanged, feed: 3, etag: "base") else { Issue.record("unchanged"); return }
        #expect(same.entries.map(\.sourceID) == first.entries.map(\.sourceID) && same.entries.map(\.body) == first.entries.map(\.body))
        guard case .modified(let morning, _, _) = try await fetch(.morning, feed: 3, etag: "base") else { Issue.record("morning"); return }
        #expect(morning.entries.count == 110 && morning.entries.first?.sourceID == "new-3-0")
        guard case .notModified = try await fetch(.typical, feed: 3, etag: "base") else { Issue.record("typical 304"); return }
        guard case .modified(let typicalSame, _, _) = try await fetch(.typical, feed: 7, etag: "base") else { Issue.record("typical same"); return }
        #expect(typicalSame.entries.count == 100)
        guard case .modified(let typicalNew, _, _) = try await fetch(.typical, feed: 9, etag: "base") else { Issue.record("typical new"); return }
        #expect(typicalNew.entries.count == 103)
        #expect(ReadingBenchmark.newArticles(.morning) == 1_000 && ReadingBenchmark.newArticles(.typical) == 30)
    }
}
