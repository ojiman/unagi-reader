import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

extension SplitViewFoldTests {
    /// A private notification center tests the wiring without sending synthetic full-screen notices to AppKit.
    /// Real green-button clicks still need the packaged app (#373).
    @Suite(.serialized) @MainActor struct FullScreenTitlebarTests {
        @Test func entryLeavesTheNormalFrameAloneUntilTheSystemHasEntered() throws {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1024, height: 674),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let center = NotificationCenter()
            let anchor = FullScreenTitlebarFix.Anchor(center: center)
            try #require(window.contentView).addSubview(anchor)
            let normal = window.frame
            center.post(name: NSWindow.willEnterFullScreenNotification, object: window)
            #expect(window.frame == normal, "AppKit must begin entry with the person's normal frame")
            #expect(window.styleMask.contains(.fullSizeContentView))
            center.post(name: NSWindow.didEnterFullScreenNotification, object: window)
            #expect(!window.styleMask.contains(.fullSizeContentView))
        }

        @Test func theAttachedWindowReceivesTheFullScreenChanges() {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            let other = NSWindow(contentRect: window.contentView!.bounds,
                                 styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            other.isReleasedWhenClosed = false
            defer { window.close(); other.close() }
            let center = NotificationCenter()
            let anchor = FullScreenTitlebarFix.Anchor(center: center)
            window.contentView!.addSubview(anchor)
            center.post(name: NSWindow.didEnterFullScreenNotification, object: other)
            #expect(window.styleMask.contains(.fullSizeContentView))
            for _ in 0..<3 {
                center.post(name: NSWindow.willEnterFullScreenNotification, object: window)
                #expect(window.styleMask.contains(.fullSizeContentView))
                center.post(name: NSWindow.didEnterFullScreenNotification, object: window)
                #expect(!window.styleMask.contains(.fullSizeContentView))
                center.post(name: NSWindow.willExitFullScreenNotification, object: window)
                #expect(window.styleMask.contains(.fullSizeContentView))
            }
            anchor.removeFromSuperview()
            center.post(name: NSWindow.didEnterFullScreenNotification, object: window)
            #expect(window.styleMask.contains(.fullSizeContentView), "A detached anchor must stop changing its old window")
        }
    }

    @Suite(.serialized) @MainActor struct FullScreenFrameTests {
        @MainActor private final class WindowDelegate: NSObject, NSWindowDelegate {
            var exitFrame: NSRect?
            var exits = 0
            func windowDidExitFullScreen(_ notification: Notification) {
                exits += 1
                if let window = notification.object as? NSWindow, let exitFrame {
                    window.setFrame(exitFrame, display: false)
                }
            }
        }
        @Test func eachExitRestoresTheActualNormalSize() throws {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1024, height: 674),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let original = WindowDelegate()
            window.delegate = original
            let center = NotificationCenter()
            let anchor = FullScreenTitlebarFix.Anchor(center: center)
            try #require(window.contentView).addSubview(anchor)
            for size in [NSSize(width: 1024, height: 674), NSSize(width: 1000, height: 650)] {
                window.setFrame(NSRect(origin: NSPoint(x: 100, y: 100), size: size), display: false)
                center.post(name: NSWindow.willEnterFullScreenNotification, object: window)
                center.post(name: NSWindow.willExitFullScreenNotification, object: window)
                // Reproduce a different normal size after the full-screen transition on a small desktop (#373).
                window.setFrame(NSRect(x: 150, y: 200, width: 1240, height: 810), display: false)
                original.exitFrame = window.frame
                let nativeTop = window.frame.maxY
                center.post(name: NSWindow.didExitFullScreenNotification, object: window)
                window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
                #expect(window.frame.size == size)
                #expect(window.frame.minX == 150)
                #expect(window.frame.maxY == nativeTop, "Keep AppKit's restored top-left position")
            }
            #expect(original.exits == 2, "Forward each exit once before restoring the size")
            original.exitFrame = nil
            let restored = window.frame
            center.post(name: NSWindow.didExitFullScreenNotification, object: window)
            window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
            #expect(window.frame == restored, "An extra exit notification must not reuse an old size")
        }
    }

    @Suite(.serialized) @MainActor struct FullScreenFailureTests {
        @MainActor private final class WindowDelegate: NSObject, NSWindowDelegate {
            var entryFailures = 0
            var exitFailures = 0
            func windowDidFailToEnterFullScreen(_ window: NSWindow) { entryFailures += 1 }
            func windowDidFailToExitFullScreen(_ window: NSWindow) { exitFailures += 1 }
            func windowShouldClose(_ sender: NSWindow) -> Bool { false }
        }

        @Test(arguments: [true, false])
        func aFailedTransitionRestoresThePreviousContentMode(entering: Bool) throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let original = WindowDelegate()
            window.delegate = original
            let center = NotificationCenter()
            let anchor = FullScreenTitlebarFix.Anchor(center: center)
            try #require(window.contentView).addSubview(anchor)
            let normalSize = window.frame.size
            center.post(name: NSWindow.willEnterFullScreenNotification, object: window)
            if entering {
                window.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 810), display: false)
                window.delegate?.windowDidFailToEnterFullScreen?(window)
                #expect(window.styleMask.contains(.fullSizeContentView))
                #expect(window.frame.size == normalSize)
            } else {
                center.post(name: NSWindow.didEnterFullScreenNotification, object: window)
                center.post(name: NSWindow.willExitFullScreenNotification, object: window)
                window.delegate?.windowDidFailToExitFullScreen?(window)
                #expect(!window.styleMask.contains(.fullSizeContentView))
                center.post(name: NSWindow.willExitFullScreenNotification, object: window)
                window.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 810), display: false)
                center.post(name: NSWindow.didExitFullScreenNotification, object: window)
                window.delegate?.windowDidExitFullScreen?(Notification(name: NSWindow.didExitFullScreenNotification, object: window))
                #expect(window.frame.size == normalSize, "A failed exit must keep the original size for the next attempt")
            }
            #expect(original.entryFailures == (entering ? 1 : 0))
            #expect(original.exitFailures == (entering ? 0 : 1))
            // A window delegate's optional method and its return value still reach the original receiver.
            #expect(window.delegate?.windowShouldClose?(window) == false)
            anchor.removeFromSuperview()
            #expect(window.delegate === original)
        }
    }

    @Suite(.serialized) @MainActor struct FullScreenListTopTests {
        /// The first article stays at the same height below the band and the heading, whether the title bar lies under the content
        /// (a normal window) or not (full screen). In full screen it went up under the heading (#373).
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
