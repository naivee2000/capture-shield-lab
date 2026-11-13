import AppKit
import CaptureCore

@MainActor enum ApplicationPresentation {
    static func policy(for mode: ChatSharingMode) -> NSApplication.ActivationPolicy {
        mode == .legacy ? .accessory : .regular
    }
    @discardableResult static func apply(_ mode: ChatSharingMode) -> Bool {
        let desired = policy(for: mode)
        return NSApp.activationPolicy() == desired || NSApp.setActivationPolicy(desired)
    }
}
