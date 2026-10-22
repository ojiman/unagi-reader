import SwiftUI

/// Use AppKit's detached full-screen toolbar for the revealed window controls (#373). Normal windows have no toolbar and keep
/// their custom bands (decision 0057). This component does not change the content mode or correct the window frame.
struct FullScreenTitlebarFix: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stopObserving() }

    final class Anchor: NSView {
        private let center: NotificationCenter
        private var observers: [NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?
        private let toolbar = NSToolbar(identifier: "FullScreenControls")
        private var originalToolbar: NSToolbar?
        private var originalToolbarVisible = false
        private var windowDelegate: WindowDelegate?
        init(center: NotificationCenter = .default) { self.center = center; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let delegate = WindowDelegate(original: window.delegate, anchor: self)
            observedWindow = window
            windowDelegate = delegate
            window.delegate = delegate
            trace("attached")
            if ProcessInfo.processInfo.environment["UNAGI_FULLSCREEN_TRACE"] != nil {
                for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didResizeNotification, NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                    let event = name.rawValue, stack = name == NSWindow.didResizeNotification
                    observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.trace(event, stack: stack) }
                    })
                }
            }
            for name in [NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.showToolbar(false) }
                })
            }
            if window.styleMask.contains(.fullScreen) { showToolbar(true) }
        }
        func trace(_ event: String, stack: Bool = false) {
            guard let path = ProcessInfo.processInfo.environment["UNAGI_FULLSCREEN_TRACE"], let window = observedWindow else { return }
            let line = "\(ProcessInfo.processInfo.systemUptime) \(event) frame=\(window.frame) min=\(window.minSize) contentMin=\(window.contentMinSize) content=\(window.contentView?.frame ?? .zero) layout=\(window.contentLayoutRect) style=\(window.styleMask.rawValue) toolbar=\(window.toolbar != nil) delegate=\(String(describing: windowDelegate?.original))\n" + (stack ? Thread.callStackSymbols.joined(separator: "\n") + "\n" : "")
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            do {
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: Data(line.utf8))
            } catch { print("Full-screen trace failed: \(error)") }
        }
        func showToolbar(_ visible: Bool) {
            guard let window = observedWindow else { return }
            trace("toolbar before \(visible)")
            if visible {
                if window.toolbar !== toolbar {
                    originalToolbar = window.toolbar
                    originalToolbarVisible = window.toolbar?.isVisible ?? false
                    window.toolbar = toolbar
                }
                toolbar.isVisible = true
            } else {
                if window.toolbar === toolbar {
                    window.toolbar = originalToolbar
                    originalToolbar?.isVisible = originalToolbarVisible
                }
                originalToolbar = nil
            }
            trace("toolbar after \(visible)")
        }
        func stopObserving() {
            for observer in observers { center.removeObserver(observer) }
            observers = []
            showToolbar(false)
            if let window = observedWindow, window.delegate === windowDelegate { window.delegate = windowDelegate?.original }
            observedWindow = nil
            windowDelegate = nil
        }
    }

    final class WindowDelegate: NSObject, NSWindowDelegate {
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
        func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
            let options = original?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
            anchor?.showToolbar(options.contains(.fullScreen))
            guard options.contains([.fullScreen, .autoHideMenuBar]) else { return options }
            return options.union(.autoHideToolbar)
        }
        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            original?.windowDidFailToEnterFullScreen?(window)
            anchor?.showToolbar(false)
        }
        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            original?.windowDidFailToExitFullScreen?(window)
            anchor?.showToolbar(true)
        }
    }
}
