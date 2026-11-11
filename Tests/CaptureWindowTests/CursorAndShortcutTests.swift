import Testing
import AppKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor private final class CursorFixture: SystemCursorControl {
    var hidden = 0
    var restored = 0
    var succeeds = true
    func hide() -> Bool { hidden += 1; return succeeds }
    func show() { restored += 1 }
}
@MainActor struct CursorAndShortcutTests {
    @Test func cursorLeaseIsBalancedAcrossRepeatedEventsAndFailure() {
        let system = CursorFixture(); let lease = CursorLease(system: system)
        lease.update(active: true); lease.update(active: true)
        #expect(system.hidden == 1 && lease.hidden)
        lease.update(active: false); lease.update(active: false)
        #expect(system.restored == 1 && !lease.hidden)
        system.succeeds = false
        lease.update(active: true); lease.update(active: false)
        #expect(system.hidden == 2 && system.restored == 1 && !lease.hidden)
    }
    @Test func privateCursorRequiresEveryEligibilityConditionAndIsNotReleased() {
        #expect(!PrivateCursorController.qualifiedForNormalUse)
        #expect(CursorEligibility.allows(enabled: true, legacy: true, foreground: true, insideOwnedWindow: true, visible: true, obstructed: false))
        #expect(!CursorEligibility.allows(enabled: true, legacy: false, foreground: true, insideOwnedWindow: true, visible: true, obstructed: false))
        #expect(!CursorEligibility.allows(enabled: true, legacy: true, foreground: false, insideOwnedWindow: true, visible: true, obstructed: false))
        #expect(!CursorEligibility.allows(enabled: true, legacy: true, foreground: true, insideOwnedWindow: false, visible: true, obstructed: false))
        #expect(!CursorEligibility.allows(enabled: true, legacy: true, foreground: true, insideOwnedWindow: true, visible: false, obstructed: false))
        #expect(!CursorEligibility.allows(enabled: true, legacy: true, foreground: true, insideOwnedWindow: true, visible: true, obstructed: true))
    }
    @Test func movementLeavesIMEAndModalEventsUntouched() {
        #expect(ChatKeyboard.direction(keyCode: 126, modifiers: [.command, .option], markedText: false, modal: false) == .up)
        #expect(ChatKeyboard.direction(keyCode: 126, modifiers: [.command], markedText: false, modal: false) == nil)
        #expect(ChatKeyboard.direction(keyCode: 123, modifiers: [.command, .option], markedText: true, modal: false) == nil)
        #expect(ChatKeyboard.direction(keyCode: 124, modifiers: [.command, .option], markedText: false, modal: true) == nil)
    }
}
