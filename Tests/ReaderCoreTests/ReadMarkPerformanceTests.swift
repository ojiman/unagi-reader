import Foundation
import SwiftData
import Testing
@testable import ReaderCore

/// Opt-in (#249, architecture 3): the save of a read mark on a copy of the `BenchmarkFixtureTests` library, against a
/// one-field save in the library context. Release only; run alone on the Mac:
///
///     UNAGI_READER_READ_MARK_FIXTURE=<exported fixture> swift test -c release --filter ReadMarkPerformanceTests
@MainActor struct ReadMarkPerformanceTests {
    nonisolated private static let fixture = ProcessInfo.processInfo.environment["UNAGI_READER_READ_MARK_FIXTURE"]

    @Test(.enabled(if: fixture != nil)) func aReadMarkSavesInAContextOfItsOwn() throws {
        let source = URL(fileURLWithPath: try #require(Self.fixture), isDirectory: true)
        let copy = FileManager.default.temporaryDirectory.appending(path: "read-mark-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: source, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let now = Date()
        let store = try ReaderStore(url: copy.appending(path: "Reader.store"), now: now)
        let unread = store.articles.filter { !$0.isRead && $0.firstReadAt == nil }
        try #require(store.articles.count == 10_000 && unread.count >= 60)
        let clock = ContinuousClock()
        func milliseconds(_ duration: Duration) -> Double { Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15 }
        // The library context: one field of one article, then its save, as every change was saved before.
        var library: [Double] = []
        for article in unread[0..<30] {
            article.isRead = true; article.firstReadAt = now
            library.append(milliseconds(clock.measure { try? store.context.save() }))
        }
        try store.reload()
        // The read mark: the whole call, from the check to the refetch and the counts.
        var mark: [Double] = []
        for article in unread[30..<60] {
            let id = article.id
            mark.append(milliseconds(try clock.measure { try store.markDisplayed(articleID: id, at: now) }))
            #expect(store.article(id: id)?.firstReadAt == now)
        }
        func line(_ values: [Double]) -> String {
            let sorted = values.sorted()
            return String(format: "median %.3f ms, p95 %.3f ms, max %.3f ms", sorted[sorted.count / 2], sorted[Int((Double(sorted.count) * 0.95).rounded(.up)) - 1], sorted.last!)
        }
        print("ReadMarkPerformance library-context save: \(line(library))")
        print("ReadMarkPerformance markDisplayed: \(line(mark))")
        #expect(!store.context.hasChanges)
    }
}
