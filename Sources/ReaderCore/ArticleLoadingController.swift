import Foundation
import Observation

@Observable @MainActor public final class ArticleLoadingController {
    public private(set) var displayed: ArticleContent?
    public private(set) var availableUpdate: ArticleContent?
    public private(set) var error: String?
    private var state = ArticleLoadingState()
    private let store: ReaderStore
    @ObservationIgnored private let now: @MainActor () -> Date
    public init(store: ReaderStore, now: @escaping @MainActor () -> Date = { .now }) {
        self.store = store; self.now = now
    }
    public func clear() { state = ArticleLoadingState(); displayed = nil; availableUpdate = nil }
    /// Shows what the feed gave. The original page is never fetched for the reader (decisions 0033 and 0056): it is read with `v` or `b`.
    public func load(articleID: UUID) {
        state.begin(articleID: articleID)
        error = nil; availableUpdate = nil
        do { displayed = try store.content(articleID: articleID, at: now()) } catch { self.error = error.localizedDescription; displayed = nil }
    }
    public func recordInteraction(articleID: UUID) { state.recordInteraction(articleID: articleID) }
    public func refreshCachedContent() {
        guard let id = state.selectedArticleID else { return }
        do {
            guard let latest = try store.content(articleID: id, at: now()) else { displayed = nil; availableUpdate = nil; return }
            // Check using the active generation without resetting its interaction history.
            if state.mayReplaceCurrentDisplay { displayed = latest; availableUpdate = nil }
            else if displayed != latest { availableUpdate = latest }
        } catch { self.error = error.localizedDescription }
    }
    public func applyAvailableUpdate() throws {
        guard let id = state.selectedArticleID, availableUpdate?.articleID == id else { return }
        displayed = try store.content(articleID: id, at: now()); availableUpdate = nil
    }
}
