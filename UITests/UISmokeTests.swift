import XCTest
import Carbon

@MainActor final class UISmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL!
    private var inputSource: TISInputSource?

    override func setUp() async throws {
        try await MainActor.run {
            continueAfterFailure = false
            let path = try XCTUnwrap(ProcessInfo.processInfo.environment["UNAGI_UI_SMOKE_APP"])
            let url = URL(fileURLWithPath: path)
            XCTAssertEqual(Bundle(url: url)?.bundleIdentifier, "xyz.ojima.UnagiReader.Synthetic.UISmoke", "Refusing app at: \(path)")
            directory = FileManager.default.temporaryDirectory.appending(path: "unagi-ui-smoke-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            app = XCUIApplication(url: url)
            app.launchArguments = ["--data-directory", directory.path, "--seed-demo"]
            app.launch()
            app.activate()
            inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            XCTAssertEqual(TISSelectInputSource(ascii), noErr)
            XCTAssertTrue(app.tables["Article List"].waitForExistence(timeout: 15), app.windows.debugDescription)
            XCTAssertTrue(app.outlines.staticTexts["開発ノート"].exists)
        }
    }

    override func tearDown() async throws {
        try await MainActor.run {
            if let inputSource { XCTAssertEqual(TISSelectInputSource(inputSource), noErr) }
            app?.terminate()
            if let directory { try FileManager.default.removeItem(at: directory) }
        }
    }

    // Issue #371: exercise the packaged hidden-title-bar window at the width that exposed #222.
    private func checkNarrowWindowLayout(width: CGFloat) {
        selectFirst()
        let window = app.windows.firstMatch
        let frame = window.frame
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: 1, dy: 1))
        let target = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: width + 1, dy: frame.height + 1))
        edge.click(forDuration: 0.1, thenDragTo: target)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(window.frame.width - width) < 4 }, object: nil)], timeout: 5), .completed, "window after drag: \(window.frame), before: \(frame)")
        let table = app.tables["Article List"]
        let listViewport = app.scrollViews.containing(.table, identifier: "Article List").firstMatch
        let articleViewport = app.scrollViews.containing(.textView, identifier: "Article Body").firstMatch
        let divider = table.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 1, dy: 0))
        let listRight = table.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 401, dy: 0))
        divider.click(forDuration: 0.1, thenDragTo: listRight)
        XCTAssertEqual(listViewport.frame.width, 400, accuracy: 3)
        let start = window.frame
        for _ in 0..<2 {
            window.typeKey("n", modifierFlags: [])
            let editor = app.textViews["Note"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            app.buttons["Show Article List"].click()
            XCTAssertTrue(app.buttons["Hide Article List"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
            XCTAssertEqual(listViewport.frame.width, 400, accuracy: 3)
            XCTAssertGreaterThanOrEqual(articleViewport.frame.minX, listViewport.frame.maxX - 1)
            XCTAssertLessThanOrEqual(articleViewport.frame.maxX, window.frame.maxX + 1)
            XCTAssertEqual(window.frame.width, start.width, accuracy: 1)
            app.buttons["Hide Article List"].click()
            XCTAssertTrue(app.buttons["Show Article List"].waitForExistence(timeout: 5))
            editor.click()
            window.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
            XCTAssertEqual(listViewport.frame.width, 400, accuracy: 3)
            XCTAssertGreaterThanOrEqual(articleViewport.frame.minX, listViewport.frame.maxX - 1)
            XCTAssertLessThanOrEqual(articleViewport.frame.maxX, window.frame.maxX + 1)
            XCTAssertEqual(window.frame.width, start.width, accuracy: 1)
            XCTAssertEqual(window.frame.minX, start.minX, accuracy: 1)
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    // Checks PRD-01: a real click and j/k must select and display the corresponding article.
    func testLaunchSelectionAndReadingKeys() {
        let table = app.tables["Article List"]
        XCTAssertEqual(table.tableRows.count, 6)
        // Native cell accessibility clicks can select without giving the table the keyboard.
        table.tableRows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let body = app.textViews["Article Body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        waitForValue(body, containing: "毎日届く情報")
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        XCTAssertEqual(TISSelectInputSource(ascii), noErr)
        table.typeText("j")
        waitForValue(body, containing: "朝の空気")
        table.typeText("k")
        waitForValue(body, containing: "毎日届く情報")
    }

    // Checks PRD-04 and decision 0050: the panel's own close button and Esc close the note.
    func testNoteCloseButtonAndEscape() {
        selectFirst()
        app.windows.firstMatch.typeKey("n", modifierFlags: [])
        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.groups["Note"].buttons["Close Note"].click()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        app.windows.firstMatch.typeKey("n", modifierFlags: [])
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.windows.firstMatch.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
    }

    // Checks PRD-04: layout changes keep the note, and committed typing survives a restart.
    func testNoteLayoutKeepsEditing() {
        for width in [CGFloat(1170), CGFloat(1240)] { checkNarrowWindowLayout(width: width) }
        selectFirst()
        app.windows.firstMatch.typeKey("n", modifierFlags: [])
        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        for key in ["j", "k", "n"] { editor.typeText(key) }
        app.buttons["Show Article List"].click()
        XCTAssertTrue(app.buttons["Hide Article List"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
        XCTAssertEqual(editor.value as? String, "jkn")
        app.buttons["Hide Article List"].click()
        XCTAssertTrue(app.buttons["Show Article List"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "jkn")
        app.terminate()
        app.launch()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        XCTAssertEqual(TISSelectInputSource(ascii), noErr)
        selectFirst()
        app.windows.firstMatch.typeKey("n", modifierFlags: [])
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "jkn")
    }

    // Checks PRD-14 and PRD-03: normal URL input fetches a loopback feed; v/Esc opens/closes its local page.
    func testLocalFeedAndOriginalPage() throws {
        try addLocalFeed()
        selectFirst()
        let body = app.textViews["Article Body"]
        waitForValue(body, containing: "Smoke local article body.")
        app.windows.firstMatch.typeKey("v", modifierFlags: [])
        XCTAssertTrue(app.buttons["Return to Article"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["Smoke original page"].waitForExistence(timeout: 10))
        app.windows.firstMatch.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["Return to Article"].waitForNonExistence(timeout: 5))
        waitForValue(body, containing: "Smoke local article body.")
        XCTAssertTrue(app.outlines.staticTexts["Smoke local feed"].exists)
    }

    // Checks PRD-16 and PRD-15 with real events. 「名前を変更」 from the context menu puts the keyboard in the name field at once
    // (decision 0043): the person types without clicking it. Several renames, from an unselected and a selected row, because the
    // focus was lost only sometimes (#265).
    func testRenameAndOPMLMenu() {
        var current = "開発ノート"
        for round in 1...4 {
            let row = app.outlines.staticTexts[current]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            if round > 2 { row.click() }                                       // rounds 3 and 4: the subscription is selected first
            row.rightClick()
            app.menuItems["Rename"].click()
            let name = app.textFields["Name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: name)
            XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 5), .completed, "round \(round): the name field has no keyboard focus")
            let renamed = "Smoke renamed \(round)"
            app.typeText(renamed)                                              // the whole old name is selected, so typing replaces it
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(app.outlines.staticTexts[renamed].waitForExistence(timeout: 5), "round \(round)")
            XCTAssertFalse(app.outlines.staticTexts[current].exists)
            current = renamed
        }
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["Import OPML…"].exists)
        XCTAssertTrue(app.menuItems["Import OPML…"].isEnabled)
        app.windows.firstMatch.typeKey(.escape, modifierFlags: [])
    }

    private func selectFirst() {
        let table = app.tables["Article List"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.tableRows.element(boundBy: 0).click()
        app.textViews["Article Body"].click()
    }

    private func waitForValue(_ element: XCUIElement, containing text: String) {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed, "Expected \(text), got: \(String(describing: element.value))")
    }

    private func addLocalFeed() throws {
        let address = try XCTUnwrap(ProcessInfo.processInfo.environment["UNAGI_UI_SMOKE_FEED"])
        XCTAssertTrue(address.hasPrefix("http://127.0.0.1:"))
        app.buttons["Add Subscription"].click()
        let field = app.textFields["Feed URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(address)
        let add = app.buttons["Add"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: add)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        add.click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.outlines.staticTexts["Smoke local feed"].waitForExistence(timeout: 5))
    }
}
