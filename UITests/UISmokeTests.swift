import XCTest
import AppKit
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
            // Process-local settings exercise real restoration and Sepia without changing the person's preferences.
            app.launchArguments = ["--data-directory", directory.path, "--seed-demo", "-NSQuitAlwaysKeepsWindows", "YES", "-appearance", "sepia"]
            app.launch()
            let launchedState = app.state
            inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            XCTAssertEqual(TISSelectInputSource(ascii), noErr)
            let inputState = app.state
            // Selecting an input source is a system interaction; reclaim the app before asking for its UI.
            app.activate()
            XCTAssertEqual(app.state, .runningForeground, "Startup states: launched=\(launchedState), after input=\(inputState), current=\(app.state)")
            XCTAssertTrue(app.tables["Article List"].waitForExistence(timeout: 15), "Startup states: launched=\(launchedState), after input=\(inputState), current=\(app.state)\n\(app.windows.debugDescription)")
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
        if abs(frame.width - width) >= 4 {
            let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: 1, dy: 1))
            let target = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: width + 1, dy: frame.height + 1))
            edge.click(forDuration: 0.1, thenDragTo: target)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(window.frame.width - width) < 4 }, object: nil)], timeout: 5), .completed, "window after drag: \(window.frame), before: \(frame)")
        let table = app.tables["Article List"]
        let listViewport = app.scrollViews.containing(.table, identifier: "Article List").firstMatch
        let articleViewport = app.scrollViews.containing(.textView, identifier: "Article Body").firstMatch
        // The table ends before a visible scrollbar. Drag the actual split-view divider, not the table's edge.
        guard let splitter = app.splitters.allElementsBoundByIndex.first(where: { abs($0.frame.minX - listViewport.frame.maxX) < 1 }) else {
            XCTFail("The list must have a divider at its viewport edge"); return
        }
        let divider = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // CI's 1,024 pt desktop also needs room for the note and the article beside the list.
        let listWidth: CGFloat = width < 1170 ? 280 : 400
        let listRight = listViewport.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: listWidth + splitter.frame.width / 2, dy: 0))
        divider.click(forDuration: 0.1, thenDragTo: listRight)
        XCTAssertEqual(listViewport.frame.width, listWidth, accuracy: 3)
        let start = window.frame
        for _ in 0..<2 {
            window.typeKey("n", modifierFlags: [])
            let editor = app.textViews["Note"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            app.buttons["Show Article List"].click()
            XCTAssertTrue(app.buttons["Hide Article List"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
            XCTAssertEqual(listViewport.frame.width, listWidth, accuracy: 3)
            XCTAssertGreaterThanOrEqual(articleViewport.frame.minX, listViewport.frame.maxX - 1)
            XCTAssertLessThanOrEqual(articleViewport.frame.maxX, window.frame.maxX + 1)
            XCTAssertEqual(window.frame.width, start.width, accuracy: 1)
            app.buttons["Hide Article List"].click()
            XCTAssertTrue(app.buttons["Show Article List"].waitForExistence(timeout: 5))
            editor.click()
            window.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.tables["Article List"].tableRows.firstMatch.isHittable)
            XCTAssertEqual(listViewport.frame.width, listWidth, accuracy: 3)
            XCTAssertGreaterThanOrEqual(articleViewport.frame.minX, listViewport.frame.maxX - 1)
            XCTAssertLessThanOrEqual(articleViewport.frame.maxX, window.frame.maxX + 1)
            XCTAssertEqual(window.frame.width, start.width, accuracy: 1)
            XCTAssertEqual(window.frame.minX, start.minX, accuracy: 1)
            XCTAssertEqual(app.state, .runningForeground)
        }
        if abs(width - 1170) < 4 {
            // #381: after the no-drag baseline, try a newer choice in both directions.
            for targetWidth: CGFloat in [340, 460] {
                // Cache the normal-layout coordinates before folding; do not wait for restoration before dragging.
                let from = window.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: listViewport.frame.minX - start.minX + listWidth + splitter.frame.width / 2,
                             dy: start.height / 2))
                let to = from.withOffset(CGVector(dx: targetWidth - listWidth, dy: 0))
                window.typeKey("n", modifierFlags: [])
                let editor = app.textViews["Note"]
                XCTAssertTrue(editor.waitForExistence(timeout: 5))
                let closedAt = ProcessInfo.processInfo.systemUptime
                window.typeKey(.escape, modifierFlags: [])
                let dragRequestedAfter = ProcessInfo.processInfo.systemUptime - closedAt
                from.click(forDuration: 0.05, thenDragTo: to)
                let elapsed = ProcessInfo.processInfo.systemUptime - closedAt
                print("#381 window=\(width), target=\(targetWidth), close-to-drag-request=\(dragRequestedAfter)s, close-to-drag-complete=\(elapsed)s, actual=\(listViewport.frame.width)")
                XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
                XCTAssertEqual(listViewport.frame.width, targetWidth, accuracy: 3)
                // Observe beyond the restoration task's two-second limit, rather than accepting one matching frame.
                let overridden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    abs(listViewport.frame.width - targetWidth) > 3
                }, object: nil)
                overridden.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [overridden], timeout: 2.2), .completed,
                               "A newer divider choice must not be restored to the old width")
                XCTAssertEqual(window.frame.width, start.width, accuracy: 1)
                // A later fold must remember the new choice too.
                window.typeKey("n", modifierFlags: [])
                XCTAssertTrue(editor.waitForExistence(timeout: 5))
                window.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
                XCTAssertEqual(listViewport.frame.width, targetWidth, accuracy: 3)
                // Reset the baseline for the other direction.
                let currentDivider = app.splitters.allElementsBoundByIndex.first {
                    abs($0.frame.minX - listViewport.frame.maxX) < 1
                }
                XCTAssertNotNil(currentDivider)
                currentDivider?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .click(forDuration: 0.1, thenDragTo: listRight)
                XCTAssertEqual(listViewport.frame.width, listWidth, accuracy: 3)
            }
        }
    }

    // Checks PRD-01: a real click and j/k must select and display the corresponding article.
    func testLaunchSelectionAndReadingKeys() throws {
        useNormalWindow()
        let table = app.tables["Article List"]
        XCTAssertEqual(table.tableRows.count, 6)
        try checkListFilterControl()
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
        // Keep the initial, screen-clamped frame case that exposed the native restoration bug on CI (#373).
        try checkFullScreenControls(alwaysVisibleMenu: false, resize: false)
        waitForValue(body, containing: "毎日届く情報")
        try checkFullScreenControls(alwaysVisibleMenu: false, resize: true)
        waitForValue(body, containing: "毎日届く情報")
        // #392: preserve a real full-screen scene across a normal quit, including Sepia before any theme change.
        let window = app.windows.firstMatch
        let normal = window.frame
        let green = app.buttons[XCUIIdentifierFullScreenWindow]
        let greenX = green.frame.midX - normal.minX
        green.click()
        XCTAssertTrue(waitForCondition { window.frame.height > normal.height + 1 })
        window.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        // NSArgumentDomain applies this setting only to the synthetic app; do not change the person's menu-bar preference.
        app.launchArguments += ["-AppleMenuBarVisibleInFullscreen", "YES"]
        app.launch()
        app.activate()
        let configuredTableAppeared = table.waitForExistence(timeout: 15)
        let nativeState = NSRunningApplication.runningApplications(withBundleIdentifier: "xyz.ojima.UnagiReader.Synthetic.UISmoke")
            .map { "pid=\($0.processIdentifier), active=\($0.isActive), hidden=\($0.isHidden), finished=\($0.isFinishedLaunching)" }
        XCTAssertTrue(configuredTableAppeared, "Configured launch: \(nativeState)\n\(app.windows.debugDescription)")
        let menu = app.menuBars.menuBarItems["View"]
        menu.click()
        XCTAssertTrue(app.menuItems["Exit Full Screen"].waitForExistence(timeout: 5), "The synthetic app must really restore full screen")
        app.typeKey(.escape, modifierFlags: [])
        let top = window.coordinate(withNormalizedOffset: .zero)
        for y: CGFloat in [100, 0, 1] { top.withOffset(CGVector(dx: greenX, dy: y - window.frame.minY)).hover() }
        XCTAssertTrue(waitForCondition { self.greenPoint(x: greenX, in: window) != nil })
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Restored full-screen Sepia controls, before any theme change"
        image.lifetime = .keepAlways
        add(image)
        useNormalWindow()
        XCTAssertEqual(window.frame.width, normal.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, normal.height, accuracy: 1)
        table.tableRows.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        waitForValue(body, containing: "毎日届く情報")
        try checkFullScreenControls(alwaysVisibleMenu: true, resize: true)
        waitForValue(body, containing: "毎日届く情報")
    }

    // Checks PRD-04 and decision 0050: the panel's own close button and Esc close the note.
    func testNoteCloseButtonAndEscape() {
        useNormalWindow()
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
        useNormalWindow()
        let available = NSScreen.main?.visibleFrame.width ?? 1170
        let widths = Set([min(CGFloat(1170), available), min(CGFloat(1240), available)]).sorted()
        for width in widths { checkNarrowWindowLayout(width: width) }
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
        useNormalWindow()
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
        useNormalWindow()
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

    // #392: a fresh library does not reset the OS scene's full-screen state.
    private func useNormalWindow() {
        let window = app.windows.firstMatch
        let menu = app.menuBars.menuBarItems["View"]
        let top = window.coordinate(withNormalizedOffset: .zero)
        for y: CGFloat in [0, 1] { top.withOffset(CGVector(dx: menu.frame.midX - window.frame.minX, dy: y - window.frame.minY)).hover() }
        menu.click()
        let exit = app.menuItems["Exit Full Screen"]
        if exit.exists {
            print("Leaving restored full-screen fixture: \(app.windows.firstMatch.frame)")
            // The restored-start menu click did not consistently leave full screen.
            // Dismiss it, then use the same native shortcut checked by the full-screen scenarios.
            app.typeKey(.escape, modifierFlags: [])
            window.typeKey("f", modifierFlags: .function)
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(app.buttons[XCUIIdentifierFullScreenWindow].waitForExistence(timeout: 5), "The smoke fixture must have normal window controls")
        XCTAssertTrue(app.buttons["Add Subscription"].waitForExistence(timeout: 5))
    }

    // #373: use real input on the packaged window, including the transient green control that has no AX element.
    private func checkFullScreenControls(alwaysVisibleMenu: Bool, resize: Bool) throws {
        let window = app.windows.firstMatch
        if resize {
            // The CI desktop initially clamps the requested 1240 × 810 pt size. Also exercise a smaller, person-resized
            // window locally: restoring the requested default instead of this frame must fail on either desktop.
            let targetSize = CGSize(width: 1000, height: 650)
            let beforeResize = window.frame
            // Keep the resize handles inside the display, including CI's edge-to-edge starting window.
            let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0))
            let rightTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: targetSize.width - 1, dy: 0))
            right.click(forDuration: 0.1, thenDragTo: rightTarget)
            let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: -1))
            let bottomTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: targetSize.height - 1))
            bottom.click(forDuration: 0.1, thenDragTo: bottomTarget)
            XCTAssertTrue(waitForCondition { abs(window.frame.width - targetSize.width) < 3 && abs(window.frame.height - targetSize.height) < 3 }, "Resized window: \(window.frame), before: \(beforeResize)")
        }
        let normal = window.frame
        func keepImage(_ name: String, _ screenshot: XCUIScreenshot) {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = (alwaysVisibleMenu ? "Always-visible menu: " : "Auto-hidden menu: ") + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        keepImage("Normal window", window.screenshot())
        let green = app.buttons[XCUIIdentifierFullScreenWindow]
        XCTAssertTrue(green.exists)
        let greenX = green.frame.midX - normal.minX
        func fullScreen() -> Bool { window.frame.height > normal.height + 1 }
        var fullScreenFrame = CGRect.zero
        func normalWindow() -> Bool { green.exists && window.frame.height < fullScreenFrame.height - 1 }
        func checkRestoredSize() {
            let frames = "before=\(normal), full=\(fullScreenFrame), after=\(window.frame), green=\(green.exists)"
            print("Full-screen frames: \(frames)")
            XCTAssertEqual(window.frame.height, normal.height, accuracy: 1, "The window must regain its old height: \(frames)")
            XCTAssertEqual(window.frame.width, normal.width, accuracy: 1, "The window must regain its old width: \(frames)")
        }
        green.click()
        XCTAssertTrue(waitForCondition(fullScreen))
        fullScreenFrame = window.frame
        XCTAssertEqual(fullScreenFrame.minY > 0, alwaysVisibleMenu, "The synthetic menu preference must take effect: \(fullScreenFrame)")
        keepImage("Full screen", window.screenshot())
        print("Full-screen frames: before=\(normal), full=\(fullScreenFrame)")
        try checkListFilterControl()
        let top = window.coordinate(withNormalizedOffset: .zero)
        for y: CGFloat in [100, 0, 1] { top.withOffset(CGVector(dx: greenX, dy: y - window.frame.minY)).hover() }
        XCTAssertTrue(waitForCondition { self.greenPoint(x: greenX, in: window) != nil })
        keepImage("Revealed full-screen controls", window.screenshot())
        let point = try XCTUnwrap(greenPoint(x: greenX, in: window))
        top.withOffset(point).click()
        XCTAssertTrue(waitForCondition(normalWindow), "The revealed green control must leave full screen")
        checkRestoredSize()
        green.click()
        XCTAssertTrue(waitForCondition(fullScreen))
        let menu = app.menuBars.menuBarItems["View"]
        for y: CGFloat in [0, 1] { top.withOffset(CGVector(dx: menu.frame.midX - window.frame.minX, dy: y - window.frame.minY)).hover() }
        menu.click()
        let exit = app.menuItems["Exit Full Screen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCondition { exit.isHittable })
        exit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitForCondition(normalWindow), "The View menu must leave full screen")
        checkRestoredSize()
        window.typeKey("f", modifierFlags: .function)
        XCTAssertTrue(waitForCondition(fullScreen))
        window.typeKey("f", modifierFlags: .function)
        XCTAssertTrue(waitForCondition(normalWindow), "The system shortcut must leave full screen")
        checkRestoredSize()
    }

    // #397: AX can expose a clickable button even while the column clips its SwiftUI symbol.
    private func checkListFilterControl() throws {
        let button = app.buttons["Filter Articles"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: button.screenshot().pngRepresentation))
        let background = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
        var visiblePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let contrast = abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent) + abs(color.blueComponent - background.blueComponent)
                if contrast > 0.15 { visiblePixels += 1 }
            }
        }
        XCTAssertGreaterThan(visiblePixels, 10, "The filter symbol must have visible contrast, not only an AX element")
        button.click()
        let field = app.searchFields["Filter Articles"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    private func greenPoint(x: CGFloat, in window: XCUIElement) -> CGVector? {
        guard let image = NSBitmapImageRep(data: XCUIScreen.main.screenshot().pngRepresentation) else { return nil }
        let scale = CGFloat(image.pixelsWide) / window.frame.width
        let centerX = Int((window.frame.minX + x) * scale), radius = Int(20 * scale)
        var points: [(x: Int, y: Int)] = []
        for row in 0..<min(image.pixelsHigh, Int(100 * scale)) {
            let columns = (max(0, centerX - radius)...min(image.pixelsWide - 1, centerX + radius)).filter { column in
                guard let colour = image.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return colour.greenComponent > 0.5 && colour.greenComponent > colour.redComponent * 1.25 && colour.greenComponent > colour.blueComponent * 1.3
            }
            if columns.count >= 3 { points.append(contentsOf: columns.map { ($0, row) }) }
        }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxY - minY >= 6 else { return nil }
        // Detached native controls can move horizontally: click the observed green circle, not its normal-window x.
        return CGVector(dx: CGFloat(minX + maxX) / (2 * scale) - window.frame.minX,
                        dy: CGFloat(minY + maxY) / (2 * scale) - window.frame.minY)
    }

    private func waitForCondition(_ ready: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in ready() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
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
