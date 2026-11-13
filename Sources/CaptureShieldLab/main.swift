import AppKit
import CaptureCore

let app = NSApplication.shared
let mode: LaunchMode
do { mode = try LaunchMode.parse(Array(CommandLine.arguments.dropFirst())) }
catch {
    fputs("Usage: CaptureShieldLab [--chat-preview | --lab | --web-test] [--session /absolute/test/directory]\n", stderr)
    exit(2)
}
let delegate: any NSApplicationDelegate
switch mode {
case .chat: delegate = ChatDelegate()
case .chatPreview:
    PreviewTestConfiguration.apply()
    delegate = ChatDelegate(preview: true)
case .lab: delegate = LabDelegate()
}
switch mode {
case .lab: app.setActivationPolicy(.regular)
case .chat: ApplicationPresentation.apply(ChatPreferences.load(from: .standard).mode)
case .chatPreview:
    let defaults = UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "CaptureShield").preview")!
    ApplicationPresentation.apply(ChatPreferences.load(from: defaults).mode)
}
app.delegate = delegate
app.run()
