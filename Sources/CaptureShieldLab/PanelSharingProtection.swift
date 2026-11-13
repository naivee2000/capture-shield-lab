import AppKit
import ObjectiveC

/// AppKit can create input candidate NSPanel instances outside our window controllers.
/// Interpose the PUBLIC ordering method in this process, setting the PUBLIC sharing
/// property before forwarding. No private class/selector, input text, geometry change,
/// other-process manipulation or IME substitution is involved.
/// This is a compatibility experiment, not a guarantee about compositor/receiver frames.
@MainActor enum PanelSharingProtection {
    private static var installed = false
    private static var legacy = false
    private static let original = NSMapTable<NSPanel, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    static func configure(legacy: Bool) {
        if !installed {
            guard let order = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.order(_:relativeTo:))),
                  let replacement = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.captureShieldOrder(_:relativeTo:))) else { return }
            method_exchangeImplementations(order, replacement)
            installed = true
        }
        Self.legacy = legacy
        NSApp.windows.forEach(prepare)
    }
    static func prepare(_ window: NSWindow) {
        guard let panel = window as? NSPanel else { return }
        if legacy {
            if original.object(forKey: panel) == nil { original.setObject(NSNumber(value: panel.sharingType.rawValue), forKey: panel) }
            WindowProtection.setSharing(of: panel, legacy: true)
        } else if let value = original.object(forKey: panel), let sharing = NSWindow.SharingType(rawValue: value.uintValue) {
            WindowProtection.restoreSharing(of: panel, to: sharing)
            original.removeObject(forKey: panel)
        }
    }
}

extension NSWindow {
    @objc dynamic fileprivate func captureShieldOrder(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
        if place != .out {
            PanelSharingProtection.prepare(self)
            if self is NSPanel, ProcessInfo.processInfo.environment["CAPTURESHIELD_WINDOW_DIAGNOSTICS"] == "1" {
                let entry: [String: Any] = ["event": "before-panel-order", "windowID": windowNumber,
                    "sharing": sharingType.rawValue, "wasVisible": isVisible, "level": level.rawValue]
                if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) {
                    try? FileHandle.standardError.write(contentsOf: data + Data([10]))
                }
            }
        }
        // After exchange, this selector invokes AppKit's original implementation.
        captureShieldOrder(place, relativeTo: otherWindow)
    }
}
