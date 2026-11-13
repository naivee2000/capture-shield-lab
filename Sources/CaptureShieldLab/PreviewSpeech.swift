import Foundation
import CaptureCore
import CaptureCore

/// Only constructed by the offline preview. Never reads applications/audio or downloads models.
@MainActor final class PreviewAudioCapture: AudioCaptureProviding {
    var failed: ((Int) -> Void)?
    func sources() async throws -> [AudioSource] {
        [.init(bundleID: "synthetic.offline.audio", name: "Synthetic audio (no capture)", pid: -1)]
    }
    func start(source: AudioSource) async throws { try Task.checkCancellation() }
    func stop() async -> [Float] { [Float](repeating: 0.2, count: 1600) }
}

@MainActor final class PreviewSpeechBackend: SpeechTranscriptionBackend {
    let name = "Offline UI fixture — no speech recognition"
    private let failure: Bool
    init(failure: Bool) { self.failure = failure }
    func prepare(_ language: TranscriptionLanguage, download: Bool, progress: @escaping @MainActor (Double) -> Void) async throws {
        try Task.checkCancellation(); progress(1)
    }
    func transcribe(_ samples: [Float], language: TranscriptionLanguage,
                    partial: @escaping @MainActor (String) -> Void) async throws -> String {
        partial("Synthetic transcript 中文")
        try await Task.sleep(for: .seconds(2))
        if failure { throw SpeechFailure(stage: .recognition, code: 900, message: "Synthetic recognition failure. No audio was captured.") }
        return "Synthetic transcript 中文"
    }
    func cancel() {}
}
