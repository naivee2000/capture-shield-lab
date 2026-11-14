import AppKit
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
