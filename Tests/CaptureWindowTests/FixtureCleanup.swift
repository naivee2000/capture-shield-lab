import AppKit
import Testing
@testable import CaptureShieldLab

/// Only windows created by this native test target use this teardown.
@MainActor extension ChatWindow {
    func closeTestFixture() {
        webView.stopLoading()
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        if let sheet = window?.attachedSheet { window?.endSheet(sheet); sheet.orderOut(nil) }
        window?.close()
    }
}

@MainActor struct FixturePreferences {
    let domain = "CaptureShield-native-test-\(UUID())"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: domain)! }
    func clear() {
        defaults.removePersistentDomain(forName: domain)
        #expect(defaults.persistentDomain(forName: domain)?.isEmpty != false)
    }
}
