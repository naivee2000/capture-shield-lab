import AppKit
import CaptureCore

/// An ordinary-arrow resize affordance inside the protected window. The
/// reserved trailing gutter keeps it away from webpage/preview controls.
@MainActor final class LegacyResizeGrip: NSView {
    private var tracking: NSTrackingArea?
    private var origin: (frame: CGRect, pointer: CGPoint)?
    private var hovering = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Drag to resize. Legacy uses an ordinary arrow; Normal also supports window edges."
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Resize window")
        setAccessibilityIdentifier("window-resize-grip")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; NSCursor.arrow.set(); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(hovering ? 0.9 : 0.5).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.2
        for inset in [CGFloat(5), 10, 15] {
            path.move(to: CGPoint(x: bounds.maxX - inset, y: 4))
            path.line(to: CGPoint(x: bounds.maxX - 4, y: inset))
        }
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard let window, (window as? ChatPanel)?.legacyResize == true else { return }
        window.makeKey(); NSCursor.arrow.set()
        origin = (window.frame, window.convertPoint(toScreen: event.locationInWindow))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin, let window, (window as? ChatPanel)?.legacyResize == true,
              let screen = window.screen else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let next = WindowPlacement.resizedFromTopLeft(origin.frame,
            delta: CGSize(width: point.x - origin.pointer.x, height: origin.pointer.y - point.y),
            visibleFrame: screen.visibleFrame)
        (window as? ChatPanel)?.clearLegacyZoom()
        NSCursor.arrow.set(); window.setFrame(next, display: true)
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); origin = nil; NSCursor.arrow.set() }
}
