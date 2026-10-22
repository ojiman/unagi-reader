import SwiftUI
import ReaderCore

/// A compact scope heading kept inside the list column, even while the sidebar is folded.
struct ListHeader: View {
    let title: String
    let count: Int
    var isFiltering = false

    static let sideMargin = NativeArticleList.Metrics.contentMargin
    static let fontSize: CGFloat = 12
    /// Every column reserves this space for its controls and window dragging.
    static let bandHeight: CGFloat = 52
    /// One heading line; the first article starts level with the first sidebar row.
    static let height: CGFloat = 19
    /// From the top of the column to the first article, level with the first sidebar row. It was the window's title bar (32 pt on
    /// macOS 27) plus `height`; a fixed value keeps it when native full-screen controls are detached (#373).
    static let listTopInset: CGFloat = 51

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).lineLimit(1).truncationMode(.tail)
            if isFiltering {
                Text(String(localized: "\(count) articles", bundle: ReaderLocalization.bundle))
                    .lineLimit(1).fixedSize().layoutPriority(1)
            }
        }
        .font(.system(size: Self.fontSize, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.sideMargin)
        .padding(.top, 3)
        .frame(height: Self.height, alignment: .top)
        .background(AppPalette.surfaceColor)
        .padding(.top, Self.bandHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
