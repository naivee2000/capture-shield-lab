import AppKit
import ScreenCaptureKit
import CaptureCore

/// Manual, unfiltered whole-display evidence. Never assigns a hiding verdict.
@MainActor final class CursorRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var finished = false
    private var failure: String?
    private var directory: URL?
    private var metadata: [String: String] = [:]
    private var autoStop: Task<Void, Never>?
    var stopped: ((String) -> Void)?
    private let finalizer = RecordingFinalizer()

    func start(displayID: UInt32, output: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ProbeError.message("Selected display is unavailable.")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = min(1, 4096 / max(1, filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        let width = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale) * scale) / 2 * 2)
        let height = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale) * scale) / 2 * 2)
        let config = IndependentCaptureConfiguration.make(width: width, height: height, includesCursor: true)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 4
        let folder = output.appendingPathComponent("cursor-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        directory = folder
        metadata = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "appVersion": "0.4.0",
                    "capture": "ScreenCaptureKit whole display; empty exclusion list", "showsCursor": "true",
                    "audio": "false", "displayID": String(displayID), "pixels": "\(width)x\(height)",
                    "verdict": "not-tested", "reason": "Manual video requires local visibility and independent receiver review.",
                    "startedAt": ISO8601DateFormatter().string(from: Date()), "recordingStatus": "starting"]
        try saveMetadata()
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = folder.appendingPathComponent("full-display-with-cursor.mp4")
        let recording = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(recording)
        self.stream = stream; self.recording = recording
        do { try await stream.startCapture() }
        catch {
            metadata["recordingStatus"] = "failed"; metadata["errorCode"] = String((error as NSError).code)
            try? saveMetadata(); self.stream = nil; self.recording = nil
            throw ProbeError.message("Cursor recording could not start. Check CaptureProbe's recording permission.")
        }
        autoStop = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            await self?.stop()
        }
    }
    func stop() async {
        autoStop?.cancel(); autoStop = nil
        await finalizer.finish { [self] in await finishRecording() }
    }
    private func finishRecording() async {
        guard stream != nil else { return }
        do { try await stream?.stopCapture() }
        catch { failure = "Capture stopped with error code \((error as NSError).code)." }
        for _ in 0..<100 {
            if finished || failure != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if !finished && failure == nil { failure = "Recording did not confirm finalization." }
        metadata["recordingStatus"] = failure == nil ? "saved" : "failed"
        metadata["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        if let failure { metadata["error"] = failure }
        try? saveMetadata()
        stream = nil; recording = nil
        stopped?(failure ?? "Saved local full-display video with the system cursor. Hiding verdict remains NOT TESTED.")
    }
    private func saveMetadata() throws {
        guard let directory else { return }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("recording.json"), options: .atomic)
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.metadata["recordingStatus"] = "recording"; try? self?.saveMetadata() }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.finished = true }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor [weak self] in self?.failure = "Recording failed with error code \(code)."; await self?.stop() }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor [weak self] in self?.failure = "Stream failed with error code \(code)."; await self?.stop() }
    }
}
