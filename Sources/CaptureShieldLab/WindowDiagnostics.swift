import AppKit

/// Opt-in, metadata-only output for candidate ownership investigations. No titles/text.
@MainActor final class WindowDiagnostics {
    private var timer: Timer?
    private var previous = ""
    private var metadataURL: URL?
    func startIfRequested(preview: Bool = false) {
        if preview, Bundle.main.bundleIdentifier?.hasPrefix("dev.naivee2000.captureshield.uitest.") == true,
           let path = ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_METADATA"], path.hasPrefix("/") {
            metadataURL = URL(fileURLWithPath: path)
        }
        guard metadataURL != nil || ProcessInfo.processInfo.environment["CAPTURESHIELD_WINDOW_DIAGNOSTICS"] == "1" else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
    }
    private func record() {
        let windows: [[String: Any]] = NSApp.windows.map { window in
            let chat = window.delegate as? ChatWindow
            var row: [String: Any] = ["windowID": window.windowNumber, "class": NSStringFromClass(type(of: window)),
             "visible": window.isVisible, "sharing": window.sharingType.rawValue,
             "level": window.level.rawValue, "frame": NSStringFromRect(window.frame),
             "identifier": chat.map { $0.isMain ? "chat-window" : "chat-popup" } ?? "system-panel",
             "alpha": window.alphaValue, "backgroundAlpha": window.backgroundColor.alphaComponent,
             "x": window.frame.minX, "y": window.frame.minY,
             "width": window.frame.width, "height": window.frame.height,
             "miniaturized": window.isMiniaturized]
            if let view = window.contentView.flatMap(Self.webView) {
                row["webZoom"] = view.pageZoom
                row["webAlpha"] = view.alphaValue
                if let owner = view.navigationDelegate as? ChatWindow {
                    row["compositionKnown"] = owner.composition.composing != nil
                    row["composing"] = owner.composition.composing ?? false
                    row["attachmentPhase"] = String(describing: owner.images.phase)
                    if metadataURL != nil {
                        if let image = owner.images.image {
                            row["imageWidth"] = image.width; row["imageHeight"] = image.height
                        }
                        row["speechPhase"] = String(describing: owner.speech.phase)
                        row["speechSourceSelected"] = owner.speechPane.selectedAudioSource != nil
                        row["speechRecordTitle"] = owner.speechPane.record.title
                    }
                }
            }
            return row
        }.sorted { ($0["windowID"] as? Int ?? 0) < ($1["windowID"] as? Int ?? 0) }
        var testRecord: [String: Any] = ["policy": NSApp.activationPolicy().rawValue, "windows": windows,
                                      "processID": ProcessInfo.processInfo.processIdentifier]
        if metadataURL != nil {
            let defaults = UserDefaults(suiteName: Bundle.main.bundleIdentifier! + ".preview")!
            testRecord["previewFrame"] = defaults.string(forKey: "ChatWindowFrame") ?? "missing"
            testRecord["previewSourceSet"] = defaults.string(forKey: "SpeechSourceBundleID") == "synthetic.offline.audio"
            testRecord["testToken"] = defaults.string(forKey: "UITestSeedToken") ?? "missing"
            testRecord["screens"] = NSScreen.screens.map { NSStringFromRect($0.visibleFrame) }
        }
        let record: Any = metadataURL == nil ? windows : testRecord
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8), line != previous else { return }
        previous = line
        if let metadataURL { try? data.write(to: metadataURL, options: .atomic); return }
        try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
    }
    private static func webView(_ view: NSView) -> ChatWebView? {
        if let web = view as? ChatWebView { return web }
        return view.subviews.lazy.compactMap(webView).first
    }
    func stop() { timer?.invalidate(); timer = nil }
}
