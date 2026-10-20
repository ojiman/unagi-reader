import SwiftUI
import ReaderCore

struct ArticleDetailView: View {
    let article: Article
    let content: ArticleContent?
    let expiry: Date?
    let updateAvailable: Bool
    let error: String?
    let initialAnchor: String?
    let initialOffset: Double
    let onScroll: (String, Double) -> Void
    let onInteraction: () -> Void
    let onUpdate: () -> Void
    let onDisplayBegin: () -> Void
    let onDisplayed: () -> Void
    let imageLoader: ReaderImageLoader
    var pageForward = true
    /// False while the original page covers the reader text: the page's slide-out is the only motion then (one motion at a time).
    var pageMotion = true
    /// The translated title and paragraphs to show in place of the original (specification 3.6). The status is in the article band.
    var translated: TranslatedArticle? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settings ▸ 「外観」 ▸ 「文字サイズ」 (specification 3.7).
    @AppStorage(ArticleTextSize.key) private var textSize = ArticleTextSize.standard

    private var available: Bool { content?.articleID == article.id && (expiry ?? .distantPast) > .now }
    private var date: String { article.publishedAt == .distantPast ? String(localized: "Publication date unknown", bundle: ReaderLocalization.bundle) : article.publishedAt.formatted(.dateTime.year().month().day()) }
    private var title: String {
        let value = translated?.title ?? article.title
        return value.isEmpty ? article.displayTitle : value
    }
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: ArticleBand.contentTop)              // the publisher sits below the column controls
            if updateAvailable || error != nil {
                HStack {
                    if updateAvailable { Button(String(localized: "Show fetched body", bundle: ReaderLocalization.bundle), action: onUpdate).buttonStyle(.link) }
                    if let error { Text(error) }
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
            NativeArticleText(articleID: article.id, title: title, publisher: article.displayPublisher.uppercased(), date: date,
                paragraphs: available ? (translated?.paragraphs.map(\.text) ?? content!.paragraphs) : [],
                unavailable: available ? nil : (article.contentDeletedAt != nil ? String(localized: "The article body and RSS summary have been deleted.", bundle: ReaderLocalization.bundle) : String(localized: "The article body is unavailable.", bundle: ReaderLocalization.bundle)),
                initialAnchor: initialAnchor, initialOffset: initialOffset, reduceMotion: reduceMotion || !pageMotion, onScroll: onScroll, onInteraction: onInteraction, onDisplayBegin: onDisplayBegin, onDisplayed: onDisplayed,
                imageLoader: imageLoader, heroURL: available ? article.imageURL.flatMap { ArticleURL.validated($0) } : nil,
                bodyParagraphs: available ? (translated?.paragraphs ?? content!.bodyParagraphs) : nil, pageForward: pageForward,
                textScale: CGFloat(ArticleTextSize.scale(textSize)))
        }.background(AppPalette.surfaceColor)
    }
}
