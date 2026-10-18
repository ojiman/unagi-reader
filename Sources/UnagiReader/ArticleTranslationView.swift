import SwiftUI
@preconcurrency import Translation   // the session is used only inside one `translationTask` call (`TranslationController.translate(with:)`)
import ReaderCore

/// How the app decides and translates. `.system` uses the Translation framework on the Mac; tests give a fake.
struct TranslationEngine {
    var decide: @MainActor (_ sample: String, _ target: String) async -> LanguageDecision.Outcome
    /// nil: the system's session, which exists only inside `TranslationHost`'s `translationTask`.
    var batch: TranslationBatch?
    var languages: @MainActor () async -> [String] = { await TranslationLanguages.available() }

    @MainActor static let system = TranslationEngine(decide: { sample, target in
        await LanguageDecision.decide(sample: sample, target: target, detect: LanguageDecision.detect) { source, target in
            await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)) != .unsupported
        }
    }, batch: nil)
}

/// Links a press (the button, `t`, the menu bar) to `ArticleTranslation` and to the system's session.
@Observable @MainActor final class TranslationController {
    let state = ArticleTranslation()
    private(set) var target = "en"
    private var supportedTargets: [String]?
    var targetReady: Bool { supportedTargets != nil }

    func setTarget(_ target: String, supported: [String]) {
        let supportChanged = supportedTargets.map { $0.contains(target) != supported.contains(target) } ?? !supported.contains(target)
        if self.target != target || supportChanged { reset() }
        self.target = target
        supportedTargets = supported
    }
    /// The session's configuration: a new one starts `TranslationHost`'s task; nil stops it.
    private(set) var configuration: TranslationSession.Configuration?
    @ObservationIgnored private var job: ArticleTranslation.Job?
    @ObservationIgnored private var deciding: Task<Void, Never>?
    @ObservationIgnored private let engine: TranslationEngine

    init(engine: TranslationEngine) { self.engine = engine }
    func availableTargets() async -> [String] { await engine.languages() }

    /// Whether this article's translation is shown or being made (the button is filled).
    func isOn(for articleID: UUID?) -> Bool { articleID != nil && (state.key?.articleID == articleID || deciding != nil) }
    func shown(for articleID: UUID) -> TranslatedArticle? { state.key?.articleID == articleID ? state.shown : nil }

    /// Translates the article, or shows the original again when it is on.
    func toggle(title: String, content: ArticleContent) {
        guard targetReady else { return }
        if isOn(for: content.articleID) { reset(); return }
        reset()
        let target = self.target
        if let supportedTargets, !supportedTargets.contains(target) {
            _ = state.press(title: title, content: content, target: target, decision: .unsupported)
            return
        }
        let sample = LanguageDecision.sample(title: title, paragraphs: content.paragraphs)
        let decide = engine.decide
        deciding = Task { [weak self] in
            let outcome = await decide(sample, target)
            guard let self, !Task.isCancelled else { return }
            deciding = nil
            guard let job = state.press(title: title, content: content, target: target, decision: outcome) else { return }
            start(job)
        }
    }

    /// Back to the original: another article, or a second press. A running translation is dropped.
    func reset() {
        deciding?.cancel(); deciding = nil
        job = nil; configuration = nil
        state.reset()
    }

    func contentChanged(title: String, content: ArticleContent) {
        state.contentChanged(title: title, content: content)
        if state.key == nil, job != nil { job = nil; configuration = nil }
    }

    private func start(_ job: ArticleTranslation.Job) {
        if let batch = engine.batch {
            Task { await state.run(job, translate: batch, describe: Self.describe) }
            return
        }
        self.job = job
        var next = TranslationSession.Configuration(source: job.source.map { Locale.Language(identifier: $0) },
                                                    target: Locale.Language(identifier: job.plan.key.target))
        if next == configuration { next.invalidate() }      // the same pair again: run the task once more
        configuration = next
    }

    /// Runs inside `translationTask`: gets the language ready (the system may ask to download it), then translates the plan as a batch
    /// and hands each answer to `ArticleTranslation` by its index.
    func translate(with session: TranslationSession) async {
        guard let job else { return }
        let (answers, continuation) = AsyncThrowingStream<TranslationResponse, Error>.makeStream()
        let applying = Task { await state.run(job, translate: { _ in answers }, describe: Self.describe) }
        do {
            if await !session.isReady {
                state.preparing(job)
                try await session.prepareTranslation()
            }
            let requests = job.plan.items.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.index)) }
            for try await response in session.translate(batch: requests) {
                guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
                continuation.yield(TranslationResponse(index: index, text: response.targetText))
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
        await applying.value
    }

    /// One short sentence for the status row (specification 3.6).
    nonisolated static func describe(_ error: Error) -> String {
        guard let error = error as? TranslationError else { return String(localized: "Could not translate.", bundle: ReaderLocalization.bundle) }
        switch error {
        case TranslationError.unsupportedLanguagePairing, TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage:
            return String(localized: "This language pair is not supported.", bundle: ReaderLocalization.bundle)
        case TranslationError.notInstalled:
            return String(localized: "Language data is missing. The download may not have been allowed, or the Mac is offline.", bundle: ReaderLocalization.bundle)
        case TranslationError.unableToIdentifyLanguage:
            return String(localized: "The article's language could not be identified.", bundle: ReaderLocalization.bundle)
        default:
            return String(localized: "Could not translate.", bundle: ReaderLocalization.bundle)
        }
    }
}

/// A zero-size view that holds the system's translation session. It is the only place that touches `TranslationSession`.
struct TranslationHost: View {
    let controller: TranslationController
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(controller.configuration) { session in await controller.translate(with: session) }
            .accessibilityHidden(true)
    }
}

/// An empty view that lets a modifier find its window when a key arrives (#315).
struct WindowAnchor: NSViewRepresentable {
    @MainActor final class Reference { weak var view: NSView? }
    let reference: Reference
    func makeNSView(context: Context) -> NSView { let view = NSView(); reference.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { reference.view = view }
}

/// The translation status: short text at the left of the article band (specification 3.6, decision 0057).
struct TranslationStatusRow: View {
    let state: ArticleTranslation.State
    var target = "ja"
    let showOriginal: () -> Void

    var body: some View {
        if let content {
            HStack(spacing: 8) { content }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityElement(children: .combine)
        }
    }

    private var content: AnyView? {
        switch state {
        case .idle: nil
        case .preparing: AnyView(Text(String(localized: "Preparing languages…", bundle: ReaderLocalization.bundle)))
        case .translating(let done, let total): AnyView(Text(String(localized: "Translating \(done)/\(total)", bundle: ReaderLocalization.bundle)).monospacedDigit())
        case .done(let failed, let source):
            AnyView(Group {
                Text(Self.pair(source: source, target: target))
                if failed > 0 { Text(String(localized: "Untranslated paragraphs: \(failed)", bundle: ReaderLocalization.bundle)) }
                Button(String(localized: "Show Original", bundle: ReaderLocalization.bundle), action: showOriginal).buttonStyle(.link)
            })
        case .failed(let message): AnyView(Text(message))
        case .alreadyInTarget: AnyView(Text(String(localized: "Already in \(Self.name(target))", bundle: ReaderLocalization.bundle)))
        case .unsupported: AnyView(Text(String(localized: "This language pair is not supported.", bundle: ReaderLocalization.bundle)))
        }
    }

    /// 「英語 → 日本語」. The source is left out when the system detected it on its own.
    static func pair(source: String?, target: String) -> String {
        guard let source else { return "→ \(name(target))" }
        return "\(name(source)) → \(name(target))"
    }
    static func name(_ language: String) -> String {
        TranslationLanguages.name(language)
    }
}

/// The menu bar's 「表示 ▸ 翻訳 / 原文に戻す」, published by the library window.
struct TranslationCommand {
    let isOn: Bool
    let enabled: Bool
    let action: () -> Void
}

private struct TranslationCommandKey: FocusedValueKey { typealias Value = TranslationCommand }

extension FocusedValues {
    var translateArticle: TranslationCommand? {
        get { self[TranslationCommandKey.self] }
        set { self[TranslationCommandKey.self] = newValue }
    }
}

struct TranslationCommands: Commands {
    @FocusedValue(\.translateArticle) private var command

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(command?.isOn == true ? String(localized: "Return to Original", bundle: ReaderLocalization.bundle) : String(localized: "Translate", bundle: ReaderLocalization.bundle)) { command?.action() }
                .disabled(command?.enabled != true)
        }
    }
}

/// What the library window adds for translation: the key `t`, the menu bar command, the session's host, and the rule that another
/// article, or a changed text, shows the original. A modifier of its own: the window's chain is long (AGENTS.md known gotchas).
struct ArticleTranslationPresentation: ViewModifier {
    let controller: TranslationController
    let articleID: UUID?
    let title: String?
    let content: ArticleContent?
    /// No editable field is being typed in, and no sheet is open.
    let keysEnabled: Bool
    /// The original page is closed.
    let readerShown: Bool
    @AppStorage(TranslationTarget.key) private var storedTarget = ""
    @State private var supportedTargets: [String] = []
    @State private var targetsLoaded = false
    @State private var window = WindowAnchor.Reference()

    private func updateTarget() {
        guard targetsLoaded else { return }
        controller.setTarget(TranslationTarget.resolve(stored: storedTarget, preferred: TranslationLanguages.preferred,
                                                       supported: supportedTargets), supported: supportedTargets)
    }

    private var command: TranslationCommand {
        TranslationCommand(isOn: controller.isOn(for: articleID), enabled: canTranslate, action: toggle)
    }
    private var canTranslate: Bool { controller.targetReady && readerShown && articleID != nil && content?.articleID == articleID }
    private func toggle() {
        guard canTranslate, let title, let content else { return }
        controller.toggle(title: title, content: content)
    }

    func body(content view: Content) -> some View {
        view
            .background(TranslationHost(controller: controller))
            .background(WindowAnchor(reference: window).frame(width: 0, height: 0).accessibilityHidden(true))
            .task { supportedTargets = await controller.availableTargets(); targetsLoaded = true; updateTarget() }
            .onChange(of: storedTarget) { _, _ in updateTarget() }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in updateTarget() }
            .focusedSceneValue(\.translateArticle, command)
            // `keysEnabled` was decided when the window was last drawn. Where the keyboard is now is read here, at the key: the note's editor
            // can have it although the window was not drawn again (#315), and its `t` is a letter.
            .onKeyPress("t") {
                let responder = (window.view?.window ?? NSApp.keyWindow)?.firstResponder
                guard keysEnabled, !ReaderKeyboardCommands.isTextInput(responder), !ReaderKeyboardCommands.hasMarkedText(responder), canTranslate else { return .ignored }
                toggle(); return .handled
            }
            .onChange(of: articleID) { _, _ in controller.reset() }
            .onChange(of: content) { _, new in
                if let new, let title, new.articleID == articleID { controller.contentChanged(title: title, content: new) }
            }
    }
}
