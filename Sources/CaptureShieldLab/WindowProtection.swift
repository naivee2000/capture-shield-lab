import AppKit
import CaptureCore

/// One place for capture-related AppKit writes. Availability is not a hiding verdict.
@MainActor enum WindowProtection {
    static func setSharing(of window: NSWindow, legacy: Bool) {
        window.sharingType = legacy ? .none : .readOnly
        WindowDiagnostics.activeTest?.noteTransition("sharing-setter", mode: legacy ? "legacy" : "normal", windows: [window])
    }
    static func restoreSharing(of window: NSWindow, to value: NSWindow.SharingType) {
        window.sharingType = value
    }
    static func apply(to window: NSWindow, mode: ChatSharingMode) {
        window.alphaValue = 1; window.level = .normal; window.hasShadow = false
        setSharing(of: window, legacy: mode == .legacy)
    }
    @discardableResult static func reconcileAfterDisplay(_ window: NSWindow, mode: ChatSharingMode) -> Bool {
        guard mode == .normal, window.isVisible else { return true }
        // Some hosts retain .none when relaxing an ordered-out window. Check
        // once after display; Legacy is still configured before any ordering.
        if window.sharingType != .readOnly { setSharing(of: window, legacy: false) }
        return window.sharingType == .readOnly
    }
}
