import AVFoundation
import Speech
import CaptureCore

@MainActor protocol SpeechTranscriptionBackend: AnyObject {
    var name: String { get }
    func prepare(_ language: TranscriptionLanguage, download: Bool, progress: @escaping @MainActor (Double) -> Void) async throws
    func transcribe(_ samples: [Float], language: TranscriptionLanguage, partial: @escaping @MainActor (String) -> Void) async throws -> String
    func cancel()
}

@MainActor enum SpeechBackends {
    static func make() -> any SpeechTranscriptionBackend {
        if #available(macOS 26, *) { return ModernSpeechBackend() }
        return CompatibleSpeechBackend()
    }
    static func buffer(_ samples: ArraySlice<Float>) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: AudioSampleSink.format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { buffer.floatChannelData![0].update(from: base, count: samples.count) }
        }
        return buffer
    }
}

@available(macOS 26, *)
@MainActor final class ModernSpeechBackend: SpeechTranscriptionBackend {
    let name = "SpeechAnalyzer (on device)"
    private var analyzer: SpeechAnalyzer?
    private var prepared: SpeechTranscriber?
    private var preparedLanguage: TranscriptionLanguage?
    func prepare(_ language: TranscriptionLanguage, download: Bool, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else {
            throw SpeechFailure(stage: .model, code: 1, message: "This device does not support the selected on-device language. No audio was recorded.")
        }
        let transcriber: SpeechTranscriber
        if preparedLanguage == language, let prepared { transcriber = prepared }
        else { transcriber = SpeechTranscriber(locale: locale, preset: .transcription); prepared = transcriber; preparedLanguage = language }
        try await AssetInventory.reserve(locale: locale)
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            guard download else { throw SpeechFailure(stage: .model, code: 2, message: "Language model is not installed. Click Prepare language to download it before recording.") }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let monitor = Task { while !Task.isCancelled { progress(request.progress.fractionCompleted); try? await Task.sleep(for: .milliseconds(200)) } }
                defer { monitor.cancel() }
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw SpeechFailure(stage: .model, code: 5, message: "Apple's language assets are not ready after preparation. No audio was recorded. Try Prepare language again later.")
            }
        }
        try Task.checkCancellation(); progress(1)
    }
    func transcribe(_ samples: [Float], language: TranscriptionLanguage, partial: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.rawValue)) else { throw CancellationError() }
        // Each analysis owns a fresh result sequence, including consecutive recordings.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = AVAudioConverter(from: AudioSampleSink.format, to: format) else {
            throw SpeechFailure(stage: .recognition, code: 1, message: "No supported speech audio format is available.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber]); self.analyzer = analyzer
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let reader = Task { @MainActor in
            var text = ""
            for try await result in transcriber.results {
                try Task.checkCancellation()
                text += String(result.text.characters); partial(text)
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            try await analyzer.start(inputSequence: input)
            for start in stride(from: 0, to: samples.count, by: SpeechAudioPolicy.sampleRate) {
                try Task.checkCancellation()
                let buffer = SpeechBackends.buffer(samples[start..<min(samples.count, start + SpeechAudioPolicy.sampleRate)])
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 64
                let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
                let input = PCMBufferInput(buffer)
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, status in input.provide(status) }
                guard status != .error else { throw SpeechFailure(stage: .recognition, code: error?.code ?? 2, message: "Audio conversion failed.") }
                continuation.yield(AnalyzerInput(buffer: output))
                await Task.yield()
            }
            let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
            var tailError: NSError?
            _ = converter.convert(to: tail, error: &tailError) { _, status in status.pointee = .endOfStream; return nil }
            if tail.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: tail)) }
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await reader.value
            self.analyzer = nil; return text
        } catch {
            continuation.finish(); reader.cancel(); await analyzer.cancelAndFinishNow(); self.analyzer = nil
            throw error
        }
    }
    func cancel() { let current = analyzer; analyzer = nil; Task { await current?.cancelAndFinishNow() } }
}

/// macOS 15.6 path. Never starts a request unless local recognition is supported.
@MainActor final class CompatibleSpeechBackend: SpeechTranscriptionBackend {
    let name = "SFSpeechRecognizer (on device, segmented)"
    private var current: LegacySpeechRequest?
    func prepare(_ language: TranscriptionLanguage, download: Bool, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)), recognizer.supportsOnDeviceRecognition else {
            throw SpeechFailure(stage: .model, code: 1, message: "On-device recognition for this language is unavailable. Install its Dictation language in macOS settings or use macOS 26+. Cloud recognition is disabled.")
        }
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined {
            guard download else { throw SpeechFailure(stage: .permission, code: 2, message: "Click Prepare language to authorize on-device Speech Recognition.") }
            authorization = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        }
        guard authorization == .authorized else { throw SpeechFailure(stage: .permission, code: 3, message: "Allow Speech Recognition for CaptureShieldLab in System Settings. No audio was recorded.") }
        guard recognizer.isAvailable else { throw SpeechFailure(stage: .model, code: 3, message: "The on-device speech service is currently unavailable.") }
        progress(1)
    }
    func transcribe(_ samples: [Float], language: TranscriptionLanguage, partial: @escaping @MainActor (String) -> Void) async throws -> String {
        let chunks = SpeechAudioPolicy.chunks(sampleCount: samples.count)
        var results: [[TimedSpeechSegment]] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let request = LegacySpeechRequest(); current = request
            let segments = try await request.run(samples[chunk], language: language)
            current = nil; results.append(segments)
            partial(SpeechAudioPolicy.merge(results, chunks: chunks, language: language))
        }
        return SpeechAudioPolicy.merge(results, chunks: chunks, language: language)
    }
    func cancel() { current?.finish(.failure(CancellationError())); current = nil }
}

@MainActor private final class LegacySpeechRequest {
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[TimedSpeechSegment], any Error>?
    private var timeout: Task<Void, Never>?
    func run(_ samples: ArraySlice<Float>, language: TranscriptionLanguage) async throws -> [TimedSpeechSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)), recognizer.supportsOnDeviceRecognition else {
            throw SpeechFailure(stage: .model, code: 1, message: "Local speech recognition became unavailable.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false; request.addsPunctuation = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let segments = result?.isFinal == true ? result?.bestTranscription.segments.map {
                    TimedSpeechSegment(text: $0.substring, start: $0.timestamp, duration: $0.duration)
                } : nil
                let code = error.map { ($0 as NSError).code }
                Task { @MainActor in
                    if let segments { self?.finish(.success(segments)) }
                    else if let code { self?.finish(.failure(SpeechFailure(stage: .recognition, code: code, message: "Local speech recognition failed. Any completed segments remain available for review."))) }
                }
            }
            request.append(SpeechBackends.buffer(samples)); request.endAudio()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.finish(.failure(SpeechFailure(stage: .recognition, code: 408, message: "Local speech recognition timed out.")))
            }
        }
    }
    func finish(_ result: Result<[TimedSpeechSegment], any Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil; task?.cancel(); task = nil
        continuation.resume(with: result)
    }
}
