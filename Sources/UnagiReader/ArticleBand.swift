import SwiftUI
import ReaderCore

/// The article column's band below the native toolbar (decisions 0057, 0065): the translation status at the left, the article's buttons at the
/// right, in one monochrome style. The empty part moves the window, as a title bar does.
struct ArticleBand: View {
    /// The column's own band below the native window toolbar.
    static let height = ListHeader.bandHeight
    /// The controls share one line inside each column's band.
    static let controlLine: CGFloat = 28
    static let controlTop: CGFloat = 2
    /// The band over the original page: only as high as its controls, so that no strip of empty band shows above the white page (#204).
    static let compactHeight: CGFloat = controlTop + controlLine + 4
    /// NSTextView's glyph inset puts the publisher level with the SwiftUI headings, below the controls.
    static let contentTop: CGFloat = ListHeader.bandHeight + 2

    let status: ArticleTranslation.State
    var translationTarget = "ja"
    let showOriginal: () -> Void
    let buttons: [BandButton]
    /// While the original page is open: its host name, and its ✕ in place of the status (decisions 0047, 0057).
    var originalHost: String? = nil
    var closeOriginal: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            if let originalHost {
                BandButton(id: "close-original", symbol: "xmark", help: String(localized: "Return to Article (Esc)", bundle: ReaderLocalization.bundle), label: String(localized: "Return to Article", bundle: ReaderLocalization.bundle), action: closeOriginal)
                Text(originalHost).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                TranslationStatusRow(state: status, target: translationTarget, showOriginal: showOriginal)
            }
            Spacer(minLength: 8)
            ForEach(buttons) { $0 }
        }
        .bandLayout(height: originalHost == nil ? Self.height : Self.compactHeight)
    }
}

extension View {
    /// The controls and drag area shared by each column's band.
    func bandLayout(height: CGFloat = ArticleBand.height) -> some View {
        padding(.horizontal, 12)
            .frame(height: ArticleBand.controlLine)
            .padding(.top, ArticleBand.controlTop)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background { BandDragArea() }
    }
}

/// One control of a band: a monochrome symbol of one size and one hit area. Colour only shows a state, through the symbol (filled).
struct BandButton: View, Identifiable {
    let id: String
    let symbol: String
    let help: String
    let label: String
    var enabled = true
    var shortcut: KeyboardShortcut? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .keyboardShortcut(shortcut)
        .help(help).accessibilityLabel(label)
        .disabled(!enabled)
    }
}

/// The empty part of a column band also moves the window.
struct BandDragArea: View {
    var body: some View {
        AppPalette.surfaceColor.contentShape(Rectangle()).gesture(WindowDragGesture())
    }
}
