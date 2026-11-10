import AppKit
import CaptureCore

let app = NSApplication.shared
let delegate = LabDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
