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

        init(center: NotificationCenter = .default) {
            self.center = center
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { Self.entering(window) } }
            })
            // Put back before the window returns to its old frame, so its size is kept.
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { Self.leaving(window) } }
            })
            // A window restored in full screen is already there.
            if window.styleMask.contains(.fullScreen) { Self.entering(window) }
        }
        static func entering(_ window: NSWindow) { window.styleMask.remove(.fullSizeContentView) }
        static func leaving(_ window: NSWindow) { window.styleMask.insert(.fullSizeContentView) }
        func stopObserving() {
            for observer in observers { center.removeObserver(observer) }
            observers = []
        }
    }
}
