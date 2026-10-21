import SwiftUI
import ReaderCore

/// Library actions stay in the native toolbar while any reader column is folded.
struct LibraryToolbarControls: View {
    var refreshing: Bool
    var onAdd: () -> Void
    var onRefresh: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) { Image(systemName: "plus").frame(width: 28, height: 28) }
                .help(String(localized: "Add Subscription from URL", bundle: ReaderLocalization.bundle)).accessibilityLabel(String(localized: "Add Subscription", bundle: ReaderLocalization.bundle))
            // The arrow itself turns while the feeds are being updated (the system stops the motion for Reduce Motion).
            // The button is not disabled: pressing it again while it works does nothing (FeedRefreshController.refresh).
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: refreshing)
                    .frame(width: 28, height: 28)
            }.help(String(localized: "Refresh Subscriptions", bundle: ReaderLocalization.bundle)).accessibilityLabel(String(localized: "Refresh Subscriptions", bundle: ReaderLocalization.bundle)).accessibilityValue(refreshing ? String(localized: "Refreshing", bundle: ReaderLocalization.bundle) : "")
        }.buttonStyle(.borderless)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 12)
    }
}
