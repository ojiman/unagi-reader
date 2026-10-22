import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

extension SplitViewFoldTests {
    /// Private notifications exercise attachment without sending fake full-screen events to AppKit.
    @Suite(.serialized) @MainActor struct FullScreenTitlebarTests {
        @Test func theFullScreenToolbarDoesNotChangeTheNormalFrame() throws {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 650),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let center = NotificationCenter()
            let anchor = FullScreenTitlebarFix.Anchor(center: center)
            let frame = window.frame
            try #require(window.contentView).addSubview(anchor)
            #expect(window.toolbar == nil)
            #expect(window.frame == frame)
            for _ in 0..<3 {
                let options: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
                _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: options)
                let toolbar = try #require(window.toolbar)
                #expect(toolbar.isVisible)
                #expect(window.frame == frame, "Preparing native full-screen controls must preserve the normal frame")
                #expect(window.styleMask.contains(.fullSizeContentView))
                window.delegate?.windowDidFailToEnterFullScreen?(window)
                #expect(window.toolbar == nil)
                _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: options)
                center.post(name: NSWindow.willExitFullScreenNotification, object: window)
                #expect(window.toolbar == nil)
                window.delegate?.windowDidFailToExitFullScreen?(window)
                #expect(toolbar.isVisible)
                window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
                #expect(window.toolbar == nil)
                #expect(window.frame == frame)
            }
            anchor.removeFromSuperview()
            #expect(window.toolbar == nil)
            _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: [.fullScreen, .autoHideMenuBar])
            #expect(window.toolbar == nil)
        }
    }

    @Suite(.serialized) @MainActor struct FullScreenPresentationTests {
        @MainActor private final class WindowDelegate: NSObject, NSWindowDelegate {
            var calls = 0
            var removeMenuHiding = false
            var entryFailures = 0
            var exitFailures = 0
            var exits = 0
            var exitFrame: NSRect?
            func windowDidExitFullScreen(_ notification: Notification) {
                exits += 1
                if let exitFrame, let window = notification.object as? NSWindow { window.setFrame(exitFrame, display: false) }
            }
            func windowDidFailToEnterFullScreen(_ window: NSWindow) { entryFailures += 1 }
            func windowDidFailToExitFullScreen(_ window: NSWindow) { exitFailures += 1 }
            func windowShouldClose(_ window: NSWindow) -> Bool { false }
            func window(_ window: NSWindow, willUseFullScreenPresentationOptions options: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
                calls += 1
                var result = options.union(.disableHideApplication)
                if removeMenuHiding { result.remove(.autoHideMenuBar) }
                return result
            }
        }

        @Test func nativePresentationPreservesTheOriginalOptionsAndNormalFrame() throws {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 650),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let original = WindowDelegate()
            window.delegate = original
            let anchor = FullScreenTitlebarFix.Anchor(center: NotificationCenter())
            try #require(window.contentView).addSubview(anchor)
            let frame = window.frame
            let proposed: NSApplication.PresentationOptions = [.fullScreen, .autoHideMenuBar, .autoHideDock]
            let options = window.delegate?.window?(window, willUseFullScreenPresentationOptions: proposed)
            #expect(options == proposed.union([.autoHideToolbar, .disableHideApplication]))
            #expect(original.calls == 1)
            #expect(window.frame == frame)
            #expect(window.styleMask.contains(.fullSizeContentView))
            // Respect the existing delegate and an always-visible menu bar; autoHideToolbar would be invalid without hiding it.
            original.removeMenuHiding = true
            let visibleMenu = window.delegate?.window?(window, willUseFullScreenPresentationOptions: proposed)
            #expect(visibleMenu == proposed.subtracting(.autoHideMenuBar).union(.disableHideApplication))
            window.delegate?.windowDidFailToEnterFullScreen?(window)
            window.delegate?.windowDidFailToExitFullScreen?(window)
            #expect(original.entryFailures == 1)
            #expect(original.exitFailures == 1)
            #expect(window.delegate?.windowShouldClose?(window) == false)
            anchor.removeFromSuperview()
            #expect(window.delegate === original)
        }

        /// #373: macOS 26 can restore the scene's unconstrained default size before announcing completed exit.
        @Test func completedExitRestoresTheActualFrameAfterTheOriginalDelegate() throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.center()
            let original = WindowDelegate()
            window.delegate = original
            let anchor = FullScreenTitlebarFix.Anchor(center: NotificationCenter())
            try #require(window.contentView).addSubview(anchor)
            let normal = window.frame
            _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: [.fullScreen, .autoHideMenuBar])
            window.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 810), display: false)
            original.exitFrame = NSRect(x: 0, y: 0, width: 1100, height: 700)
            window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
            #expect(original.exits == 1)
            #expect(window.frame == normal)
            #expect(window.toolbar == nil)
            // A completed transition cannot apply a saved frame to a later, unrelated notification.
            window.setFrame(NSRect(x: 0, y: 0, width: 1150, height: 720), display: false)
            let later = window.frame
            original.exitFrame = nil
            window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
            #expect(window.frame == later)
        }

        /// A display removed during full screen can leave the captured frame outside every current screen.
        @Test func completedExitKeepsTheRestoredWindowOnTheCurrentScreen() throws {
            let screen = try #require(NSScreen.main)
            let visible = screen.visibleFrame
            let window = NSWindow(contentRect: NSRect(x: visible.minX + 40, y: visible.minY + 40, width: 600, height: 400),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let reachable = window.frame
            let anchor = FullScreenTitlebarFix.Anchor(center: NotificationCenter())
            try #require(window.contentView).addSubview(anchor)
            let rightmostEdge = try #require(NSScreen.screens.map(\.frame.maxX).max())
            window.setFrameOrigin(NSPoint(x: rightmostEdge + 1000, y: reachable.minY))
            #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
            _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: [.fullScreen, .autoHideMenuBar])
            // AppKit has already adapted its exit frame to the remaining display.
            window.setFrame(reachable, display: false)
            window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
            #expect(visible.contains(window.frame), "Restoration must not undo AppKit's recovery from a removed display")
            #expect(window.frame.size == reachable.size)
            #expect(window.toolbar == nil)
        }

        @Test(arguments: [false, true], [false, true])
        func detachPreservesTheExistingToolbarAndItsVisibility(visible: Bool, replaced: Bool) throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                                  styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let original = NSToolbar(identifier: "ExistingControls")
            window.toolbar = original
            original.isVisible = visible
            let anchor = FullScreenTitlebarFix.Anchor(center: NotificationCenter())
            try #require(window.contentView).addSubview(anchor)
            #expect(window.toolbar === original)
            #expect(original.isVisible == visible)
            _ = window.delegate?.window?(window, willUseFullScreenPresentationOptions: [.fullScreen, .autoHideMenuBar])
            #expect(window.toolbar !== original)
            let newer = NSToolbar(identifier: "NewerControls")
            if replaced { window.toolbar = newer; newer.isVisible = false }
            anchor.removeFromSuperview()
            #expect(window.toolbar === (replaced ? newer : original))
            #expect(window.toolbar?.isVisible == (replaced ? false : visible))
        }
    }

    @Suite(.serialized) @MainActor struct FullScreenListTopTests {
        /// The first article keeps its place below the band and heading across native title-bar layouts. It previously moved
        /// under the heading in full screen (#373).
        @Test func theFirstArticleKeepsItsPlaceWithOrWithoutTheTitleBar() async throws {
            let underTitleBar = try await firstRowTop(styleMask: [.titled, .fullSizeContentView])
            let withoutTitleBar = try await firstRowTop(styleMask: [.titled])
            #expect(abs(underTitleBar - withoutTitleBar) < 0.5, "first row at \(underTitleBar) pt and \(withoutTitleBar) pt")
            #expect(abs(underTitleBar - ListHeader.listTopInset) < 0.5)
        }

        /// From the top of the window's content to the top of the article list's rows.
        private func firstRowTop(styleMask: NSWindow.StyleMask) async throws -> CGFloat {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try inMemoryReaderStore()
            let entry = ParsedEntry(sourceID: "synthetic", title: "Synthetic article", url: nil, summary: "Synthetic summary", body: "Synthetic body", coverage: .feedProvided, publishedAt: .now)
            _ = try store.importFeed(ParsedFeed(title: "Synthetic feed", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: [entry], skippedEntries: 0), receivedAt: .now)
            let host = NSHostingView(rootView: ReaderView(store: store, refresh: FeedRefreshController(store: store), imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images"))))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: styleMask, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            func find(_ view: NSView) -> NativeArticleList.Table? {
                if let table = view as? NativeArticleList.Table { return table }
                for child in view.subviews { if let table = find(child) { return table } }
                return nil
            }
            for _ in 0..<250 {
                host.layoutSubtreeIfNeeded()
                if find(host)?.numberOfRows == 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let table = try #require(find(host))
            #expect(table.numberOfRows == 1)
            // The top edge of the table, with the list scrolled to its top.
            let edge = table.convert(NSPoint(x: 0, y: table.bounds.minY), to: host)
            return host.isFlipped ? edge.y : host.bounds.maxY - edge.y
        }
    }
}
