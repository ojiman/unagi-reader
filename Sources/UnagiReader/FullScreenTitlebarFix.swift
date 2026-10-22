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
            trace("move.beforeStop")
            stopObserving()
            guard let window else { return }
            let delegate = FailureDelegate(original: window.delegate, anchor: self)
            observedWindow = window
            failureDelegate = delegate
            window.delegate = delegate
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.trace("willEnter.before")
                    if self.normalSize == nil { self.normalSize = window.frame.size }
                    self.trace("willEnter.after")
                }
            })
            // Changing a normal window's content mode changes its frame; let AppKit enter first.
            observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.trace("didEnter.before")
                    Self.entering(window)
                    self.trace("didEnter.after")
                }
            })
            // Put the content mode back before AppKit restores the normal frame.
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.trace("willExit.before")
                    Self.leaving(window)
                    self.trace("willExit.after")
                }
            })
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { self.trace("resized") } }
            })
            // A window restored in full screen is already there.
            if window.styleMask.contains(.fullScreen) { Self.entering(window) }
        }
        static func entering(_ window: NSWindow) { window.styleMask.remove(.fullSizeContentView) }
        static func leaving(_ window: NSWindow) { window.styleMask.insert(.fullSizeContentView) }
        func restoreNormalSize(_ window: NSWindow) {
            trace("didExit.before")
            guard let size = normalSize else { return }
            normalSize = nil
            guard window.frame.size != size else { return }
            // Small displays can return at a different size. Preserve the actual size and AppKit's restored top-left.
            var frame = window.frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
            trace("didExit.after")
        }
        fileprivate func trace(_ event: String) {
            guard let path = ProcessInfo.processInfo.environment["UNAGI_FULLSCREEN_TRACE"] else { return }
            let frame = window.map { NSStringFromRect($0.frame) } ?? "nil"
            let content = window?.contentView.map { NSStringFromRect($0.frame) } ?? "nil"
            let saved = normalSize.map(NSStringFromSize) ?? "nil"
            let line = "\(ProcessInfo.processInfo.systemUptime) \(ObjectIdentifier(self)) \(event) frame=\(frame) content=\(content) saved=\(saved) style=\(window?.styleMask.rawValue ?? 0)\n"
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let file = try? FileHandle(forWritingTo: url) {
                defer { try? file.close() }
                _ = try? file.seekToEnd()
                try? file.write(contentsOf: Data(line.utf8))
            }
        }
        func stopObserving() {
            trace("stop")
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

    /// Run the existing exit handler before correcting its restored frame; forward other delegate messages unchanged.
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
        func windowDidExitFullScreen(_ notification: Notification) {
            anchor?.trace("delegateExit.beforeOriginal")
            original?.windowDidExitFullScreen?(notification)
            anchor?.trace("delegateExit.afterOriginal")
            if let window = notification.object as? NSWindow { anchor?.restoreNormalSize(window) }
            anchor?.trace("delegateExit.afterCorrection")
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
