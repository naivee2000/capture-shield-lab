import Testing
import AppKit
import WebKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor struct WindowTests {
    @Test func orderingOwnedWindowsReconcilesSharingWithTheirCurrentMode() {
        _ = NSApplication.shared
        PanelSharingProtection.configure(legacy: false)
        defer { PanelSharingProtection.configure(legacy: false) }
        for main in [true, false] {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            let controller = ChatWindow(configuration: config, isMain: main, preview: true)
            let window = controller.window!
            defer { window.orderOut(nil) }
            for mode in [ChatSharingMode.normal, .legacy, .normal] {
                controller.applyPreferences(ChatPreferences(mode: mode))
                window.orderOut(nil)
                window.sharingType = mode == .normal ? .none : .readOnly
                window.orderFront(nil)
                #expect(window.sharingType == (mode == .normal ? .readOnly : .none))
            }
            #expect(controller.responds(to: #selector(WKUIDelegate.webView(_:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:))))
        }
    }
    @Test func savedOuterFrameDoesNotGrowWhenTheNativeTitlebarIsRecreated() {
        _ = NSApplication.shared
        let name = "CaptureShield-frame-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let expected = NSRect(x: 100, y: 100, width: 900, height: 600)
        defaults.set(NSStringFromRect(expected), forKey: "ChatWindowFrame")
        for _ in 0..<3 {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            let controller = ChatWindow(configuration: config, isMain: true, defaults: defaults)
            #expect(controller.window?.frame == expected)
            defaults.set(NSStringFromRect(controller.window!.frame), forKey: "ChatWindowFrame")
            controller.window?.close()
        }
    }
    @Test func chatWindowBehavesLikeARegularWindow() {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false)
        let window = controller.window!
        defer { window.orderOut(nil) }
        #expect(!(window is NSPanel))
        #expect(window.level == .normal)
        #expect(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
        #expect(window.alphaValue == 1)
    }
    @Test func normalModeAndZoomSurvivePresentationAndSheetConfiguration() {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false)
        defer { controller.window?.close() }
        controller.applyPreferences(ChatPreferences(mode: .normal, zoomPercent: 140))
        controller.present()
        #expect(controller.window?.sharingType == .readOnly)
        #expect(controller.window?.alphaValue == 1)
        #expect(controller.webView.pageZoom == 1.4)
        let sheet = NSWindow()
        controller.configureAppearance(of: sheet)
        #expect(sheet.sharingType == .readOnly && sheet.alphaValue == 1)
        controller.applyPreferences(ChatPreferences(mode: .legacy, zoomPercent: 70))
        controller.configureAppearance(of: sheet)
        #expect(sheet.sharingType == .none && sheet.alphaValue == 1)
        #expect(controller.webView.pageZoom == 0.7)
    }
}
