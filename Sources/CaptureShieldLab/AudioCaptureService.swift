import AppKit
import AVFoundation
import ScreenCaptureKit
import CaptureCore

struct SpeechFailure: LocalizedError, Sendable {
    enum Stage: String, Sendable { case permission, source, capture, model, recognition, insertion }
    let stage: Stage
    let code: Int
    let message: String
    var errorDescription: String? { message }
    var diagnostic: String { "\(stage.rawValue), code \(code)" }
}

struct AudioSource: Equatable, Sendable {
    let bundleID: String
    let name: String
    let pid: pid_t
}

/// Converter callbacks may be annotated Sendable even when used synchronously.
/// The immutable buffer is handed out once, with the callback state locked.
final class PCMBufferInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func provide(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock(); defer { lock.unlock() }
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true; status.pointee = .haveData; return buffer
    }
}

/// All audio callbacks and converter state are confined to queue. Access from
/// the main actor uses queue.sync after stopCapture; no raw audio is logged.
final class AudioSampleSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "CaptureShield.AudioSamples")
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var active = true
    let failure: @Sendable (Int) -> Void
    init(failure: @escaping @Sendable (Int) -> Void) { self.failure = failure }
    static var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: Double(SpeechAudioPolicy.sampleRate), channels: 1)! }
    func take() -> [Float] { queue.sync { active = false; defer { samples.removeAll(keepingCapacity: false); converter = nil }; return samples } }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { failure((error as NSError).code) }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .audio, sample.isValid, samples.count < SpeechAudioPolicy.maximumSamples else { return }
        guard let description = sample.formatDescription, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { fail(-1); return }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else { fail(Int(status)); return }
        if converter?.inputFormat != format { converter = AVAudioConverter(from: format, to: Self.format) }
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: Self.format,
            frameCapacity: AVAudioFrameCount(ceil(Double(frames) * Self.format.sampleRate / format.sampleRate)) + 64) else { fail(-2); return }
        let input = PCMBufferInput(buffer)
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in input.provide(status) }
        guard result != .error, let channel = output.floatChannelData?[0] else { fail(error?.code ?? -3); return }
        let count = min(Int(output.frameLength), SpeechAudioPolicy.maximumSamples - samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
    }
    private func fail(_ code: Int) { active = false; failure(code) }
}

@MainActor protocol AudioCaptureProviding: AnyObject {
    var failed: ((Int) -> Void)? { get set }
    func sources() async throws -> [AudioSource]
    func start(source: AudioSource) async throws
    func stop() async -> [Float]
}

@MainActor final class AudioCaptureService: AudioCaptureProviding {
    private var stream: SCStream?
    private var sink: AudioSampleSink?
    private var streamID: UUID?
    private let defaults: UserDefaults
    private let permission: any ScreenCapturePermissionChecking
    var failed: ((Int) -> Void)?
    init(defaults: UserDefaults, permission: any ScreenCapturePermissionChecking = SystemScreenCapturePermission()) {
        self.defaults = defaults; self.permission = permission
    }
    func sources() async throws -> [AudioSource] {
        try ScreenCaptureAuthorization.ensure(defaults: defaults, permission: permission)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.applications.filter { $0.processID != ProcessInfo.processInfo.processIdentifier && !$0.bundleIdentifier.isEmpty }
            .map { AudioSource(bundleID: $0.bundleIdentifier, name: $0.applicationName, pid: $0.processID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func configuration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true; config.captureMicrophone = false; config.excludesCurrentProcessAudio = true
        config.sampleRate = SpeechAudioPolicy.sampleRate; config.channelCount = 1
        // No screen output is registered. Keep unused video production minimal.
        config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        config.showsCursor = false; config.showMouseClicks = false
        return config
    }
    func start(source: AudioSource) async throws {
        guard stream == nil else { return }
        try ScreenCaptureAuthorization.ensure(defaults: defaults, permission: permission)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let app = content.applications.first(where: { $0.processID == source.pid && $0.bundleIdentifier == source.bundleID }),
              let display = content.displays.first else {
            throw SpeechFailure(stage: .source, code: 1, message: "The selected application is no longer available. Refresh sources and select it again.")
        }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let id = UUID()
        let sink = AudioSampleSink { [weak self] code in Task { @MainActor in
            guard self?.streamID == id else { return }; self?.failed?(code)
        } }
        let stream = SCStream(filter: filter, configuration: Self.configuration(), delegate: sink)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
        self.sink = sink; self.stream = stream; streamID = id
        do { try await stream.startCapture(); try Task.checkCancellation() }
        catch { if streamID == id { _ = await stop() }; throw error }
    }
    func stop() async -> [Float] {
        let stream = self.stream, sink = self.sink
        self.stream = nil; self.sink = nil; streamID = nil
        try? await stream?.stopCapture()
        return sink?.take() ?? []
    }
}
