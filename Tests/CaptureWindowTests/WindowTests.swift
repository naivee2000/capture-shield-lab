import Testing
import AppKit
import WebKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor struct WindowTests {
    @Test func replacementShellPreservesWebViewDraftImageAndUndo() async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false,
                                    preferences: ChatPreferences(mode: .normal), preview: true)
        defer { controller.window?.close() }
        let old = controller.window!, content = old.contentView!, web = controller.webView
        let store = web.configuration.websiteDataStore
        controller.present(); controller.goHome()
        var loaded = false
        for _ in 0..<100 {
            loaded = (try? await web.evaluateJavaScript("Boolean(document.querySelector('[contenteditable]'))")) as? Bool == true
            if loaded { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(loaded)
        _ = try await web.evaluateJavaScript("const editor=document.querySelector('[contenteditable]');editor.focus();document.execCommand('insertText',false,'Preserved synthetic draft');document.querySelector('#attachments').append(document.createElement('img'))")
        _ = try await web.evaluateJavaScript("document.execCommand('undo')")
        let baselineUndo = try await web.evaluateJavaScript("document.querySelector('[contenteditable]').textContent") as? String
        #expect(baselineUndo == "")
        _ = try await web.evaluateJavaScript("document.execCommand('redo')")
        let frame = old.frame
        old.sharingType = .none
        #expect(controller.replaceNormalWindowShell())
        #expect(controller.window !== old && controller.window?.contentView === content)
        #expect(controller.webView === web && web.configuration.websiteDataStore === store)
        #expect(controller.window?.frame == frame && controller.window?.minSize == NSSize(width: 640, height: 480))
        #expect(controller.window?.sharingType == .readOnly)
        #expect(try await web.evaluateJavaScript("document.querySelector('[contenteditable]').textContent") as? String == "Preserved synthetic draft")
        #expect(try await web.evaluateJavaScript("document.querySelector('#attachments').children.length") as? Int == 1)
        #expect(try await web.evaluateJavaScript("sends") as? Int == 0)
        _ = try await web.evaluateJavaScript("document.execCommand('undo')")
        let afterUndo = try await web.evaluateJavaScript("document.querySelector('[contenteditable]').textContent") as? String
        #expect(afterUndo == "")
    }
    @Test func loadedPreviewRestoresNormalSharing() async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false,
                                    preferences: ChatPreferences(mode: .normal), preview: true)
        let priorPolicy = NSApp.activationPolicy()
        defer { controller.window?.close(); PanelSharingProtection.configure(legacy: false); NSApp.setActivationPolicy(priorPolicy) }
        controller.present(); controller.goHome()
        var loaded = false
        for _ in 0..<100 {
            loaded = (try? await controller.webView.evaluateJavaScript("Boolean(document.querySelector('[contenteditable]'))")) as? Bool == true
            if loaded { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(loaded)
        #expect(controller.window?.sharingType == .readOnly)
        controller.window?.orderOut(nil)
        PanelSharingProtection.configure(legacy: true)
        controller.applyPreferences(ChatPreferences(mode: .legacy))
        _ = ApplicationPresentation.apply(.legacy)
        controller.window?.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.window?.sharingType == NSWindow.SharingType.none)
        controller.window?.orderOut(nil)
        PanelSharingProtection.configure(legacy: false)
        controller.applyPreferences(ChatPreferences(mode: .normal))
        _ = ApplicationPresentation.apply(.normal)
        controller.window?.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.window?.sharingType == .readOnly)
    }
    @Test func confirmationDelegateIsExposedThroughWebKitsPublicSelector() {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false, preview: true)
        defer { controller.window?.orderOut(nil) }
        #expect(controller.responds(to: #selector(WKUIDelegate.webView(_:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:))))
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
        #expect(window.minSize == NSSize(width: 640, height: 480))
    }
    @Test func normalModeAndZoomSurvivePresentationAndSheetConfiguration() {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false)
        defer { controller.window?.close() }
        controller.applyPreferences(ChatPreferences(mode: .normal, zoomPercent: 140))
        controller.present()
        #expect(controller.window?.minSize == NSSize(width: 640, height: 480))
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
        controller.applyPreferences(ChatPreferences(mode: .normal, zoomPercent: 90))
        #expect(controller.window?.sharingType == .readOnly)
        #expect(controller.window?.minSize == NSSize(width: 640, height: 480))
    }
}
