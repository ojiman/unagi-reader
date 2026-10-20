import AppKit
import SwiftUI
import WebKit
import Testing
@testable import UnagiReader

@MainActor struct OriginalFailureFocusTests {
    @Test(arguments: [false, true])
    func aLateOriginalFailureMustNotTakeTheNotesKeyboard(composing: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: window.contentView!.bounds)
        window.contentView = container
        let note = NoteTextView(frame: NSRect(x: 400, y: 0, width: 400, height: 600))
        container.addSubview(note)
        #expect(window.makeFirstResponder(note))
        if composing { note.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        let failure = OriginalFailureHostingView(rootView: Text("Synthetic delayed network failure"))
        container.addSubview(failure)
        #expect(window.firstResponder === note)
        #expect(note.hasMarkedText() == composing)
    }

    @Test func aLateFailureMustNotTakeTheListKeyboard() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: window.contentView!.bounds)
        window.contentView = container
        let list = NSTableView(frame: container.bounds)
        list.addTableColumn(NSTableColumn(identifier: .init("article")))
        container.addSubview(list)
        #expect(window.makeFirstResponder(list))
        try #require(window.firstResponder === list)
        container.addSubview(OriginalFailureHostingView(rootView: Text("Synthetic failure")))
        #expect(window.firstResponder === list)
    }

    @Test func aFailureStillTakesTheKeyboardAfterTheFocusedPageIsRemoved() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = NSView(frame: window.contentView!.bounds)
        window.contentView = container
        let page = OriginalReaderWebView(frame: container.bounds, configuration: WKWebViewConfiguration())
        container.addSubview(page)
        #expect(window.firstResponder === page)
        page.removeFromSuperview()
        let failure = OriginalFailureHostingView(rootView: Text("Synthetic failure"))
        container.addSubview(failure)
        #expect(window.firstResponder === failure)
    }
}
