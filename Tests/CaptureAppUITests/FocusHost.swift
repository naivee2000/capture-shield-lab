import AppKit

@MainActor final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1260, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    let state = NSTextField(labelWithString: "Windowed")
    let input = NSTextField(string: "Background draft")
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.delegate = self
        state.frame = NSRect(x: 1100, y: 500, width: 150, height: 24)
        state.setAccessibilityIdentifier("background-state")
        window.contentView!.addSubview(state)
        window.title = "Synthetic background — focus test"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        input.frame = NSRect(x: 1100, y: 600, width: 150, height: 32)
        input.setAccessibilityIdentifier("background-input")
        window.contentView!.addSubview(input)
        let button = NSButton(title: "Toggle full screen", target: self, action: #selector(fullscreen))
        button.frame = NSRect(x: 1100, y: 550, width: 150, height: 32)
        button.setAccessibilityIdentifier("background-fullscreen")
        window.contentView!.addSubview(button)
        let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input); NSApp.activate()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { state.stringValue = "Full screen" }
    func windowDidExitFullScreen(_ notification: Notification) { state.stringValue = "Windowed" }
    @objc func fullscreen() { window.toggleFullScreen(nil) }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let host = Host()
    app.setActivationPolicy(.regular); app.delegate = host; app.run()
}
