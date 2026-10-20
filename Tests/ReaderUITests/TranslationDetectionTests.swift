import Foundation
import Testing
import ReaderCore
@testable import UnagiReader

@MainActor struct TranslationDetectionTests {
    // Checks PRD-18: a changed body drops every stage of the old translation.
    @Test(arguments: [false, true])
    func aBodyChangeWhileDecidingMustDiscardTheOldTranslation(changed: Bool) async throws {
        let gate = AsyncStream<Void>.makeStream()
        var deciding = false
        var decisionReturned = false
        let engine = TranslationEngine(decide: { _, _ in
            deciding = true
            for await _ in gate.stream { break }
            decisionReturned = true
            return .translate(source: "en")
        }, batch: { items in
            AsyncThrowingStream { continuation in
                for item in items { continuation.yield(TranslationResponse(index: item.index, text: "Translated: " + item.text)) }
                continuation.finish()
            }
        })
        let controller = TranslationController(engine: engine)
        let id = UUID()
        let old = ArticleContent(articleID: id, text: "Old feed body", summary: "", coverage: .feedProvided, originalURL: nil)
        let new = ArticleContent(articleID: id, text: "New corrected feed body", summary: "", coverage: .feedProvided, originalURL: nil)
        controller.setTarget("ja", supported: ["ja", "en"])
        controller.toggle(title: "Title", content: old)
        for _ in 0..<100 where !deciding { try await Task.sleep(for: .milliseconds(10)) }
        try #require(deciding)
        controller.contentChanged(title: "Title", content: changed ? new : old)
        gate.continuation.finish()
        for _ in 0..<100 where !decisionReturned { try await Task.sleep(for: .milliseconds(10)) }
        try #require(decisionReturned)
        if changed {
            #expect(controller.shown(for: id) == nil)
            #expect(controller.state.state == .idle)
            controller.toggle(title: "Title", content: new)
        }
        for _ in 0..<100 where controller.state.state != .done(failed: 0, source: "en") { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.state.state == .done(failed: 0, source: "en"))
        #expect(controller.shown(for: id)?.paragraphs.map(\.text) == [changed ? "Translated: New corrected feed body" : "Translated: Old feed body"])
    }

}
