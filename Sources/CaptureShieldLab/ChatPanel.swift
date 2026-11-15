import AppKit

/// Keep keyboard focus separate from application activation. Never change the
/// nonactivating style after creation; AppKit's window-server state is persistent.
@MainActor final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    static func make(frame: NSRect, style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]) -> ChatPanel {
        let panel = ChatPanel(contentRect: frame, styleMask: style.union(.nonactivatingPanel), backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
    func applyPin(_ enabled: Bool) {
        isFloatingPanel = enabled
        level = enabled ? .floating : .normal
        collectionBehavior = enabled ? [.canJoinAllSpaces, .canJoinAllApplications] : [.moveToActiveSpace, .canJoinAllApplications]
    }
}

/// Only retain an application identity, never another application's input text.
@MainActor final class ChatFocusReturn {
    private var previous: NSRunningApplication?
    func begin() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previous = app }
    }
    func finish() {
        defer { previous = nil }
        // A nonactivating panel normally releases focus back to the active app.
        // Do not override a subsequent deliberate switch to a different app.
        guard let previous, !previous.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        previous.activate(options: [])
    }
}
