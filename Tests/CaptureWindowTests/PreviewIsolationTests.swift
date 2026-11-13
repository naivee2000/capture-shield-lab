import AppKit
import WebKit
import Testing
@testable import CaptureShieldLab

@MainActor struct PreviewIsolationTests {
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
