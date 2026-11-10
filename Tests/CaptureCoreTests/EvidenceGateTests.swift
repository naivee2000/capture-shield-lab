import Testing
import Foundation
import CoreGraphics
@testable import CaptureCore

struct EvidenceGateTests {
    @Test func delayedBaselineIsRejectedEvenWithNewSequence() {
        #expect(!EvidenceGate.acceptsFrame(presentation: 9.9, notBefore: 10, sequence: 100, after: 99))
        #expect(EvidenceGate.acceptsFrame(presentation: 10.1, notBefore: 10, sequence: 100, after: 99))
        #expect(!EvidenceGate.acceptsFrame(presentation: 10.1, notBefore: 10, sequence: 99, after: 99))
        #expect(!EvidenceGate.acceptsFrame(presentation: .nan, notBefore: 10, sequence: 100, after: 99))
    }
    @Test func displayReorderingPreservesSelectedDisplayAndRemovalRejectsIt() {
        #expect(EvidenceGate.displayIndex(id: 42, currentIDs: [9, 42]) == 1)
        #expect(EvidenceGate.displayIndex(id: 42, currentIDs: [42, 9]) == 0)
        #expect(EvidenceGate.displayIndex(id: 42, currentIDs: [9]) == nil)
    }
    @Test func lifecycleInterruptionSurvivesLaterConfiguration() {
        var validity = RunValidity()
        #expect(validity.mayContinue)
        validity.interrupt("sleep")
        #expect(!validity.canConfigure(rendererHealthy: true))
        #expect(!validity.mayContinue)
        #expect(validity.failure == "sleep")
    }
    @Test func staleOrDeadLabCannotSupplyPassingEvidence() {
        let now = Date(timeIntervalSince1970: 100)
        let frame = CGRect(x: 60, y: 80, width: 640, height: 440)
        var state = LabState(revision: 2, mode: .protectedMask, visible: true, ready: true,
                             windowNumber: 1, frame: frame, error: nil)
        state.heartbeat = now
        #expect(EvidenceGate.liveState(state, revision: 2, mode: .protectedMask, frame: frame, processAlive: true, now: now))
        #expect(!EvidenceGate.liveState(state, revision: 2, mode: .protectedMask, frame: frame, processAlive: false, now: now))
        #expect(!EvidenceGate.liveState(state, revision: 2, mode: .protectedMask, frame: frame, processAlive: true, now: now.addingTimeInterval(3)))
        #expect(!EvidenceGate.liveState(state, revision: 3, mode: .protectedMask, frame: frame, processAlive: true, now: now))
    }
}
