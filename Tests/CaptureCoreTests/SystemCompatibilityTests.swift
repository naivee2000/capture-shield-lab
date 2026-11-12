import Testing
import Foundation
@testable import CaptureCore

struct SystemCompatibilityTests {
    @Test func runtimeFloorAndEngineSelectionAreIndependentOfVerification() {
        func os(_ major: Int, _ minor: Int = 0) -> OperatingSystemVersion {
            OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        }
        #expect(!SystemCompatibility.supports(os(14, 7)))
        #expect(!SystemCompatibility.supports(os(15, 5)))
        for version in [os(15, 6), os(15, 8), os(26), os(27), os(99)] {
            #expect(SystemCompatibility.supports(version))
            #expect(SystemCompatibility.screenshotEngine(os: version, mode: .compatible) == .compatible)
            #expect(SystemCompatibility.screenshotEngine(os: version, mode: .auto) == (version.majorVersion >= 26 ? .modern : .compatible))
        }
    }
    @Test func switchingEnginesAndOSUpgradeDoNotResetUserPreferences() {
        let name = "CaptureShield-compatibility-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ChatPreferences.load(from: defaults).screenshotMode == .auto)
        let settings = ChatPreferences(mode: .legacy, zoomPercent: 120, screenshotMode: .compatible)
        settings.save(to: defaults)
        #expect(!SystemCompatibility.recordOSBuild("25G83", in: defaults))
        #expect(!SystemCompatibility.recordOSBuild("25G83", in: defaults))
        #expect(!SystemCompatibility.recordOSBuild("unknown", in: defaults))
        #expect(SystemCompatibility.recordOSBuild("26A100", in: defaults))
        #expect(!SystemCompatibility.recordOSBuild("26A100", in: defaults))
        #expect(ChatPreferences.load(from: defaults) == settings)
        defaults.set("future-value", forKey: "ScreenshotMode")
        #expect(ChatPreferences.load(from: defaults).screenshotMode == .auto)
        #expect(ChatPreferences.load(from: defaults).mode == .legacy)
    }
    @Test func deploymentFloorMatchesPackageAndScriptSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(package.contains(".macOS(\"\(SystemCompatibility.minimumVersion)\")"))
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build.sh"), encoding: .utf8)
        #expect(script.contains("<key>LSMinimumSystemVersion</key><string>$MINIMUM_MACOS</string>"))
    }
}
