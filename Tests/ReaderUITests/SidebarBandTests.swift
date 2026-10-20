import AppKit
import SwiftUI
import ReaderCore
import Testing
@testable import UnagiReader

/// The sidebar's rows scrolled up under the window buttons, and the scroll bar ran up to the top of the window (seen while dogfooding,
/// 2026-10-17). Decision 0057: the sidebar's band, as high as the window buttons' band, belongs to the window buttons and the two
/// buttons; the rows and their scroll bar start below it.
extension SplitViewFoldTests {
    @Suite(.serialized) @MainActor struct SidebarBandTests {
        private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
            if let result = view as? T { return result }
            return view.subviews.lazy.compactMap { find(type, in: $0) }.first
        }

        @Test(arguments: [960.0, 1240.0, 1600.0])
        func theSidebarStaysBelowTheBandAndItsFirstRowAlignsWithTheList(width: Double) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try ReaderStore(url: directory.appendingPathComponent("Reader.store"))
            let entries = [ParsedEntry(sourceID: "synthetic-0", title: "合成記事 0", url: URL(string: "http://127.0.0.1:1/article/0"), summary: "合成要約", body: "合成本文", coverage: .feedProvided, publishedAt: .now)]
            _ = try store.importFeed(ParsedFeed(title: "合成購読", sourceURL: URL(string: "http://127.0.0.1:1/feed")!, entries: entries, skippedEntries: 0), receivedAt: .now)
            let reader = ReaderView(store: store, refresh: FeedRefreshController(store: store),
                imageLoader: ReaderImageLoader(directory: directory.appendingPathComponent("Images")))
            let host = NSHostingView(rootView: reader)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            var outline: NSOutlineView?
            for _ in 0..<250 {
                host.layoutSubtreeIfNeeded()
                outline = find(NSOutlineView.self, in: host)
                if outline?.enclosingScrollView != nil, find(NativeArticleList.Table.self, in: host)?.numberOfRows == 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let scroll = try #require(outline?.enclosingScrollView)
            // Window coordinates run upward from the bottom: the distance from the top of the window is the height minus the top edge.
            let top = 800 - scroll.convert(scroll.bounds, to: nil).maxY
            #expect(top >= ListHeader.bandHeight - 0.5, "the sidebar's scroll view starts \(top) pt from the window's top")
            let sidebar = try #require(outline)
            let table = try #require(find(NativeArticleList.Table.self, in: host))
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            for _ in 0..<250 where store.articles.first?.firstReadAt == nil {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(store.articles.first?.firstReadAt != nil)
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let scale = CGFloat(image.pixelsHigh) / host.bounds.height
            func selectionTop(in view: NSView, row: NSRect) throws -> CGFloat {
                let rect = view.convert(row, to: nil)
                let top = 800 - rect.maxY, bottom = 800 - rect.minY
                let x = Int(rect.midX * scale)
                let sample = try #require(image.colorAt(x: x, y: Int((bottom - 8) * scale))?.usingColorSpace(.sRGB))
                let background = try #require(image.colorAt(x: x, y: Int(40 * scale))?.usingColorSpace(.sRGB))
                let contrast = abs(sample.redComponent - background.redComponent)
                    + abs(sample.greenComponent - background.greenComponent)
                    + abs(sample.blueComponent - background.blueComponent)
                if contrast <= 0.05, let results = ProcessInfo.processInfo.environment["CI_RESULTS"],
                   let png = image.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(fileURLWithPath: results).appendingPathComponent("sidebar-selection-\(Int(width)).png"))
                }
                try #require(contrast > 0.05, "the row must actually be painted as selected: \(type(of: view)), row \(row), window rect \(rect), host \(host.bounds), bitmap \(image.pixelsWide)x\(image.pixelsHigh)")
                // Read the actual background near the bottom of the selected row, away from its text. Then find its first painted
                // pixel. The list's heading can cover part of a row; its internal rect alone does not describe what the person sees.
                let first = (Int(max(52, top - 10) * scale)..<Int((top + 20) * scale)).first { y in
                    guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                    return abs(colour.redComponent - sample.redComponent) < 0.02
                        && abs(colour.greenComponent - sample.greenComponent) < 0.02
                        && abs(colour.blueComponent - sample.blueComponent) < 0.02
                }
                return CGFloat(try #require(first)) / scale
            }
            // Use the actual selection instead of assuming its position among the system's group rows.
            try #require(sidebar.selectedRow >= 0)
            let sidebarTop = try selectionTop(in: sidebar, row: sidebar.rect(ofRow: sidebar.selectedRow))
            let articleTop = try selectionTop(in: table, row: table.rect(ofRow: 0))
            #expect(abs(sidebarTop - articleTop) <= 2,
                    "visible selections start at different heights: sidebar \(sidebarTop), list \(articleTop)")
        }
    }
}
