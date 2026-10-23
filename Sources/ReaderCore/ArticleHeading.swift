import Foundation

/// The date line under an article's title (specification 3.1.4).
public enum ArticleHeading {
    /// The weekday, date and time of publication, in the person's time zone and format.
    public static func date(_ date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard date != .distantPast else { return String(localized: "Publication date unknown", bundle: ReaderLocalization.bundle) }
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day().year().hour().minute()
        style.locale = locale; style.timeZone = timeZone
        return date.formatted(style)
    }
}

extension ReaderStore {
    /// The name an article's list row and reading heading show: its subscription's, or its site's when the subscription is gone
    /// (specification 3.0).
    public func sourceName(of article: Article) -> String { feed(id: article.feedID)?.displayTitle ?? article.displayPublisher }
}
