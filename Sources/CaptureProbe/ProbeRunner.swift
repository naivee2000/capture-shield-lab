import AppKit
import ScreenCaptureKit
import CaptureCore

@MainActor
final class ProbeRunner {
    let screen: NSScreen
    let panelFrame: CGRect
    let directory: URL
    let session: URL
    let captureFirst: Bool
    let web: Bool
    var progress: (String) -> Void = { _ in }
    private var commandRevision = 0
    private var lab: NSRunningApplication?
    private var capture: ScreenStream?
    private(set) var report: RunReport
    private var comparisons: [ProtectionMode: [Comparison]] = [:]
    private var controlsVisible = false

    init(screen: NSScreen, output: URL, captureFirst: Bool, web: Bool = false) throws {
        self.screen = screen; self.captureFirst = captureFirst; self.web = web
        let id = UUID().uuidString
        directory = output.appendingPathComponent(id, isDirectory: true)
        session = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureShield-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let size = CGSize(width: min(640, screen.frame.width - 120), height: min(440, screen.frame.height - 240))
        guard size.width >= 480, size.height >= 360 else { throw ProbeError.message("Use a display with at least 600 × 600 logical points.") }
        panelFrame = CGRect(x: screen.frame.minX + 60, y: screen.frame.minY + 80, width: size.width, height: size.height)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        report = RunReport(id: id, os: ProcessInfo.processInfo.operatingSystemVersionString,
                           displayID: displayID, displayFrame: CGDisplayBounds(displayID),
                           pixelWidth: Int(screen.frame.width * screen.backingScaleFactor),
                           pixelHeight: Int(screen.frame.height * screen.backingScaleFactor),
                           testFrame: panelFrame, order: captureFirst ? "capture-before-window" : "window-before-capture")
        report.surface = web ? "synthetic-webview" : "native-editor"
    }

    func run() async {
        do {
            progress("Requesting full-display recording access…")
            let available = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = available.displays.first(where: { $0.displayID == report.displayID }) else {
                throw ProbeError.message("Selected display is unavailable.")
            }
            let labURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("CaptureShieldLab.app")
            guard FileManager.default.fileExists(atPath: labURL.path) else {
                throw ProbeError.message("CaptureShieldLab.app must be beside CaptureProbe.app. Run scripts/build.sh.")
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false; config.createsNewApplicationInstance = true
            config.arguments = ["--session", session.path] + (web ? ["--web-test"] : [])
            lab = try await NSWorkspace.shared.openApplication(at: labURL, configuration: config)
            let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let quartzFrame = CGRect(x: panelFrame.minX, y: mainHeight - panelFrame.maxY,
                                     width: panelFrame.width, height: panelFrame.height).insetBy(dx: -8, dy: -8)
            let region = try CaptureAnalysis.pixelRect(window: quartzFrame, display: report.displayFrame,
                                                       pixelWidth: report.pixelWidth, pixelHeight: report.pixelHeight)
            // Every stage gets a new unfiltered stream, avoiding reused filter/cache state.
            for mode in [ProtectionMode.ordinary, .maskControl, .legacy, .protectedMask] {
                try Task.checkCancellation()
                progress("Testing \(mode.title)… Keep the test window in place.")
                try await command(mode: mode, visible: false)
                let baselineStream = try ScreenStream(display: display, region: region, width: report.pixelWidth, height: report.pixelHeight)
                capture = baselineStream
                try await baselineStream.start()
                try await Task.sleep(for: .milliseconds(350))
                baselineStream.discardQueuedFrames()
                let baseline = try await baselineStream.nextFrame()
                try savePNG(baseline, to: directory.appendingPathComponent("\(mode.rawValue)-baseline.png"))
                guard CaptureAnalysis.isUsefulBaseline(baseline) else {
                    throw ProbeError.message("Baseline is empty, flat, or not the synthetic checkerboard. Test is invalid.")
                }
                let second = try await baselineStream.nextFrame()
                guard try CaptureAnalysis.compare(second, to: baseline).matchesBackground else {
                    throw ProbeError.message("Background is changing inside the test region. Close overlapping windows and retry.")
                }
                let stream: ScreenStream
                if captureFirst {
                    stream = baselineStream
                    try await command(mode: mode, visible: true)
                } else {
                    await baselineStream.stop()
                    try await command(mode: mode, visible: true)
                    stream = try ScreenStream(display: display, region: region, width: report.pixelWidth, height: report.pixelHeight)
                    capture = stream
                    try await stream.start()
                }
                var samples: [Comparison] = []
                // Stable samples start after command acknowledgement and compositor warmup.
                // Transition flashes are a separate receiver/video test, never claimed here.
                stream.discardQueuedFrames()
                // Sampled capture evidence, not a guarantee against sub-frame flashes.
                for n in 0..<12 {
                    try checkLab(mode: mode, visible: true)
                    let frame = try await stream.nextFrame()
                    try checkLab(mode: mode, visible: true)
                    let comparison = try CaptureAnalysis.compare(frame, to: baseline)
                    samples.append(comparison)
                    if n == 0 || !comparison.matchesBackground {
                        try savePNG(frame, to: directory.appendingPathComponent("\(mode.rawValue)-sample-\(n).png"))
                    }
                }
                comparisons[mode] = samples
                let isControl = mode == .ordinary || mode == .maskControl
                let visible = samples.allSatisfy { $0.mismatchFraction > 0.05 }
                let verdict: Verdict = isControl ? (visible ? .pass : .notTested) : .notTested
                let reason = isControl
                    ? (visible ? "Visible capture control confirmed." : "Visible control missing or unstable: candidate results are invalid.")
                    : "Awaiting control evaluation and local visibility/input confirmation."
                report.stages.append(StageResult(mode: mode, verdict: verdict, reason: reason, sampleCount: samples.count,
                                                  worstMismatch: samples.map(\.mismatchFraction).max(),
                                                  worstMeanError: samples.map(\.meanError).max()))
                await stream.stop(); capture = nil
                try save()
            }
            controlsVisible = [.ordinary, .maskControl].allSatisfy { mode in
                report.stages.first(where: { $0.mode == mode })?.verdict == .pass
            }
            updateCandidateResults()
            try save()
            try await previewCandidate(.legacy)
            progress("Capture finished. Legacy is shown. Check local visibility/input before confirming; select Protected mask to check it separately.")
        } catch {
            await capture?.stop(); capture = nil
            report.error = error.localizedDescription
            // An interrupted run cannot leave earlier candidate rows marked pass.
            for i in report.stages.indices where report.stages[i].mode == .legacy || report.stages[i].mode == .protectedMask {
                report.stages[i].verdict = .notTested; report.stages[i].reason = "Run interrupted: \(error.localizedDescription)"
            }
            for mode in ProtectionMode.allCases where !report.stages.contains(where: { $0.mode == mode }) {
                report.stages.append(StageResult(mode: mode, verdict: .notTested, reason: error.localizedDescription))
            }
            try? save()
            progress("Not completed: \(error.localizedDescription)")
            stopLab()
        }
    }

    func previewCandidate(_ mode: ProtectionMode) async throws {
        guard report.error == nil, mode == .legacy || mode == .protectedMask, comparisons[mode] != nil else {
            throw ProbeError.message("Complete a capture run before selecting a candidate.")
        }
        try await command(mode: mode, visible: true)
    }
    func confirmLocal(_ canSeeAndType: Bool, mode: ProtectionMode) throws {
        guard report.error == nil, mode == .legacy || mode == .protectedMask, comparisons[mode] != nil else {
            throw ProbeError.message("Complete a capture run before confirming.")
        }
        try checkLab(mode: mode, visible: true)
        if let i = report.stages.firstIndex(where: { $0.mode == mode }) {
            report.stages[i].localConfirmed = canSeeAndType
        }
        updateCandidateResults(); try save()
    }
    private func updateCandidateResults() {
        for i in report.stages.indices {
            let mode = report.stages[i].mode
            guard mode == .legacy || mode == .protectedMask else { continue }
            let verdict = Outcome.candidate(frames: comparisons[mode] ?? [], controlsVisible: controlsVisible,
                                            localConfirmed: report.stages[i].localConfirmed)
            report.stages[i].verdict = verdict
            if !controlsVisible { report.stages[i].reason = "Visible controls failed; this result is invalid." }
            else if comparisons[mode]?.contains(where: { !$0.matchesBackground }) == true {
                report.stages[i].reason = "Content or an artifact appeared in capture. See local PNG evidence."
            } else if report.stages[i].localConfirmed == false {
                report.stages[i].reason = "Operator could not see and type in the local window."
            } else if verdict == .pass {
                report.stages[i].reason = "Sampled background matched and operator confirmed local visibility/input. This is not a meeting-app certification."
            } else {
                report.stages[i].reason = "Sampled background matched; local visibility/input is unconfirmed."
            }
        }
    }
    private func command(mode: ProtectionMode, visible: Bool) async throws {
        commandRevision += 1
        try SessionIO.write(LabCommand(revision: commandRevision, mode: mode, visible: visible, frame: panelFrame),
                            to: session.appendingPathComponent("command.json"))
        for _ in 0..<80 {
            try Task.checkCancellation()
            if let state = try? SessionIO.read(LabState.self, from: session.appendingPathComponent("state.json")),
               state.revision == commandRevision {
                if let error = state.error { throw ProbeError.message(error) }
                if state.ready && state.visible == visible { return }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProbeError.message("The lab did not acknowledge the test command.")
    }
    private func checkLab(mode: ProtectionMode, visible: Bool) throws {
        let state = try SessionIO.read(LabState.self, from: session.appendingPathComponent("state.json"))
        guard visible, EvidenceGate.liveState(state, revision: commandRevision, mode: mode, frame: panelFrame,
                                              processAlive: lab?.isTerminated == false, now: Date()) else {
            throw ProbeError.message(state.error ?? "Test window moved, resized, closed, or changed mode; rerun the experiment.")
        }
    }
    func stopLab() {
        commandRevision += 1
        try? SessionIO.write(LabCommand(revision: commandRevision, mode: .ordinary, visible: false, frame: panelFrame, quit: true),
                             to: session.appendingPathComponent("command.json"))
        lab?.terminate()
    }
    func save() throws {
        try SessionIO.write(report, to: directory.appendingPathComponent("report.json"))
        var text = "# CaptureShield Lab run\n\nID: \(report.id)\n\nOS: \(report.os)\n\nOrder: \(report.order)\n\n"
        text += "Surface: \(report.surface ?? "native-editor")\n\n"
        text += "Method: \(report.captureMethod). Cursor omitted; no audio. Local samples do not certify meeting apps or short flashes.\n\n"
        for stage in report.stages {
            text += "- **\(stage.mode.title): \(stage.verdict.rawValue)** — \(stage.reason)\n"
        }
        text += "\n## Meetings\n\n"
        for meeting in report.meetings { text += "- \(meeting.app): \(meeting.verdict.rawValue) — \(meeting.reason)\n" }
        if let error = report.error { text += "\nRun error: \(error)\n" }
        try text.write(to: directory.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }
}
