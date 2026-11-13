import AppKit
import XCTest

/// Separate process UI tests: never import CaptureShieldLab or use its account store.
@MainActor final class AppUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_APP"])
        let url = URL(fileURLWithPath: path)
        let bundle = try XCTUnwrap(Bundle(url: url))
        let identifier = try XCTUnwrap(bundle.bundleIdentifier)
        guard identifier.hasPrefix("dev.naivee2000.captureshield.uitest.") else {
            throw NSError(domain: "Unsafe UI target", code: 1)
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: identifier + ".preview"))
        defaults.removePersistentDomain(forName: identifier + ".preview")
        defaults.set("normal", forKey: "ChatSharingMode")
        defaults.set(90, forKey: "ChatZoomPercent")
        defaults.set("{{100, 100}, {980, 700}}", forKey: "ChatWindowFrame")
        defaults.synchronize()
        app = XCUIApplication(url: url)
        app.launchArguments = ["--chat-preview"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
    }
    override func tearDownWithError() throws {
        // This instance was created by the test and has no personal login or draft.
        if let app, app.state != .notRunning { app.terminate() }
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
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews.textViews["Synthetic chat input"].firstMatch.waitForExistence(timeout: 15))
    }
}

