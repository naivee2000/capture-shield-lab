import Testing
import AppKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor struct ImagePreviewTests {
    @Test func keypadEnterCanBeRepresentedByItsAppKitCharacter() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .numericPad,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{3}",
            charactersIgnoringModifiers: "\u{3}", isARepeat: false, keyCode: 0)!
        #expect(ImageReturnGate.key(for: event) == 76)
    }
    @Test(arguments: [UInt16(36), UInt16(76)]) func enterIsOneShotUntilReleaseAndCannotSendDuringHandoff(key: UInt16) {
        var gate = ImageReturnGate()
        func down(_ preview: Bool, _ pending: Bool, _ repeatKey: Bool = false) -> ImageReturnGate.Action {
            gate.action(type: .keyDown, key: key, modifiers: [], repeatKey: repeatKey,
                preview: preview, pending: pending, canConfirm: true, marked: false, modal: false)
        }
        #expect(down(true, false) == .confirm)
        #expect(down(false, true, true) == .consume)
        #expect(down(false, false, true) == .consume)
        #expect(gate.action(type: .keyUp, key: key, modifiers: [], repeatKey: false, preview: false,
            pending: true, canConfirm: true, marked: false, modal: false) == .consume)
        #expect(down(false, true) == .consume)
        _ = gate.action(type: .keyUp, key: key, modifiers: [], repeatKey: false, preview: false,
            pending: false, canConfirm: true, marked: false, modal: false)
        #expect(down(false, false) == .pass)
        #expect(down(true, false) == .confirm) // A second image/retry can be confirmed.
    }
    @Test func previewEnterRespectsModifiersCompositionModalsAndCropDrag() {
        for (flags, marked, modal) in [(NSEvent.ModifierFlags.shift, false, false), ([], true, false), ([], false, true)] {
            var gate = ImageReturnGate()
            #expect(gate.action(type: .keyDown, key: 36, modifiers: flags, repeatKey: false,
                preview: true, pending: false, canConfirm: true, marked: marked, modal: modal) == .pass)
        }
        var gate = ImageReturnGate()
        #expect(gate.action(type: .keyDown, key: 36, modifiers: [], repeatKey: false,
            preview: true, pending: false, canConfirm: false, marked: false, modal: false) == .consume)
        let preview = ImagePreview(image: ChatPreview.sampleImage())
        var calls = 0
        preview.add = { _ in calls += 1 }
        preview.addImage(); preview.addImage()
        #expect(calls == 1)
        preview.busy(false); preview.addImage()
        #expect(calls == 2)
    }
    @Test func gripResizeAnchorsTopLeftAndClampsToDisplay() {
        let screen = CGRect(x: -1600, y: 40, width: 1600, height: 1000)
        let start = CGRect(x: -1400, y: 300, width: 800, height: 600)
        let grown = WindowPlacement.resizedFromTopLeft(start, delta: CGSize(width: 80, height: 40), visibleFrame: screen)
        #expect(grown.minX == start.minX && grown.maxY == start.maxY)
        #expect(grown.size == CGSize(width: 880, height: 640))
        let minimum = WindowPlacement.resizedFromTopLeft(start, delta: CGSize(width: -1000, height: -1000), visibleFrame: screen)
        #expect(minimum.size == CGSize(width: 640, height: 480))
        let maximum = WindowPlacement.resizedFromTopLeft(start, delta: CGSize(width: 9000, height: 9000), visibleFrame: screen)
        #expect(screen.contains(maximum) && maximum.minX == start.minX && maximum.maxY == start.maxY)
    }
    @Test func resizingPreviewPreservesTheSelectedImagePixels() throws {
        let canvas = CropCanvas(image: ChatPreview.sampleImage())
        canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let rect = canvas.imageRect
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.2)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.6)))
        let before = canvas.croppedImage
        #expect(before.width < canvas.image.width)
        canvas.setFrameSize(NSSize(width: 400, height: 280))
        #expect(canvas.croppedImage.width == before.width)
        #expect(canvas.croppedImage.height == before.height)
        #expect(canvas.croppedImage.dataProvider?.data == before.dataProvider?.data)
        canvas.reset()
        #expect(canvas.croppedImage.width == canvas.image.width)
    }
}
