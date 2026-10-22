import AppKit

/// The system split view item that holds a view: the one way `ListColumnCollapse` and `NoteColumnHold` reach the AppKit split view
/// behind SwiftUI's `NavigationSplitView` and `inspector`.
///
/// SwiftUI does not promise that an `NSSplitViewController` is there, so a macOS update can change it. Then this finds nothing and the
/// probes do nothing (`theListStillFoldsWhenNoSplitViewItemCanBeFound`). `theSplitViewStillHasTheShapeTheProbesAssume` names what it
/// assumes.
@MainActor struct SplitViewItemLookup {
    let split: NSSplitView
    let controller: NSSplitViewController
    let item: NSSplitViewItem
    /// The item's place among the controller's items; the divider before it has `index - 1`.
    let index: Int

    /// Walks up from `view` to the nearest split view whose controller has an item that holds `view`.
    init?(holding view: NSView) {
        var current = view.superview
        while let candidate = current {
            if let split = candidate as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
               let index = controller.splitViewItems.firstIndex(where: { view.isDescendant(of: $0.viewController.view) }) {
                self.split = split
                self.controller = controller
                self.item = controller.splitViewItems[index]
                self.index = index
                return
            }
            current = candidate.superview
        }
        return nil
    }
}
