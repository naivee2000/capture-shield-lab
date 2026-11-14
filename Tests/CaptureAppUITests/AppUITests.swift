import AppKit
import XCTest

/// Separate process UI tests: never import CaptureShieldLab or use its account store.
@MainActor final class AppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var testToken = ""
    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_APP"])
        let url = URL(fileURLWithPath: path)
        let bundle = try XCTUnwrap(Bundle(url: url))
        let identifier = try XCTUnwrap(bundle.bundleIdentifier)
        guard identifier.hasPrefix("dev.naivee2000.captureshield.uitest.") else {
            throw NSError(domain: "Unsafe UI target", code: 1)
        }
        app = XCUIApplication(url: url)
        guard app.state == .notRunning else {
            app = nil
            throw NSError(domain: "Previous isolated test instance is still running", code: 2)
        }
        app.launchEnvironment["CAPTURESHIELD_UI_METADATA"] = metadataURL.path
        testToken = UUID().uuidString
        let seed: [String: Any] = ["token": testToken, "compact": name.contains("Compact"),
                                  "speechFailure": name.contains("RetainedError")]
        app.launchArguments = ["--chat-preview", "--ui-test-setup", try JSONSerialization.data(withJSONObject: seed).base64EncodedString()]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        verifyFixtureSetup()
    }
    @MainActor override func tearDown() async throws {
        // This instance was created by the test and has no personal login or draft.
        if let app, app.state != .notRunning { quit() }
        app = nil
    }
    func testLaunchTypeAndRestart() throws {
        let editor = app.webViews.textViews["Synthetic chat input"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.click()
        editor.typeText("Synthetic draft 2468")
        XCTAssertTrue((editor.value as? String ?? "").contains("2468"))
        if ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_NEGATIVE"] == "1" {
            XCTAssertTrue(app.buttons["Deliberately absent UI marker"].exists, "Negative control must fail")
        }
        relaunch()
    }

    private var metadataURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_RUN"]!).appendingPathComponent("window.json")
    }
    private var editor: XCUIElement { app.webViews.textViews["Synthetic chat input"].firstMatch }
    private var mainUI: XCUIElement { app.windows.matching(identifier: "chat-window").firstMatch }
    private func quit() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "The isolated app must quit normally; no force termination is used.")
    }
    private func relaunch() {
        let previous = record()["processID"] as? Int
        quit(); app.launch()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        wait("Fresh process metadata after normal restart") {
            let data = self.record()
            return data["processID"] as? Int != previous && data["testToken"] as? String == self.testToken
        }
    }
    private func record() -> [String: Any] {
        guard let data = try? Data(contentsOf: metadataURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root
    }
    private func mainWindow() -> [String: Any] {
        (record()["windows"] as? [[String: Any]] ?? []).first { $0["identifier"] as? String == "chat-window" } ?? [:]
    }
    private func verifyFixtureSetup() {
        let expectedWidth: Double = name.contains("Compact") ? 640 : 980
        let expectedHeight: Double = name.contains("Compact") ? 480 : 700
        wait("Isolated fixture preferences are applied") {
            let snapshot = self.record()
            let sourceReady = snapshot["previewSourceSet"] as? Bool == true
            let currentToken = snapshot["testToken"] as? String
            let width = self.mainWindow()["width"] as? Double ?? 0
            let height = self.mainWindow()["height"] as? Double ?? 0
            return sourceReady && currentToken == self.testToken && abs(width - expectedWidth) < 1 && abs(height - expectedHeight) < 1
        }
    }
    private func hasFreshSample() -> Bool {
        guard let sampled = record()["sampleUptime"] as? Double else { return false }
        let age = ProcessInfo.processInfo.systemUptime - sampled
        return age >= 0 && age < 5
    }
    private func wait(_ message: String, _ predicate: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(15)
        while !(hasFreshSample() && predicate()), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let state = (try? JSONSerialization.data(withJSONObject: record(), options: [.sortedKeys])) ?? Data()
        XCTAssertTrue(hasFreshSample() && predicate(), message + " · native metadata: " + (String(data: state, encoding: .utf8) ?? "unavailable"), file: file, line: line)
    }
    private func click(_ id: String) {
        let control = mainUI.descendants(matching: .any).matching(identifier: id).firstMatch
        if !control.isHittable && id.hasPrefix("zoom-") {
            let overflow = mainUI.toolbars.popUpButtons.firstMatch
            XCTAssertTrue(overflow.exists, "Toolbar overflow must remain accessible")
            overflow.click()
            let parent = app.menuItems["Page size"].firstMatch
            XCTAssertTrue(parent.waitForExistence(timeout: 10))
            parent.hover()
            let titles = ["zoom-out": "Decrease page size", "zoom-in": "Increase page size", "zoom-reset": "Reset page size to 90 percent"]
            let item = app.menuItems[titles[id]!].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10))
            wait("Zoom submenu action is hittable") { item.isHittable }
            item.hover()
            // Activate the highlighted native item after pointer placement;
            // nested-menu animation can otherwise shift the click onto Reset.
            app.typeKey("\r", modifierFlags: [])
            return
        }
        XCTAssertTrue(control.waitForExistence(timeout: 10), "Missing control: " + id)
        control.click()
    }
    private func waitText(_ text: String) {
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 10), "Missing visible text: " + text)
    }
    private func draftContains(_ text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: editor)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
    private func loadImage() {
        mainUI.menuButtons["Images"].firstMatch.click()
        // The app menu contains another sample command. Match the toolbar action.
        menuClick("loadPreviewImage")
        XCTAssertTrue(app.buttons["image-add"].waitForExistence(timeout: 10))
    }
    private func menuClick(_ id: String) {
        let item = app.menuItems[id].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        wait("Menu action is hittable: " + id) { item.isHittable }
        XCTAssertGreaterThan(item.frame.width, 0)
        // XCTest's MenuItem.click traverses a menu-bar ancestor even for toolbar
        // menus on macOS 15. Click the resolved visible element, not screen pixels.
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }
    func testModesZoomPopupAndDraftPreservation() throws {
        wait("Initial Normal window has read-only sharing") { self.mainWindow()["sharing"] as? Int == 1 }
        let originalFrame = try XCTUnwrap(mainWindow()["frame"] as? String)
        editor.click(); editor.typeText("Preserve draft 1357")
        for _ in 0..<2 { click("zoom-out") }
        wait("70 percent page zoom") { abs((self.mainWindow()["webZoom"] as? Double ?? 0) - 0.7) < 0.01 }
        for step in 8...14 {
            click("zoom-in")
            wait("Page zoom reaches step \(step)") { abs((self.mainWindow()["webZoom"] as? Double ?? 0) - Double(step) / 10) < 0.01 }
        }
        wait("140 percent page zoom") { abs((self.mainWindow()["webZoom"] as? Double ?? 0) - 1.4) < 0.01 }
        mainUI.radioButtons["Legacy"].click()
        wait("Legacy config and Dock policy") {
            self.mainWindow()["sharing"] as? Int == 0 && self.record()["policy"] as? Int == 1
        }
        XCTAssertEqual(mainWindow()["alpha"] as? Double, 1)
        XCTAssertEqual(mainWindow()["backgroundAlpha"] as? Double ?? 0, 0.8, accuracy: 0.01)
        XCTAssertEqual(mainWindow()["webAlpha"] as? Double, 1)
        mainUI.radioButtons["Normal"].click()
        wait("Normal sharing restored before cursor or popup interaction") {
            self.mainWindow()["sharing"] as? Int == 1 && self.record()["policy"] as? Int == 0
        }
        mainUI.radioButtons["Legacy"].click()
        wait("Second Legacy transition") {
            self.mainWindow()["sharing"] as? Int == 0 && self.record()["policy"] as? Int == 1
        }
        let cursor = mainUI.descendants(matching: .any).matching(identifier: "private-cursor-toggle").firstMatch
        app.typeKey("c", modifierFlags: [.command, .shift])
        wait("Offline private-cursor shortcut enables its control") { (cursor.value as? Int) == 1 || (cursor.value as? String) == "1" }
        app.typeKey(.escape, modifierFlags: [])
        wait("Escape restores the private-cursor control") { (cursor.value as? Int) == 0 || (cursor.value as? String) == "0" }
        draftContains("1357")
        app.webViews.buttons["Open test popup"].click()
        wait("Popup is configured before being used") {
            (self.record()["windows"] as? [[String: Any]] ?? []).contains {
                $0["identifier"] as? String == "chat-popup" && $0["sharing"] as? Int == 0
            }
        }
        // Use the visible front popup's shared mode control. Its window can
        // cover the main toolbar; clicking through it is not a valid user action.
        app.windows.matching(identifier: "chat-popup").firstMatch.radioButtons["Normal"].click()
        wait("Normal mode and Dock policy restored") {
            self.mainWindow()["sharing"] as? Int == 1 && self.record()["policy"] as? Int == 0 &&
            (self.record()["windows"] as? [[String: Any]] ?? []).contains {
                $0["identifier"] as? String == "chat-popup" && $0["visible"] as? Bool == true && $0["sharing"] as? Int == 1
            }
        }
        app.windows.matching(identifier: "chat-popup").firstMatch.buttons["window-close"].click()
        app.webViews.buttons["Open test dialog"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
        wait("Confirmation sheet inherits Normal sharing") {
            (self.record()["windows"] as? [[String: Any]] ?? []).contains {
                $0["sheet"] as? Bool == true && $0["sharing"] as? Int == 1
            }
        }
        // The webpage is waiting for confirm(). Cancel through the native key
        // rather than recursively querying button descendants of a blocked page.
        app.typeKey(.escape, modifierFlags: [])
        wait("Native confirmation is cancelled") { !self.app.sheets.firstMatch.exists }
        draftContains("1357")
        relaunch()
        wait("Mode recovery preserves the saved outer frame") {
            self.mainWindow()["frame"] as? String == originalFrame && self.record()["previewFrame"] as? String == originalFrame
        }
        wait("Persisted page zoom") { abs((self.mainWindow()["webZoom"] as? Double ?? 0) - 1.4) < 0.01 }
        click("zoom-reset")
        wait("Zoom reset") { abs((self.mainWindow()["webZoom"] as? Double ?? 0) - 0.9) < 0.01 }
    }
    func testWindowGeometryAndMultilineEditing() throws {
        let window = app.windows.matching(identifier: "chat-window").firstMatch
        let x = try XCTUnwrap(mainWindow()["x"] as? Double)
        let y = try XCTUnwrap(mainWindow()["y"] as? Double)
        // Relative native title-bar coordinates, never absolute screen positions.
        let caption = try XCTUnwrap(window.staticTexts.allElementsBoundByIndex.first {
            (($0.value as? String) ?? $0.label).hasPrefix("CaptureShield — UI Preview")
        })
        let title = caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag(title, dx: 40, dy: -40)
        wait("Native title-bar drag") {
            abs((self.mainWindow()["x"] as? Double ?? x) - x - 40) < 3 &&
            abs((self.mainWindow()["y"] as? Double ?? y) - y - 40) < 3
        }
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0))
        drag(right, dx: -340, dy: 0)
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: -1))
        // Cross the minimum boundary rather than relying on the native resize
        // gesture's initial tracking offset to be exactly zero.
        drag(bottom, dx: 0, dy: -300)
        wait("Native resize to minimum") {
            abs((self.mainWindow()["width"] as? Double ?? 0) - 640) < 3 &&
            abs((self.mainWindow()["height"] as? Double ?? 0) - 480) < 3
        }
        editor.click()
        editor.typeText("Line one\nLine two\nLine three\nLine four\nLine five\nLine six\nLine seven\nLine eight")
        draftContains("Line eight")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Replacement draft")
        draftContains("Replacement draft")
        app.typeKey("z", modifierFlags: .command)
        draftContains("Line eight")
        // A multiline editor may consume the first wheel event before scrolling
        // chains to the page. Bound navigation by the actual lower control.
        for _ in 0..<3 where !app.webViews.buttons["Open test popup"].isHittable {
            app.webViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
        }
        wait("Page scroll reveals its lower controls") { self.app.webViews.buttons["Open test popup"].isHittable }
        relaunch()
        wait("Frame survives restart") { abs((self.mainWindow()["width"] as? Double ?? 0) - 640) < 3 }
    }
    func testCropThreeImagesDeleteReaddAndCancel() throws {
        editor.click(); editor.typeText("Keep image draft 8642")
        loadImage()
        wait("Original image dimensions available") { (self.mainWindow()["imageWidth"] as? Int ?? 0) > 0 }
        let originalWidth = try XCTUnwrap(mainWindow()["imageWidth"] as? Int)
        let originalHeight = try XCTUnwrap(mainWindow()["imageHeight"] as? Int)
        let canvas = app.descendants(matching: .any).matching(identifier: "crop-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))
        start.click(forDuration: 0.2, thenDragTo: end)
        click("crop-reset")
        start.click(forDuration: 0.2, thenDragTo: end)
        click("image-add")
        waitText("Images: 1 · Sends: 0")
        wait("Native coordinator confirms the visible webpage attachment") {
            self.mainWindow()["attachmentPhase"] as? String == "visible"
        }
        let dimensions = app.webViews.textFields["Decoded image dimensions"].firstMatch
        XCTAssertTrue(dimensions.waitForExistence(timeout: 10))
        wait("Decoded crop is displayed") { (dimensions.value as? String)?.hasPrefix("Last image: ") == true }
        let size = try XCTUnwrap(dimensions.value as? String)
        let pixels = size.replacingOccurrences(of: "Last image: ", with: "").components(separatedBy: " x ").compactMap(Int.init)
        XCTAssertEqual(pixels.count, 2)
        XCTAssertGreaterThan(pixels[0], 0); XCTAssertLessThan(pixels[0], originalWidth)
        XCTAssertGreaterThan(pixels[1], 0); XCTAssertLessThan(pixels[1], originalHeight)
        for count in 2...3 { loadImage(); click("image-add"); waitText("Images: \(count) · Sends: 0") }
        app.webViews.buttons["Remove file"].firstMatch.click()
        waitText("Images: 2 · Sends: 0")
        loadImage(); click("image-add"); waitText("Images: 3 · Sends: 0")
        loadImage(); click("image-cancel"); waitText("Images: 3 · Sends: 0")
        draftContains("8642")
        mainUI.radioButtons["Legacy"].click()
        wait("Attached images survive Legacy") { self.mainWindow()["sharing"] as? Int == 0 }
        mainUI.radioButtons["Normal"].click()
        wait("Attached images survive Normal recovery") { self.mainWindow()["sharing"] as? Int == 1 }
        waitText("Images: 3 · Sends: 0"); draftContains("8642")
        // This button is on the offline fixture, never the ChatGPT website.
        app.webViews.buttons["Stream reply"].click()
        waitText("Synthetic reply complete. 中文输入保持正常。")
        waitText("Images: 3 · Sends: 1")
    }
    private func drag(_ start: XCUICoordinate, dx: CGFloat, dy: CGFloat) {
        // A destination anchored to the moving window changes during the drag.
        // The native menu bar is stationary; derive its offset from current AX geometry.
        let anchor = app.menuBars.firstMatch.coordinate(withNormalizedOffset: .zero)
        let from = start.screenPoint, fixed = anchor.screenPoint
        let end = anchor.withOffset(CGVector(dx: from.x + dx - fixed.x, dy: from.y + dy - fixed.y))
        start.click(forDuration: 0.2, thenDragTo: end)
    }
    func testCompactWindowMovementCompositionAndVisibility() throws {
        wait("Small initial window") { abs((self.mainWindow()["width"] as? Double ?? 0) - 640) < 1 }
        editor.click(); editor.typeText("Small window text")
        wait("Composition tracker ready") { self.mainWindow()["compositionKnown"] as? Bool == true }
        let before = try XCTUnwrap(mainWindow()["y"] as? Double)
        app.typeKey(.upArrow, modifierFlags: [.command, .shift])
        wait("Window moved 40 points") { abs((self.mainWindow()["y"] as? Double ?? before) - before - 40) < 1 }
        let begin = app.webViews.buttons["Begin synthetic composition"].firstMatch
        begin.hover()
        wait("Composition fixture control is visible") { begin.isHittable }
        begin.click()
        let compositionStatus = app.webViews.textFields["Synthetic composition status"].firstMatch
        wait("Fixture dispatches composition start") { compositionStatus.value as? String == "Composition active" }
        wait("Synthetic composition active") { self.mainWindow()["composing"] as? Bool == true }
        let composingY = mainWindow()["y"] as? Double
        app.typeKey(.upArrow, modifierFlags: [.command, .shift])
        XCTAssertEqual(mainWindow()["y"] as? Double, composingY)
        let commit = app.webViews.buttons["Commit synthetic composition"].firstMatch
        commit.hover()
        wait("Commit fixture control is visible") { commit.isHittable }
        commit.click()
        wait("Synthetic composition ended") { self.mainWindow()["composing"] as? Bool == false }
        app.typeKey("m", modifierFlags: [.command, .shift])
        wait("Main window hidden") { self.mainWindow()["visible"] as? Bool == false }
        // Send the global key while another app owns focus; do not restart Finder.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("m", modifierFlags: [.command, .shift])
        wait("Global shortcut restored the window") { self.mainWindow()["visible"] as? Bool == true }
        app.activate()
        draftContains("Small window text")
        app.windows.firstMatch.buttons["window-minimize"].click()
        wait("Window minimized") { self.mainWindow()["miniaturized"] as? Bool == true }
        app.activate()
        app.typeKey("m", modifierFlags: [.command, .shift])
        app.typeKey("m", modifierFlags: [.command, .shift])
        wait("Window restored") { self.mainWindow()["miniaturized"] as? Bool == false }
    }
    func testSpeechUIAppendCancelAndPreserveImage() throws {
        editor.click(); editor.typeText("Existing speech draft")
        loadImage(); click("image-add"); waitText("Images: 1 · Sends: 0")
        click("toolbar-transcript")
        wait("Synthetic source ready") { self.app.buttons["speech-record"].isEnabled }
        app.typeKey("r", modifierFlags: [.command, .shift])
        wait("Recording state") { self.mainWindow()["speechPhase"] as? String == "recording" && self.mainWindow()["speechRecordTitle"] as? String == "Stop" && self.app.buttons["speech-record"].isHittable }
        click("speech-cancel")
        wait("Cancelled state") { self.mainWindow()["speechPhase"] as? String == "idle" && self.app.buttons["speech-record"].isEnabled }
        draftContains("Existing speech draft")
        click("speech-record")
        wait("Recording again") { self.mainWindow()["speechPhase"] as? String == "recording" && self.mainWindow()["speechRecordTitle"] as? String == "Stop" && self.app.buttons["speech-record"].isHittable }
        click("speech-record")
        draftContains("Synthetic transcript")
        draftContains("中文")
        waitText("Images: 1 · Sends: 0")
        draftContains("Existing speech draft")
        let draft = editor.value as? String ?? ""
        XCTAssertEqual(draft.components(separatedBy: "Synthetic transcript").count - 1, 1)
    }
    func testSpeechRetainedErrorEditDiscard() throws {
        editor.click(); editor.typeText("Retained draft")
        click("toolbar-transcript")
        wait("Fixture source ready") { self.app.buttons["speech-record"].isEnabled }
        click("speech-record")
        wait("Recording") { self.mainWindow()["speechPhase"] as? String == "recording" && self.mainWindow()["speechRecordTitle"] as? String == "Stop" && self.app.buttons["speech-record"].isHittable }
        click("speech-record")
        wait("Failed recognition retained partial") { self.app.staticTexts["speech-summary"].value as? String == "Review required" || self.app.staticTexts["speech-summary"].label == "Review required" }
        click("speech-review")
        let text = app.textViews["speech-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.click(); text.typeKey("a", modifierFlags: .command); text.typeText("Edited retained transcript")
        click("speech-review"); click("speech-review")
        XCTAssertTrue((text.value as? String ?? "").contains("Edited retained transcript"))
        click("speech-add")
        draftContains("Edited retained transcript")
        draftContains("Retained draft")
        wait("Idle after adding") { !self.app.textViews["speech-text"].isHittable }
    }

}

