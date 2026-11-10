import Testing
import Foundation
@testable import CaptureCore

struct AnalysisTests {
    func checker(_ size: Int = 32) -> PixelFrame {
        var bytes: [UInt8] = []
        for y in 0..<size { for x in 0..<size {
            let value: UInt8 = ((x / 4 + y / 4) % 2 == 0) ? 60 : 190
            bytes += [value, value, value, 255]
        } }
        return PixelFrame(width: size, height: size, rgba: bytes)
    }
    @Test func testUnchangedBackgroundMatches() throws {
        #expect(try CaptureAnalysis.compare(checker(), to: checker()).matchesBackground)
    }
    @Test func testBlackRectangleIsNotHidden() throws {
        let black = PixelFrame(width: 32, height: 32, rgba: Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 255), count: 1024).flatMap { $0 })
        #expect(!(try CaptureAnalysis.compare(black, to: checker()).matchesBackground))
    }
    @Test func testThinBorderFailsBackgroundMatch() throws {
        let original = checker()
        var bytes = original.rgba
        for x in 0..<32 { bytes[x * 4] = 255; bytes[x * 4 + 1] = 0 }
        #expect(!(try CaptureAnalysis.compare(PixelFrame(width: 32, height: 32, rgba: bytes), to: original).matchesBackground))
    }
    @Test func testMalformedAndMismatchedFramesRejected() {
        #expect(throws: (any Error).self) { try CaptureAnalysis.compare(PixelFrame(width: 0, height: 0, rgba: []), to: checker()) }
        #expect(throws: (any Error).self) { try CaptureAnalysis.compare(checker(16), to: checker()) }
    }
    @Test func testBaselineMustBeTexturedAndNonempty() {
        #expect(CaptureAnalysis.isUsefulBaseline(checker()))
        #expect(!(CaptureAnalysis.isUsefulBaseline(PixelFrame(width: 32, height: 32, rgba: Array(repeating: 0, count: 4096)))))
        #expect(!(CaptureAnalysis.isUsefulBaseline(PixelFrame(width: 0, height: 0, rgba: []))))
    }
    @Test func testRetinaCoordinatesWithNegativeDisplayOrigin() throws {
        let rect = try CaptureAnalysis.pixelRect(window: CGRect(x: -1400, y: 120, width: 300, height: 200), display: CGRect(x: -1600, y: 0, width: 1600, height: 1000), pixelWidth: 3200, pixelHeight: 2000)
        #expect(rect == CGRect(x: 400, y: 240, width: 600, height: 400))
    }
    @Test func testPartialOffscreenRegionRejected() {
        #expect(throws: (any Error).self) { try CaptureAnalysis.pixelRect(window: CGRect(x: -1, y: 10, width: 300, height: 200), display: CGRect(x: 0, y: 0, width: 1600, height: 1000), pixelWidth: 3200, pixelHeight: 2000) }
    }
    @Test func testPassingRequiresControlsFramesAndHumanConfirmation() throws {
        let same = try CaptureAnalysis.compare(checker(), to: checker())
        #expect(Outcome.candidate(frames: [same], controlsVisible: true, localConfirmed: true) == .pass)
        #expect(Outcome.candidate(frames: [same], controlsVisible: true, localConfirmed: nil) == .notTested)
        #expect(Outcome.candidate(frames: [same], controlsVisible: false, localConfirmed: true) == .notTested)
        #expect(Outcome.candidate(frames: [], controlsVisible: true, localConfirmed: true) == .notTested)
        #expect(Outcome.candidate(frames: [same], controlsVisible: true, localConfirmed: false) == .fail)
    }
    @Test func testOneLeakedFrameFailsWholeCandidate() throws {
        let same = try CaptureAnalysis.compare(checker(), to: checker())
        let leak = Comparison(mismatchFraction: 0.1, meanError: 30)
        #expect(Outcome.candidate(frames: [same, leak, same], controlsVisible: true, localConfirmed: true) == .fail)
    }
}
