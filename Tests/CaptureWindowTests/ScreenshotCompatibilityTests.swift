import Testing
import AppKit
import WebKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor private final class TestPermission: ScreenCapturePermissionChecking {
    var granted: Bool
    var requests = 0
    init(granted: Bool) { self.granted = granted }
    func preflight() -> Bool { granted }
    func request() -> Bool { requests += 1; return granted }
}
@MainActor private final class TestScreenshotBackend: ScreenshotBackend {
    let engine = ScreenshotEngine.compatible
    var calls = 0
    var error: Error?
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        calls += 1
        if let error { throw error }
        return try ImagePreparation.decode(ImagePipelineTests.fixture())
    }
}

@MainActor struct ScreenshotCompatibilityTests {
    @Test func deniedPermissionNeverCapturesOrRepromptsWhenSwitchingEngine() async throws {
        let name = "CaptureShield-permission-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let permission = TestPermission(granted: false), backend = TestScreenshotBackend()
        let service = ScreenshotService(defaults: defaults, permission: permission, backendFactory: { _ in backend })
        #expect(service.permissionGranted == false)
        #expect(permission.requests == 0) // diagnostics must not request access
        for mode in [ScreenshotMode.auto, .compatible] {
            do { _ = try await service.capture(displayID: 1, mode: mode); Issue.record("Denied capture succeeded") }
            catch { #expect(service.lastFailure?.stage == .permission) }
        }
        #expect(permission.requests == 1 && backend.calls == 0)
        permission.granted = true
        _ = try await service.capture(displayID: 1, mode: .compatible)
        #expect(backend.calls == 1 && service.lastFailure == nil)
    }
    @Test func captureFailureIsSanitizedAndNeverAutomaticallyRetries() async throws {
        let permission = TestPermission(granted: true), backend = TestScreenshotBackend()
        backend.error = NSError(domain: "private-domain", code: -123, userInfo: [NSLocalizedDescriptionKey: "secret-chat /Users/private/file token=example"])
        var selected: [ScreenshotEngine] = []
        let service = ScreenshotService(permission: permission, os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0), backendFactory: { engine in selected.append(engine); return backend })
        do { _ = try await service.capture(displayID: 1); Issue.record("Failure swallowed") }
        catch { #expect(!error.localizedDescription.contains("secret-chat")) }
        #expect(backend.calls == 1 && selected == [.modern])
        let report = CompatibilitySummary(os: ProcessInfo.processInfo.operatingSystemVersion, build: "25G83", mode: .auto,
                                          permissionGranted: true, failure: service.lastFailure).text
        #expect(report.contains("capture, code -123"))
        for privateValue in ["secret-chat", "/Users/private", "token=example", "private-domain"] { #expect(!report.contains(privateValue)) }
        backend.error = nil
        _ = try await service.capture(displayID: 1, mode: .compatible)
        #expect(selected == [.modern, .compatible] && service.lastFailure == nil)
    }
    @Test func compatibleConfigurationOmitsCursorAudioAndClicks() {
        let config = CompatibleScreenshotBackend.configuration(width: 1920, height: 1080)
        #expect(config.width == 1920 && config.height == 1080)
        #expect(!config.showsCursor && !config.capturesAudio && !config.captureMicrophone && !config.showMouseClicks)
    }
    @Test func compatibilitySheetPreservesWebViewAndInheritsSharing() {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: configuration, isMain: false, preferences: ChatPreferences(mode: .legacy), preview: true)
        let web = controller.webView
        controller.present(); controller.showCompatibility()
        defer {
            if let sheet = controller.window?.attachedSheet { controller.window?.endSheet(sheet); sheet.orderOut(nil) }
            controller.window?.close()
        }
        #expect(controller.window?.attachedSheet?.sharingType == NSWindow.SharingType.none)
        #expect(controller.window?.attachedSheet?.alphaValue == 1)
        controller.selectScreenshotMode(.compatible)
        #expect(controller.webView === web && controller.preferences.mode == .legacy)
        #expect(controller.preferences.screenshotMode == .compatible)
        controller.applyPreferences(ChatPreferences(mode: .normal, screenshotMode: .compatible))
        #expect(controller.window?.attachedSheet?.sharingType == .readOnly)
        #expect(controller.window?.attachedSheet?.alphaValue == 1)
    }
}
