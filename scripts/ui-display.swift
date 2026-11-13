// Display prerequisites for UI tests. Only ephemeral GitHub jobs may adjust modes.
import AppKit
import CoreGraphics

func report() -> [String: Any] {
    let rect = NSScreen.screens.first?.visibleFrame ?? .zero
    return ["ready": rect.width >= 1200 && rect.height >= 850,
            "visible_width": rect.width, "visible_height": rect.height,
            "scale": NSScreen.screens.first?.backingScaleFactor ?? 0]
}
func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
let argument = Array(CommandLine.arguments.dropFirst())
guard argument == ["--check"] || argument == ["--ci-adjust"] else { exit(2) }
if argument == ["--check"] { let value = report(); emit(value); exit(value["ready"] as? Bool == true ? 0 : 2) }
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
      ProcessInfo.processInfo.environment["CI"] == "true" else {
    emit(["ready": false, "reason": "Display adjustment is restricted to ephemeral GitHub Actions jobs."])
    exit(2)
}
if report()["ready"] as? Bool == true { emit(report()); exit(0) }
let display = CGMainDisplayID()
let available = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
let modes = available.filter { $0.width >= 1280 && $0.height >= 1000 }
    .sorted { $0.width * $0.height < $1.width * $1.height }
guard let mode = modes.first else {
    emit(["ready": false, "reason": "No supported display mode can fit the 980x700 window plus interaction margins.",
          "available_sizes": Array(Set(available.map { "\($0.width)x\($0.height)" })).sorted()])
    exit(2)
}
var configuration: CGDisplayConfigRef?
let begun = CGBeginDisplayConfiguration(&configuration)
guard begun == .success, let configuration else { emit(["ready": false, "stage": "begin-display", "code": begun.rawValue]); exit(2) }
let configured = CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil)
guard configured == .success else {
    CGCancelDisplayConfiguration(configuration)
    emit(["ready": false, "stage": "configure-display", "code": configured.rawValue]); exit(2)
}
let completed = CGCompleteDisplayConfiguration(configuration, .forSession)
guard completed == .success else { emit(["ready": false, "stage": "apply-display", "code": completed.rawValue]); exit(2) }
// A fresh --check process verifies logical points, avoiding NSScreen's old cache.
emit(["configuration": "applied-for-login-session", "requested_width": mode.width, "requested_height": mode.height])
