import AppKit

/// Opt-in, metadata-only output for candidate ownership investigations. No titles/text.
@MainActor final class WindowDiagnostics {
    private var timer: Timer?
    private var previous = ""
    func startIfRequested() {
        guard ProcessInfo.processInfo.environment["CAPTURESHIELD_WINDOW_DIAGNOSTICS"] == "1" else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
    }
    private func record() {
        let windows: [[String: Any]] = NSApp.windows.map { window in
            ["windowID": window.windowNumber, "class": NSStringFromClass(type(of: window)),
             "visible": window.isVisible, "sharing": window.sharingType.rawValue,
             "level": window.level.rawValue, "frame": NSStringFromRect(window.frame)]
        }.sorted { ($0["windowID"] as? Int ?? 0) < ($1["windowID"] as? Int ?? 0) }
        guard let data = try? JSONSerialization.data(withJSONObject: windows, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8), line != previous else { return }
        previous = line
        try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
    }
    func stop() { timer?.invalidate(); timer = nil }
}
