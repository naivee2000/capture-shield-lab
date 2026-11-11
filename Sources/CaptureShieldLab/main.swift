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
case .chatPreview: delegate = ChatDelegate(preview: true)
case .lab: delegate = LabDelegate()
}
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
