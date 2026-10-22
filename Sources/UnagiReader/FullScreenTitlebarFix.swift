import SwiftUI

/// In full screen the window's content does not run under the title bar. With full-size content, the title bar that comes down
/// with the menu bar drew the window buttons, but their clicks went to the content below them, and the green button could not
/// leave full screen (#373). The normal window keeps its hidden title bar (decision 0057).
struct FullScreenTitlebarFix: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stopObserving() }

    final class Anchor: NSView {
        private let center: NotificationCenter
        private var observers: [NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?
        private var failureDelegate: FailureDelegate?
        private var normalSize: NSSize?

        init(center: NotificationCenter = .default) {
            self.center = center
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let delegate = FailureDelegate(original: window.delegate, anchor: self)
            observedWindow = window
            failureDelegate = delegate
            window.delegate = delegate
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    if self.normalSize == nil { self.normalSize = window.frame.size }
                    Self.entering(window)
                }
            })
            // Put the content mode back before AppKit restores the normal frame.
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { Self.leaving(window) } }
            })
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated { if let window { self?.restoreNormalSize(window) } }
            })
            // A window restored in full screen is already there.
            if window.styleMask.contains(.fullScreen) { Self.entering(window) }
        }
        static func entering(_ window: NSWindow) { window.styleMask.remove(.fullSizeContentView) }
        static func leaving(_ window: NSWindow) { window.styleMask.insert(.fullSizeContentView) }
        func restoreNormalSize(_ window: NSWindow) {
            guard let size = normalSize else { return }
            normalSize = nil
            guard window.frame.size != size else { return }
            // Small displays can return at a different size. Preserve the actual size and AppKit's restored top-left.
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
        func stopObserving() {
            for observer in observers { center.removeObserver(observer) }
            observers = []
            if let window = observedWindow, window.delegate === failureDelegate {
                window.delegate = failureDelegate?.original
            }
            observedWindow = nil
            failureDelegate = nil
            normalSize = nil
        }
    }

    /// Failure callbacks have no notification equivalent. Every other delegate message keeps SwiftUI's receiver.
    final class FailureDelegate: NSObject, NSWindowDelegate {
        weak var original: (any NSWindowDelegate)?
        private weak var anchor: Anchor?
        init(original: (any NSWindowDelegate)?, anchor: Anchor) {
            self.original = original
            self.anchor = anchor
            super.init()
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            if let original, original.responds(to: selector) { return original }
            return super.forwardingTarget(for: selector)
        }
        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            original?.windowDidFailToEnterFullScreen?(window)
            Anchor.leaving(window)
            anchor?.restoreNormalSize(window)
        }
        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            original?.windowDidFailToExitFullScreen?(window)
            Anchor.entering(window)
        }
    }
}
