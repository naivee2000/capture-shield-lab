import AppKit

/// Window-local: retain consumed key presses until key-up, even if the preview
/// disappears before autorepeat ends. No default button on the chat window.
struct ImageReturnGate {
    enum Action { case pass, consume, confirm }
    private var held: Set<UInt16> = []
    static func key(for event: NSEvent) -> UInt16? {
        // Keep a physical key's identity stable if Fn changes while held.
        if event.keyCode == 36 || event.keyCode == 76 { return event.keyCode }
        // Fn-Return and text-service/automation events may represent Enter with
        // NSCarriageReturnCharacter/NSEnterCharacter and no hardware key code.
        switch event.charactersIgnoringModifiers {
        case "\u{3}": return 76
        case "\r": return 36
        default: return nil
        }
    }
    mutating func action(type: NSEvent.EventType, key: UInt16, modifiers: NSEvent.ModifierFlags,
                         repeatKey: Bool, preview: Bool, pending: Bool,
                         canConfirm: Bool, marked: Bool, modal: Bool) -> Action {
        guard key == 36 || key == 76 else { return .pass }
        if type == .keyUp { return held.remove(key) != nil ? .consume : .pass }
        guard type == .keyDown else { return .pass }
        if held.contains(key) {
            if repeatKey { return .consume }
            // A genuine new press proves the old key was released, even when
            // AppKit delivered that key-up to a chooser or another window.
            held.remove(key)
        }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard flags.isEmpty, !marked, !modal, preview || pending else { return .pass }
        held.insert(key)
        return preview && canConfirm && !pending && !repeatKey ? .confirm : .consume
    }
}
