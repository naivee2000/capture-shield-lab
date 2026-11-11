import Testing
import Foundation
@testable import CaptureCore

struct ChatPreferencesTests {
    @Test func modeAndZoomSurviveRelaunchWithoutChangingEachOther() {
        let name = "CaptureShield-preference-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ChatPreferences.load(from: defaults) == ChatPreferences(mode: .legacy, zoomPercent: 90))
        var chosen = ChatPreferences(mode: .normal, zoomPercent: 120)
        chosen.save(to: defaults)
        #expect(ChatPreferences.load(from: defaults) == chosen)
        chosen.mode = .legacy; chosen.save(to: defaults)
        #expect(ChatPreferences.load(from: defaults).zoomPercent == 120)
        #expect(ChatPreferences.load(from: defaults).mode.opacity == 0.8)
        #expect(ChatSharingMode.normal.opacity == 1)
    }
    @Test func zoomStaysInSupportedRangeAndResetsToCompactDefault() {
        var settings = ChatPreferences(zoomPercent: 70)
        settings.changeZoom(by: -1); #expect(settings.zoomPercent == 70)
        settings.changeZoom(by: 100); #expect(settings.zoomPercent == 140)
        settings.resetZoom(); #expect(settings.zoomPercent == 90)
        #expect(ChatPreferences(zoomPercent: -40).zoomPercent == 70)
        #expect(ChatPreferences(zoomPercent: 900).zoomPercent == 140)
        #expect(ChatPreferences(zoomPercent: 93).zoomPercent == 90)
    }
    @Test func invalidSavedSettingsRecoverWithoutOptingOutOfLegacy() {
        let name = "CaptureShield-preference-test-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("unknown", forKey: "ChatSharingMode")
        defaults.set(900, forKey: "ChatZoomPercent")
        let settings = ChatPreferences.load(from: defaults)
        #expect(settings.mode == .legacy)
        #expect(settings.zoomPercent == 140)
    }
}
