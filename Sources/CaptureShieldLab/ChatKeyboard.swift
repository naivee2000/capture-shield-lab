import AppKit
import CaptureCore
import Carbon

enum ChatKeyboard {
    static let modifiers: NSEvent.ModifierFlags = [.command, .shift]
    static let carbonModifiers = UInt32(cmdKey | shiftKey)
    static let visibilityKey = UInt32(kVK_ANSI_M)
    static let screenshotKey = UInt32(kVK_ANSI_2)
    static let cursorKey: UInt16 = UInt16(kVK_ANSI_C)
    static let visibilityLabel = "⌘⇧M"
    static let screenshotLabel = "⌘⇧2"
    static let cursorLabel = "⌘⇧C"
    static let movementLabel = "⌘⇧arrows"
    static var summary: String { "\(screenshotLabel) screenshot · \(movementLabel) move · \(visibilityLabel) hide/show · Verify Legacy on your receiver" }
    static func blocksMovement(nativeMarked: Bool?, webFocused: Bool, webComposing: Bool?) -> Bool {
        if nativeMarked == true { return true }
        if webFocused { return nativeMarked != false || webComposing != false }
        return false
    }
    static func direction(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, markedText: Bool, modal: Bool) -> WindowDirection? {
        let exact = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard !markedText, !modal, exact == Self.modifiers else { return nil }
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }
}
