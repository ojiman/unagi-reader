import Foundation
import NaturalLanguage
import Observation

/// What is sent to the translator for one article (specification 3.6): the title, then each paragraph that has text, in order.
public struct TranslationPlan: Sendable, Equatable {
    /// The index of the title among the items; paragraphs use their own index in the body.
    public static let titleIndex = -1
    public struct Item: Sendable, Equatable {
        public let index: Int
        public let text: String
    }
    /// The same article, body and target give the same key; any change gives another (a stale answer or a cache miss).
    public struct Key: Hashable, Sendable {
        public let articleID: UUID
        public let body: Int
        public let target: String
    }
    public let key: Key
    public let title: String
    public let paragraphs: [BodyParagraph]
    public let items: [Item]

    public init(title: String, content: ArticleContent, target: String) {
        var hasher = Hasher()
        hasher.combine(title); hasher.combine(content.bodyParagraphs.map(\.text))
        key = Key(articleID: content.articleID, body: hasher.finalize(), target: target)
        self.title = title
        paragraphs = content.bodyParagraphs
        let body = content.bodyParagraphs.enumerated().compactMap { index, paragraph in
            paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Item(index: index, text: paragraph.text)
        }
        items = (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [Item(index: Self.titleIndex, text: title)]) + body
    }

    /// The title and paragraphs to show: the translated text where there is one, the original elsewhere. Links are not kept in
    /// translated text (their positions change); the quote depth is, and images stay at the start or the end of their paragraph.
    public func apply(_ translated: [Int: String]) -> TranslatedArticle {
        TranslatedArticle(title: translated[Self.titleIndex] ?? title, paragraphs: paragraphs.enumerated().map { index, paragraph in
            translated[index].map { text in
                let end = (text as NSString).length
                return BodyParagraph(text: text, quoteDepth: paragraph.quoteDepth, images: paragraph.images?.map { $0.at($0.location == 0 ? 0 : end) })
            } ?? paragraph
        })
    }
}

public struct TranslatedArticle: Sendable, Equatable {
    public let title: String
    public let paragraphs: [BodyParagraph]
}

/// One answer of the translator: the item's index, and its text, or nil when that item could not be translated.
public struct TranslationResponse: Sendable, Equatable {
    public let index: Int
    public let text: String?
    public init(index: Int, text: String?) { self.index = index; self.text = text }
}

/// Translates the items and answers each as it is ready. The app gives the system's session; the tests give a fake.
public typealias TranslationBatch = @Sendable ([TranslationPlan.Item]) -> AsyncThrowingStream<TranslationResponse, Error>

/// The translation of the open article (specification 3.6). Nothing here is stored: a few results are kept in memory and are gone
/// when the app closes. A late answer for another article, language, press or body is dropped (a generation, as in `FeedChecker`).
@Observable @MainActor public final class ArticleTranslation {
    public enum State: Equatable, Sendable {
        case idle
        /// The system is getting the language ready (a language pack download).
        case preparing
        case translating(done: Int, total: Int)
        /// `failed` items kept their original text. `source` is the detected language, when it was known.
        case done(failed: Int, source: String?)
        case failed(String)
        case alreadyInTarget
        case unsupported
    }
    /// The work for one press. The app runs it with the system's session (`run`).
    public struct Job: Equatable, Sendable {
        public let generation: Int
        public let plan: TranslationPlan
        public let source: String?
    }
    private struct Result {
        let shown: TranslatedArticle
        let failed: Int
        let source: String?
    }

    public private(set) var state = State.idle
    /// The title and paragraphs to show in place of the original, or nil for the original.
    public private(set) var shown: TranslatedArticle?
    /// The article, body and target of what is shown or being worked on.
    public private(set) var key: TranslationPlan.Key?
    private var generation = 0
    private var cache: [(key: TranslationPlan.Key, result: Result)] = []
    private let cacheSize: Int

    public init(cacheSize: Int = 5) { self.cacheSize = cacheSize }

    /// The button or `t`. Shows the original again when this article is already translated (or being translated) into `target`;
    /// otherwise translates it. Returns the work to run, or nil when nothing needs to run (back to the original, the language
    /// decision ended it, or the result was in memory).
    public func press(title: String, content: ArticleContent, target: String, decision: LanguageDecision.Outcome) -> Job? {
        let plan = TranslationPlan(title: title, content: content, target: target)
        if plan.key == key { reset(); return nil }
        reset()
        switch decision {
        case .alreadyInTarget: state = .alreadyInTarget; return nil
        case .unsupported: state = .unsupported; return nil
        case .translate(let source):
            key = plan.key
            if let index = cache.firstIndex(where: { $0.key == plan.key }) {
                let entry = cache.remove(at: index); cache.append(entry)
                shown = entry.result.shown; state = .done(failed: entry.result.failed, source: entry.result.source)
                return nil
            }
            shown = plan.apply([:])
            state = .translating(done: 0, total: plan.items.count)
            return Job(generation: generation, plan: plan, source: source)
        }
    }

    /// Runs a job. Each answer is applied as it arrives; answers for a dropped job change nothing. `describe` turns a failure of
    /// the whole batch into the sentence of the status row.
    public func run(_ job: Job, translate: TranslationBatch, describe: (Error) -> String = { _ in String(localized: "Could not translate.", bundle: ReaderLocalization.bundle) },
                    onProgress: (State) -> Void = { _ in }) async {
        guard job.generation == generation else { return }
        var translated: [Int: String] = [:]
        var answered = 0
        let total = job.plan.items.count
        do {
            for try await response in translate(job.plan.items) {
                guard job.generation == generation else { return }
                guard !Task.isCancelled else { reset(); return }      // the app stopped the work without a new press
                answered += 1
                if let text = response.text { translated[response.index] = text }
                shown = job.plan.apply(translated)
                state = .translating(done: answered, total: total)
                onProgress(state)
            }
        } catch {
            guard job.generation == generation else { return }
            if error is CancellationError || Task.isCancelled { reset(); return }
            if translated.isEmpty { shown = nil; key = nil; state = .failed(describe(error)); return }
        }
        guard job.generation == generation else { return }
        guard !Task.isCancelled else { reset(); return }
        let result = Result(shown: job.plan.apply(translated), failed: total - translated.count, source: job.source)
        shown = result.shown; state = .done(failed: result.failed, source: result.source)
        // Only a whole translation is kept: after a failure the next press tries again.
        if result.failed == 0 { remember(job.plan.key, result) }
    }

    /// The system started getting the language ready for this job.
    public func preparing(_ job: Job) {
        guard job.generation == generation else { return }
        state = .preparing
    }

    /// The article's text was replaced (a feed refresh): a translation of the old text is dropped, and the original shows.
    public func contentChanged(title: String, content: ArticleContent) {
        guard let key, TranslationPlan(title: title, content: content, target: key.target).key != key else { return }
        reset()
    }

    /// Back to the original, and any running job is dropped (another article, the original page, or a second press).
    public func reset() {
        generation += 1
        state = .idle; shown = nil; key = nil
    }

    private func remember(_ key: TranslationPlan.Key, _ result: Result) {
        cache.removeAll { $0.key == key }
        cache.append((key, result))
        if cache.count > cacheSize { cache.removeFirst(cache.count - cacheSize) }
    }
}

/// Whether to translate (specification 3.6): the article may already be in the target language, or the system may not support the
/// pair. The detector and the check of the pair are given, so the rule is tested without the system's frameworks.
public enum LanguageDecision {
    public enum Outcome: Equatable, Sendable {
        /// Translate. `source` is nil when the language could not be told: the system then detects it.
        case translate(source: String?)
        case alreadyInTarget
        case unsupported
    }
    /// How much of the article is used to tell its language.
    public static let sampleLength = 600

    public static func decide(sample: String, target: String, detect: @Sendable (String) -> String?,
                              supported: @Sendable (String, String) async -> Bool) async -> Outcome {
        guard let source = detect(sample) else { return .translate(source: nil) }
        if sameLanguage(source, target) { return .alreadyInTarget }
        return await supported(source, target) ? .translate(source: source) : .unsupported
    }

    /// The title and the start of the body.
    public static func sample(title: String, paragraphs: [String]) -> String {
        String(([title] + paragraphs).joined(separator: "\n").prefix(sampleLength))
    }

    /// The language of the text by the system's recognizer (BCP 47), or nil when it is not clear.
    public static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first, confidence >= 0.5 else { return nil }
        return language.rawValue
    }

    /// The language counts, not the region: en-GB is already en-US. A script tells written forms apart (zh-Hans and zh-Hant).
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let left = Locale.Language(identifier: a), right = Locale.Language(identifier: b)
        guard let code = left.languageCode, code == right.languageCode else { return false }
        guard let scriptA = left.script, let scriptB = right.script else { return true }
        return scriptA == scriptB
    }
}
