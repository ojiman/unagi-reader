import SwiftUI
import ReaderCore

/// One subscription's row in the sidebar. It compares equal while what it shows is the same, so a selection or a read mark elsewhere in the
/// window does not rebuild every row (#249). The actions are not compared: they only reach the window's state.
struct SubscriptionRow: View, Equatable {
    struct Actions {
        var finishEdit: (String?) -> Void
        var refresh: () -> Void
        var rename: () -> Void
        var beginMove: () -> Void
        var endMove: () -> Void
        var move: (String) -> Void
        var unsubscribe: () -> Void
    }

    let feed: Feed
    let feedID: UUID
    let title: String
    let folder: String
    let folders: [String]
    let unread: Int
    let error: String?
    /// The name when it is edited in place; nil for every other row.
    let editing: String?
    let moving: Bool
    /// Not shown, but the move action reads it: a change rebuilds the row so the action is current.
    let reduceMotion: Bool
    let imageLoader: ReaderImageLoader
    let actions: Actions

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.feedID == b.feedID && a.title == b.title && a.folder == b.folder && a.folders == b.folders && a.unread == b.unread
            && a.error == b.error && a.editing == b.editing && a.moving == b.moving && a.reduceMotion == b.reduceMotion && a.imageLoader === b.imageLoader
    }

    var body: some View {
        HStack {
            SubscriptionIconView(feed: feed, loader: imageLoader)
            if let editing { InlineNameField(initial: editing, onFinish: actions.finishEdit) }
            else { Text(title).lineLimit(1) }
            Spacer()
            Text(unread.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let error {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).help(error)
                    .accessibilityLabel(String(localized: "Refresh failed: \(error)", bundle: ReaderLocalization.bundle))
            }
        }.padding(.vertical, 4)
            .draggable(FeedDrag(id: feedID))
            .popover(isPresented: Binding(get: { moving }, set: { if !$0 { actions.endMove() } }), arrowEdge: .trailing) {
                MoveToFolderView(folders: folders, current: folder, onMove: actions.move, onClose: actions.endMove)
            }
            .contextMenu {
                Button(String(localized: "Refresh This Subscription", bundle: ReaderLocalization.bundle), action: actions.refresh)
                Button(String(localized: "Rename", bundle: ReaderLocalization.bundle), action: actions.rename)
                Button(String(localized: "Move to Folder…", bundle: ReaderLocalization.bundle), action: actions.beginMove)
                Button(String(localized: "Unsubscribe…", bundle: ReaderLocalization.bundle), role: .destructive, action: actions.unsubscribe)
            }
    }
}
