import AppKit

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
