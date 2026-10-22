import SwiftUI
import AppKit
import ReaderCore

/// SwiftUI folds the width without asking AppKit to resize the window; AppKit restores width and focus.
struct ListColumnCollapse: ViewModifier, Animatable {
    var collapsed: Bool
    var animated: Bool
    let space: WindowSpace
    @State private var rememberedWidth = NotePanelWidth.listDefaultWidth
    private var fraction: Double
    init(collapsed: Bool, animated: Bool, space: WindowSpace) {
        self.collapsed = collapsed
        self.animated = animated
        self.space = space
        fraction = collapsed ? 0 : 1
    }
    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        let moves = animated && SidebarFold.animatesListFold(windowWidth: space.width)
        let shown = moves ? fraction : (collapsed ? 0.0 : 1.0)
        content
            .frame(width: shown < 1 ? rememberedWidth * shown : nil)
            .clipped()
            .accessibilityHidden(collapsed)
            .allowsHitTesting(!collapsed)
            .navigationSplitViewColumnWidth(
                min: NotePanelWidth.listMinimum * shown,
                ideal: rememberedWidth * shown,
                max: 640 * shown
            )
            .transaction { transaction in
                if !animated || !SidebarFold.animatesListFold(windowWidth: space.width) {
                    transaction.animation = nil
                }
            }
            .background(Anchor(collapsed: collapsed, expanded: shown == 1, width: rememberedWidth, space: space))
            .onChange(of: space.listWidth) { _, width in
                if !collapsed && shown == 1 { rememberedWidth = width }
            }
    }

    private struct Anchor: NSViewRepresentable {
        var collapsed: Bool
        var expanded: Bool
        let width: Double
        let space: WindowSpace
        func makeNSView(context: Context) -> Probe { Probe() }
        func updateNSView(_ view: Probe, context: Context) {
            view.space = space
            view.apply(collapsed: collapsed, expanded: expanded, width: width)
        }
    }

    @MainActor final class Probe: NSView {
        var space: WindowSpace?
        private var wanted: Bool?
        private var expanded = false
        private var updateQueued = false
        private var needsFocus = false

        private var restoring: Task<Void, Never>?
        private var widthToRestore: Double?
        func apply(collapsed: Bool, expanded: Bool, width: Double) {
            if wanted != collapsed {
                needsFocus = true
                restoring?.cancel()
                widthToRestore = wanted != nil && !collapsed ? width : nil
            }
            wanted = collapsed
            self.expanded = expanded
            scheduleUpdate()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleUpdate()
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if expanded, newSize.width >= NotePanelWidth.listMinimum, let space,
               abs(space.listWidth - newSize.width) > 0.5 {
                let width = newSize.width
                DispatchQueue.main.async { [weak self, weak space] in
                    guard let self, self.wanted == false, self.expanded, abs(self.bounds.width - width) < 0.5 else { return }
                    space?.listWidth = width
                }
            }
            scheduleUpdate()
        }
        private func scheduleUpdate() {
            guard !updateQueued else { return }
            updateQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateQueued = false
                self.update()
            }
        }
        private func update() {
            guard let wanted, let window, let item = SplitViewItemLookup(holding: self)?.item else { return }
            // A saved native split-view state may contain a collapsed middle column (#195).
            // Normal folds use the SwiftUI width preference instead.
            if item.isCollapsed { item.isCollapsed = false }
            if item.canCollapse { item.canCollapse = false }
            if expanded, let width = widthToRestore {
                widthToRestore = nil
                restoreWidth(width, of: item)
            }
            guard needsFocus else { return }
            needsFocus = false
            guard let content = window.contentView,
                  !ReaderKeyboardCommands.isTextInput(window.firstResponder) else { return }
            if wanted {
                window.makeFirstResponder(Self.first(ArticleTextView.self, in: content) ?? content)
            } else if let page = ReaderKeyboardCommands.originalPage(in: content) {
                window.makeFirstResponder(page)
            } else if let table = Self.first(NativeArticleList.Table.self, in: content) {
                window.makeFirstResponder(table)
            }
        }
        private func restoreWidth(_ width: Double, of item: NSSplitViewItem) {
            restoring = Task { @MainActor [weak self, weak item] in
                for _ in 0..<40 {
                    guard let self, let item, self.wanted == false, !Task.isCancelled else { return }
                    if let found = SplitViewItemLookup(holding: self), found.item === item {
                        let others = found.controller.splitViewItems.filter { $0 !== item && !$0.isCollapsed }
                            .reduce(0.0) { $0 + max($1.minimumThickness, $1.viewController.view.fittingSize.width) }
                        if width + others + Double(found.controller.splitViewItems.count - 1) <= found.split.bounds.width {
                            let missing = width - self.bounds.width
                            if abs(missing) < 1 { return }
                            found.split.setPosition(item.viewController.view.frame.maxX + missing, ofDividerAt: found.index)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            for child in view.subviews {
                if let result = first(type, in: child) { return result }
            }
            return nil
        }
    }
}
