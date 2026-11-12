import Testing
import AppKit
@testable import CaptureShieldLab

@Suite(.serialized) @MainActor struct PanelSharingTests {
    @Test func frameworkPanelReceivesProtectionOnFirstOrderAndModeChanges() {
        _ = NSApplication.shared
        PanelSharingProtection.configure(legacy: true)
        defer { PanelSharingProtection.configure(legacy: false) }
        let panel = NSPanel(contentRect: NSRect(x: 60, y: 60, width: 250, height: 30), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.sharingType = .readOnly
        panel.level = NSWindow.Level(rawValue: 20)
        panel.orderFront(nil)
        defer { panel.close() }
        #expect(panel.sharingType == .none)
        #expect(panel.level.rawValue == 20)
        #expect(panel.alphaValue == 1)
        PanelSharingProtection.configure(legacy: false)
        #expect(panel.sharingType == .readOnly)
        PanelSharingProtection.configure(legacy: true)
        #expect(panel.sharingType == .none)
        panel.orderOut(nil); panel.orderFront(nil)
        #expect(panel.sharingType == .none)
    }
}
