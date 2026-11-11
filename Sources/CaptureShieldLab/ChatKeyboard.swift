import AppKit
import CaptureCore

enum ChatKeyboard {
    static func direction(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, markedText: Bool, modal: Bool) -> WindowDirection? {
        let exact = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard !markedText, !modal, exact == [.command, .option] else { return nil }
        switch keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: return nil
        }
    }
}
