import AppKit
import WebKit
import Testing
@testable import CaptureShieldLab

@MainActor struct PreviewIsolationTests {
    @Test func testSeedIsIsolatedAndDoesNotResetRestartedPreferences() throws {
        let id = "dev.naivee2000.captureshield.uitest.seed-\(UUID())"
        let defaults = UserDefaults(suiteName: id + ".preview")!
        defer { defaults.removePersistentDomain(forName: id + ".preview") }
        let payload = "{\"token\":\"\(UUID())\",\"compact\":true,\"speechFailure\":true}"
        PreviewTestConfiguration.apply(bundleID: id, payload: payload)
        #expect(defaults.string(forKey: "ChatSharingMode") == "normal")
        #expect(defaults.string(forKey: "ChatWindowFrame") == "{{100, 100}, {640, 480}}")
        defaults.set(140, forKey: "ChatZoomPercent")
        PreviewTestConfiguration.apply(bundleID: id, payload: payload)
        #expect(defaults.integer(forKey: "ChatZoomPercent") == 140)
        let unrelated = "CaptureShield-seed-negative-\(UUID())"
        let other = UserDefaults(suiteName: unrelated + ".preview")!
        defer { other.removePersistentDomain(forName: unrelated + ".preview") }
        other.set(70, forKey: "ChatZoomPercent")
        PreviewTestConfiguration.apply(bundleID: unrelated, payload: payload)
        #expect(other.integer(forKey: "ChatZoomPercent") == 70)
    }
    @Test func offlineSpeechDoesNotUseSystemCaptureOrModels() async throws {
        let capture = PreviewAudioCapture()
        let sources = try await capture.sources()
        #expect(sources.count == 1 && sources[0].bundleID == "synthetic.offline.audio")
        try await capture.start(source: sources[0])
        let samples = await capture.stop()
        let backend = PreviewSpeechBackend(failure: false)
        var progress = 0.0
        try await backend.prepare(.english, download: true) { progress = $0 }
        #expect(progress == 1 && backend.name.contains("no speech recognition"))
        let text = try await backend.transcribe(samples, language: .english) { _ in }
        #expect(text == "Synthetic transcript 中文")
    }
    @Test func offlineFailurePreservesAReviewablePartial() async throws {
        let backend = PreviewSpeechBackend(failure: true)
        var partial = ""
        do {
            _ = try await backend.transcribe([0.2], language: .english) { partial = $0 }
            Issue.record("Expected the deterministic offline failure")
        } catch let error as SpeechFailure {
            #expect(error.code == 900 && partial == "Synthetic transcript 中文")
        }
    }
}
