import SwiftUI

/// Use AppKit's detached full-screen toolbar for the revealed window controls (#373). Normal windows have no toolbar and keep
/// their custom bands (decision 0057). Restore the actual normal frame after AppKit completes exit; keep the content mode unchanged.
struct FullScreenTitlebarFix: NSViewRepresentable {
    var sepia = ThemeState.shared.sepia

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.sepia = sepia }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stopObserving() }

    final class Anchor: NSView {
        private let center: NotificationCenter
        private var observers: [NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?
        private let toolbar = NSToolbar(identifier: "FullScreenControls")
        private var originalToolbar: NSToolbar?
        private var originalToolbarVisible = false
        private var originalToolbarStyle: NSWindow.ToolbarStyle?
        private var windowDelegate: WindowDelegate?
        private var normalFrame: NSRect?
        private weak var nativeButton: NSButton?
        private weak var tintedWindow: NSWindow?
        private var originalTransparency = false
        private var originalBackgroundColor: NSColor?
        var sepia = false { didSet { updateControlsAppearance() } }
        init(center: NotificationCenter = .default) { self.center = center; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            let delegate = WindowDelegate(original: window.delegate, anchor: self)
            observedWindow = window
            nativeButton = window.standardWindowButton(.closeButton)
            windowDelegate = delegate
            // This relies on SwiftUI not replacing window.delegate while the anchor remains attached.
            window.delegate = delegate
            observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.showToolbar(false) }
            })
            if window.styleMask.contains(.fullScreen) { showToolbar(true) }
        }
        func prepareForFullScreen() {
            if let window = observedWindow, normalFrame == nil, !window.styleMask.contains(.fullScreen) { normalFrame = window.frame }
            showToolbar(true)
        }
        func completeFullScreenEntry() {
            // Scene restoration can skip the earlier presentation-options callback.
            if observedWindow?.toolbar !== toolbar { showToolbar(true) }
            else { updateControlsAppearance() }
        }
        func updateControlsAppearance() { updateControlsAppearance(in: nativeButton?.window) }
        func updateControlsAppearance(in controlsWindow: NSWindow?) {
            // Full screen moves the cached native button into AppKit's separate toolbar window. Clear only its title-bar
            // background in Sepia, letting the reader's paper show through. Normal windows keep their own appearance.
            guard sepia, let controlsWindow, controlsWindow !== observedWindow else { restoreControlsAppearance(); return }
            if tintedWindow !== controlsWindow {
                restoreControlsAppearance()
                tintedWindow = controlsWindow
                originalTransparency = controlsWindow.titlebarAppearsTransparent
                originalBackgroundColor = controlsWindow.backgroundColor
            }
            controlsWindow.backgroundColor = AppPalette.paper
            controlsWindow.titlebarAppearsTransparent = true
        }
        private func restoreControlsAppearance() {
            if let window = tintedWindow {
                window.backgroundColor = originalBackgroundColor
                if window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = originalTransparency }
            }
            tintedWindow = nil
            originalBackgroundColor = nil
        }
        func finishFullScreen() {
            showToolbar(false)
            defer { normalFrame = nil }
            guard let window = observedWindow, let normalFrame, window.frame != normalFrame, let screen = window.screen else { return }
            // macOS 26 can restore the scene's unconstrained default, then fit it to the screen before didExit.
            // Fit the captured frame to the current screen in case displays changed during full screen.
            let frame = window.constrainFrameRect(normalFrame, to: screen)
            if window.frame != frame { window.setFrame(frame, display: true) }
        }
        func showToolbar(_ visible: Bool) {
            if !visible { restoreControlsAppearance() }
            guard let window = observedWindow else { return }
            if visible {
                if window.toolbar !== toolbar {
                    originalToolbar = window.toolbar
                    originalToolbarVisible = window.toolbar?.isVisible ?? false
                    window.toolbar = toolbar
                }
                // The compact bar fits the window buttons; the default style leaves a tall empty band below them (#435).
                if originalToolbarStyle == nil { originalToolbarStyle = window.toolbarStyle }
                window.toolbarStyle = .unifiedCompact
                toolbar.isVisible = true
                updateControlsAppearance()
            } else {
                if window.toolbar === toolbar {
                    window.toolbar = originalToolbar
                    originalToolbar?.isVisible = originalToolbarVisible
                }
                if let originalToolbarStyle { window.toolbarStyle = originalToolbarStyle }
                originalToolbarStyle = nil
                originalToolbar = nil
            }
        }
        func stopObserving() {
            for observer in observers { center.removeObserver(observer) }
            observers = []
            showToolbar(false)
            if let window = observedWindow, window.delegate === windowDelegate { window.delegate = windowDelegate?.original }
            observedWindow = nil
            windowDelegate = nil
            normalFrame = nil
            nativeButton = nil
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
            if options.contains(.fullScreen) { anchor?.prepareForFullScreen() } else { anchor?.showToolbar(false) }
            guard options.contains([.fullScreen, .autoHideMenuBar]) else { return options }
            return options.union(.autoHideToolbar)
        }
        func windowDidEnterFullScreen(_ notification: Notification) {
            original?.windowDidEnterFullScreen?(notification)
            anchor?.completeFullScreenEntry()
        }
        func windowDidExitFullScreen(_ notification: Notification) {
            original?.windowDidExitFullScreen?(notification)
            anchor?.finishFullScreen()
        }
        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            original?.windowDidFailToEnterFullScreen?(window)
            anchor?.finishFullScreen()
        }
        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            original?.windowDidFailToExitFullScreen?(window)
            anchor?.showToolbar(true)
        }
    }
}
