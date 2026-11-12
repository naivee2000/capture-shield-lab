import AppKit

@MainActor protocol SystemCursorControl: AnyObject {
    func hide() -> Bool
    func show()
}
@MainActor final class CursorLease {
    private(set) var hidden = false
    private let system: any SystemCursorControl
    init(system: any SystemCursorControl) { self.system = system }
    func update(active: Bool) {
        if active && !hidden { hidden = system.hide() }
        if !active && hidden { system.show(); hidden = false }
    }
}
enum CursorEligibility {
    static func allows(enabled: Bool, legacy: Bool, foreground: Bool, insideOwnedWindow: Bool, visible: Bool, obstructed: Bool) -> Bool {
        enabled && legacy && foreground && insideOwnedWindow && visible && !obstructed
    }
}
@MainActor private final class NativeSystemCursor: SystemCursorControl {
    func hide() -> Bool { CGDisplayHideCursor(CGMainDisplayID()) == .success }
    func show() { _ = CGDisplayShowCursor(CGMainDisplayID()) }
}
@MainActor private final class CursorDrawing: NSView {
    var point: CGPoint = .zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let cursor = NSCursor.arrow
        cursor.image.draw(at: CGPoint(x: point.x - cursor.hotSpot.x, y: point.y - cursor.hotSpot.y),
                          from: .zero, operation: .sourceOver, fraction: 1)
    }
}
@MainActor final class PrivateCursorController: NSObject {
    // No receiver verdict exists for 0.4. Never infer support from NSCursor/SCStream calls.
    static let qualifiedForNormalUse = false
    let available: Bool
    private(set) var enabled = false
    var changed: (() -> Void)?
    private let windows: () -> [NSWindow]
    private let lease = CursorLease(system: NativeSystemCursor())
    private var overlay: NSPanel?
    private var drawing: CursorDrawing?
    private var timer: Timer?
    private var menuOpen = false
    init(experimental: Bool, windows: @escaping () -> [NSWindow]) {
        self.available = experimental || Self.qualifiedForNormalUse; self.windows = windows
        super.init()
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSWindow.didMiniaturizeNotification, NSWindow.didResignKeyNotification] {
            center.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(disable), name: NSWorkspace.willSleepNotification, object: nil)
    }
    func toggle(legacy: Bool) {
        guard available, legacy else { disable(); return }
        enabled.toggle(); changed?()
        if enabled {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common); refresh()
        } else { timer?.invalidate(); timer = nil; suspend() }
    }
    @objc func disable() { enabled = false; timer?.invalidate(); timer = nil; suspend(); changed?() }
    @objc private func menuBegan() { menuOpen = true; suspend() }
    @objc private func menuEnded() { menuOpen = false }
    @objc func suspend() {
        lease.update(active: false)
        if let overlay { overlay.parent?.removeChildWindow(overlay); overlay.orderOut(nil) }
        overlay = nil; drawing = nil
    }
    private func refresh() {
        let point = NSEvent.mouseLocation
        guard enabled, NSApp.isActive, !menuOpen, NSApp.modalWindow == nil else { suspend(); return }
        let owned = windows()
        guard let key = NSApp.keyWindow, owned.contains(key) else { suspend(); return }
        var number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        if number == overlay?.windowNumber {
            number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: number)
        }
        guard let parent = owned.first(where: { $0.windowNumber == number }),
              CursorEligibility.allows(enabled: enabled, legacy: parent.sharingType == .none,
                 foreground: NSApp.isActive, insideOwnedWindow: parent.frame.contains(point),
                 visible: parent.isVisible && !parent.isMiniaturized, obstructed: false) else { suspend(); return }
        if overlay?.parent !== parent {
            suspend()
            let panel = NSPanel(contentRect: parent.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; WindowProtection.setSharing(of: panel, legacy: true); panel.level = .normal
            panel.alphaValue = parent.alphaValue; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.transient, .ignoresCycle]
            let view = CursorDrawing(frame: CGRect(origin: .zero, size: parent.frame.size))
            view.autoresizingMask = [.width, .height]; panel.contentView = view
            overlay = panel; drawing = view; parent.addChildWindow(panel, ordered: .above)
        }
        overlay?.setFrame(parent.frame, display: false)
        drawing?.point = CGPoint(x: point.x - parent.frame.minX, y: parent.frame.maxY - point.y)
        overlay?.orderFront(nil); drawing?.displayIfNeeded()
        // Establish the local visual before hiding the real pointer.
        lease.update(active: overlay?.isVisible == true)
        if !lease.hidden { disable() }
    }
    func shutdown() {
        disable(); NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
