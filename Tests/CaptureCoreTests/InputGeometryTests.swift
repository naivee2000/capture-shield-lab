import Testing
import Foundation
import CoreGraphics
@testable import CaptureCore

struct InputGeometryTests {
    @Test func movementUsesLogicalPointsAndStopsAtTheDisplayEdge() {
        let display = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        let frame = CGRect(x: -1300, y: 100, width: 900, height: 700)
        #expect(WindowPlacement.moved(frame, direction: .up, visibleFrame: display).origin.y == 140)
        #expect(WindowPlacement.moved(frame, direction: .left, visibleFrame: display).origin.x == -1340)
        let edge = CGRect(x: -1440, y: 24, width: 900, height: 700)
        #expect(WindowPlacement.moved(edge, direction: .left, visibleFrame: display) == edge)
        #expect(WindowPlacement.moved(edge, direction: .down, visibleFrame: display) == edge)
        #expect(WindowPlacement.moved(frame, direction: .right, visibleFrame: display).size == frame.size)
    }
    @Test func cropMapsPreviewCoordinatesToRetinaPixels() {
        let shown = CGRect(x: 20, y: 40, width: 800, height: 450)
        let drag = CGRect(x: 220, y: 140, width: 400, height: 250)
        #expect(ImageGeometry.pixelCrop(selection: drag, imageRect: shown, pixels: CGSize(width: 3200, height: 1800)) == CGRect(x: 800, y: 400, width: 1600, height: 1000))
        #expect(ImageGeometry.pixelCrop(selection: CGRect(x: -20, y: 0, width: 100, height: 100), imageRect: shown, pixels: CGSize(width: 3200, height: 1800)) == CGRect(x: 0, y: 0, width: 240, height: 240))
        #expect(ImageGeometry.pixelCrop(selection: .zero, imageRect: shown, pixels: CGSize(width: 3200, height: 1800)) == nil)
    }
    @Test func attachmentsOnlyGoToTheChatOriginOutsideAuthentication() {
        #expect(AttachmentPolicy.allows(URL(string: "https://chatgpt.com/c/example")))
        for value in ["https://chatgpt.com.evil.test/", "http://chatgpt.com/", "https://chatgpt.com/auth/login", "https://chatgpt.com/%61uth/login", "https://chatgpt.com/settings", "https://user@chatgpt.com/"] {
            #expect(!AttachmentPolicy.allows(URL(string: value)))
        }
        #expect(!AttachmentPolicy.allows(URL(string: "about:blank")))
        #expect(AttachmentPolicy.allows(URL(string: "about:blank"), preview: true))
    }
    @Test func attachmentConsentIsSingleUseAndInvalidatedByNavigation() {
        var gate = AttachmentConsent()
        let result1 = gate.consume(document: "a")
        #expect(!result1)
        gate.arm(document: "a")
        let result2 = gate.consume(document: "b")
        #expect(!result2)
        let result3 = gate.consume(document: "a")
        #expect(!result3)
        gate.arm(document: "b")
        let result4 = gate.consume(document: "b")
        #expect(result4)
        let result5 = gate.consume(document: "b")
        #expect(!result5)
    }
}
