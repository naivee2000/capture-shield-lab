import AppKit
import CaptureCore

/// Keep keyboard focus separate from application activation. Never change the
/// nonactivating style after creation; AppKit's window-server state is persistent.
@MainActor final class ChatPanel: NSPanel {
    private(set) var legacyResize = false
    private var legacyZoomFrame: NSRect?
    private var legacyZoomButton: NSButton?
    var zoomControl: NSButton? { legacyResize ? legacyZoomButton : standardWindowButton(.zoomButton) }
    func clearLegacyZoom() { legacyZoomFrame = nil }
    func applyResizePolicy(legacy: Bool) {
        guard legacyResize != legacy else { return }
        legacyResize = legacy; legacyZoomFrame = nil
        // Do not change the nonactivatingPanel identity after construction.
        let frame = self.frame
        if legacy { styleMask.remove(.resizable) } else { styleMask.insert(.resizable) }
        setFrame(frame, display: false)
        legacyZoomButton?.removeFromSuperview(); legacyZoomButton = nil
        if let native = standardWindowButton(.zoomButton), let parent = native.superview {
            native.isHidden = legacy
            if legacy {
                // AppKit deliberately disables its zoom widget on a nonresizable
                // shell. Keep zoom/restore in the same traffic-light location.
                let button = LegacyZoomButton(frame: native.frame)
                button.autoresizingMask = native.autoresizingMask
                button.target = self; button.action = #selector(zoom(_:))
                button.setAccessibilityLabel("Zoom window")
                button.setAccessibilityIdentifier("window-zoom")
                button.toolTip = "Zoom / Restore window"
                parent.addSubview(button); legacyZoomButton = button
            }
        }
        invalidateCursorRects(for: contentView ?? NSView())
    }
    override func zoom(_ sender: Any?) {
        guard legacyResize else { super.zoom(sender); return }
        if let previous = legacyZoomFrame {
            legacyZoomFrame = nil
            setFrame(WindowPlacement.restore(previous, screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        } else if let screen {
            legacyZoomFrame = frame; setFrame(screen.visibleFrame, display: true)
        }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Responders (WebKit, IME and sheets) handle their own cancellation first.
    // An unhandled Escape must not close this persistent chat panel.
    override func cancelOperation(_ sender: Any?) {}
    static func visibleOwned(_ owned: [NSWindow], ordered: [NSWindow]) -> [NSWindow] {
        let known = ordered.filter { owned.contains($0) }
        return (known + owned.reversed().filter { !known.contains($0) })
            .filter { $0.isVisible && !$0.isMiniaturized }
    }
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

@MainActor private final class LegacyZoomButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12)
        NSColor.systemGreen.setFill(); NSBezierPath(ovalIn: circle).fill()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let plus = NSBezierPath(); plus.lineWidth = 1
        plus.move(to: NSPoint(x: bounds.midX - 3, y: bounds.midY)); plus.line(to: NSPoint(x: bounds.midX + 3, y: bounds.midY))
        plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 3)); plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 3))
        plus.stroke()
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
