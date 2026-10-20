import SwiftUI
import AppKit
import ReaderCore

/// Folds the list column away and brings it back with the system's own move of a split view (decision 0049).
///
/// SwiftUI's `NavigationSplitView` can fold the sidebar (`columnVisibility`) but not the middle column: `.detailOnly` leaves it where
/// it is, and the system sets `canCollapse` to false on that column. The AppKit item behind it can fold when `canCollapse` is true for
/// the moment of the change. This view finds that item from inside the list column and sets `isCollapsed` in an animation of
/// `SidebarFold.motionDuration`, so it runs together with the sidebar's own fold.
///
/// This is a workaround kept in this one file. To take it out: delete this file and the `background` that uses it in `ReaderView`.
struct ListColumnCollapse: NSViewRepresentable {
    var collapsed: Bool
    /// False for Reduce Motion: the column changes at once (so it does in a narrow window, see `SidebarFold.animatesListFold`).
    var animated: Bool
    /// The window's room, read when the list comes back (never in `body`: a resize must not redraw the reader).
    let space: WindowSpace

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.space = space; view.apply(collapsed: collapsed, animated: animated) }

    @MainActor final class Probe: NSView {
        var space: WindowSpace?
        private var wanted: Bool?
        private var animated = true
        /// The first change (the window has just opened) is made at once.
        private var isFirst = true

        func apply(collapsed: Bool, animated: Bool) {
            wanted = collapsed; self.animated = animated
            update()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            update()
        }

        /// The window can fold the list by itself after the first change: it restores the split view's saved state, which holds a folded
        /// list when the app ended without quitting while the note was open (#195). The note starts closed, so the list is put back. This
        /// view fills the list, so a fold resizes it; the check runs after that layout pass.
        private var moving = false
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportWidth(newSize.width)
            guard !moving, wanted == false else { return }
            DispatchQueue.main.async { [weak self] in self?.keepWanted() }
        }
        /// This view fills the list: its width is the list's. Only widths from the list's minimum up are reported (not while it folds or comes
        /// back), and not inside the layout pass: the note's column reads it, and a change there during the layout looped (#222).
        private func reportWidth(_ width: CGFloat) {
            guard width >= NotePanelWidth.listMinimum, let space, abs(space.listWidth - width) > 0.5 else { return }
            DispatchQueue.main.async { [weak space] in space?.listWidth = width }
        }
        private func keepWanted() {
            guard !moving, wanted == false, let window, let item = listItem(), item.isCollapsed else { return }
            item.isCollapsed = false
            finish(item, window: window, collapsed: false)
        }

        /// The width the list had before it was folded. When it comes back the note's panel is still there for the first frames of the
        /// move, so the split view gives the list only the room that is left (its smallest width); `restoreWidth` sets the old width
        /// again after the move.
        private var widthBeforeFold: CGFloat?

        /// The split view item whose view holds this one.
        private func listItem() -> NSSplitViewItem? {
            var view: NSView? = superview
            while let current = view {
                if let split = current as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
                   let item = controller.splitViewItems.first(where: { isDescendant(of: $0.viewController.view) }) {
                    return item
                }
                view = current.superview
            }
            return nil
        }

        private func update() {
            guard let wanted, let window, let item = listItem() else { return }
            let immediate = isFirst || !animated || !SidebarFold.animatesListFold(windowWidth: window.frame.width)
            isFirst = false
            guard item.isCollapsed != wanted else { return }
            restoring?.cancel()
            if wanted { widthBeforeFold = bounds.width }
            item.canCollapse = true
            if immediate {
                item.isCollapsed = wanted
                finish(item, window: window, collapsed: wanted)
            } else {
                moving = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = SidebarFold.motionDuration
                    context.allowsImplicitAnimation = true
                    item.animator().isCollapsed = wanted
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated { self?.settled(collapsed: wanted) }
                }
            }
        }

        private func settled(collapsed: Bool) {
            moving = false
            guard let window, let item = listItem() else { return }
            finish(item, window: window, collapsed: collapsed)
        }

        /// After the change: the list cannot be folded by dragging its edge (only by this view); and the keyboard goes where the person is
        /// reading: to the article when the list is gone, to the list when it is back, or to the original page beside it (unless they are
        /// typing in the note).
        private func finish(_ item: NSSplitViewItem, window: NSWindow, collapsed: Bool) {
            if !collapsed {
                item.canCollapse = false
                restoreWidth(of: item)
            }
            guard let content = window.contentView, !ReaderKeyboardCommands.isTextInput(window.firstResponder) else { return }
            if collapsed {
                // The reader's text if there is one; otherwise the window's own view, so that the keys still reach the reader and the
                // note's editor does not take the keyboard just because the list is gone.
                if let article = Self.first(ArticleTextView.self, in: content) { window.makeFirstResponder(article) }
                else { window.makeFirstResponder(content) }
            } else if let page = ReaderKeyboardCommands.originalPage(in: content) {
                window.makeFirstResponder(page)                            // the list is back beside the original page, which keeps the keyboard
            } else if let table = Self.first(NativeArticleList.Table.self, in: content) {
                window.makeFirstResponder(table)
            }
        }

        /// Puts the list back to the width it had. The note's panel may still be leaving when the move ends (it takes longer under load), so
        /// this tries again every 50 ms until the width is right, for at most 2 seconds. The width is that of this view, which fills the
        /// list (the column's own frame can reach under the sidebar).
        private func restoreWidth(of item: NSSplitViewItem) {
            guard let remembered = widthBeforeFold, remembered > 0 else { return }
            // Not wider than the room that is left beside the note: the article keeps its minimum, and the note does not have to shrink.
            let saved = space.map { min(remembered, max(NotePanelWidth.listMinimum, $0.width - NotePanelWidth.articleMinimum - $0.noteWidth)) } ?? remembered
            restoring?.cancel()
            restoring = Task { @MainActor [weak self, weak item] in
                for _ in 0..<40 {
                    guard let self, let item, !Task.isCancelled, !item.isCollapsed else { return }
                    let missing = saved - self.bounds.width
                    if missing <= 1 { return }
                    if let controller = self.enclosingController(of: item), let index = controller.splitViewItems.firstIndex(of: item) {
                        controller.splitView.setPosition(item.viewController.view.frame.maxX + missing, ofDividerAt: index)
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        private var restoring: Task<Void, Never>?

        private func enclosingController(of item: NSSplitViewItem) -> NSSplitViewController? {
            var view: NSView? = superview
            while let current = view {
                if let split = current as? NSSplitView, let controller = split.delegate as? NSSplitViewController, controller.splitViewItems.contains(item) {
                    return controller
                }
                view = current.superview
            }
            return nil
        }

        private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { first(type, in: $0) }.first
        }
    }
}
