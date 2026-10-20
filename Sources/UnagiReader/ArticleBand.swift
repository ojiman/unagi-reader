import SwiftUI
import ReaderCore

/// The article column's band at the top of the window (decision 0057): the translation status at the left, the article's buttons at the
/// right, in one monochrome style. The empty part moves the window, as a title bar does.
struct ArticleBand: View {
    /// As high as the band of the window buttons.
    static let height = ListHeader.bandHeight
    /// The controls sit on the line of the window buttons and the sidebar's ＋ and refresh, about 13.5 pt below the top (measured in the
    /// running app on macOS 27.0.1).
    static let controlLine: CGFloat = 28
    static let controlTop: CGFloat = 2
    /// The band over the original page: only as high as its controls, so that no strip of empty band shows above the white page (#204).
    static let compactHeight: CGFloat = controlTop + controlLine + 4
    /// Room for the window buttons when the article column is at the window's left edge (the sidebar and the list are folded).
    static let windowButtonsWidth: CGFloat = 78
    /// NSTextView's glyph inset puts the publisher level with the SwiftUI headings, below the controls.
    static let contentTop: CGFloat = ListHeader.bandHeight + 2

    let status: ArticleTranslation.State
    var translationTarget = "ja"
    let showOriginal: () -> Void
    let buttons: [BandButton]
    /// The column starts at the window's left edge, under the window buttons.
    var atLeftEdge = false
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
        .bandLayout(atLeftEdge: atLeftEdge, height: originalHost == nil ? Self.height : Self.compactHeight)
    }
}

extension View {
    /// The layout every band shares: the controls on the window buttons' line, the band as high as the window buttons' band, its empty
    /// part moving the window.
    func bandLayout(atLeftEdge: Bool = false, height: CGFloat = ArticleBand.height) -> some View {
        padding(.horizontal, 12)
            .padding(.leading, atLeftEdge ? ArticleBand.windowButtonsWidth : 0)
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

/// The empty part of a band: dragging it moves the window (the window has no title bar of its own; decision 0057).
struct BandDragArea: View {
    var body: some View {
        AppPalette.surfaceColor.contentShape(Rectangle()).gesture(WindowDragGesture())
    }
}
