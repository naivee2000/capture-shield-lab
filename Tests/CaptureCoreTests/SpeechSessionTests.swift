import Foundation
import Testing
@testable import CaptureCore

struct SpeechSessionTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CAPTURESHIELD_NATIVE_HOST"] == "1"))
    func nativeTestHostSurvivesStoppedRunLoop() async throws {
        CFRunLoopStop(CFRunLoopGetMain())
        try await Task.sleep(for: .milliseconds(20))
        MainActor.preconditionIsolated()
        #expect(ProcessInfo.processInfo.environment["CAPTURESHIELD_NATIVE_NEGATIVE"] != "1", "Deliberate native-host negative control")
    }
    @Test func pendingEditsAndUncertainDeliveryStayIndependent() {
        var buffer = SpeechTranscriptBuffer()
        buffer.append("First"); buffer.edit("Reviewed first")
        buffer.append("Second")
        #expect(buffer.text == "Reviewed first\n\nSecond")
        let old = buffer.delivery()
        buffer.edit("Newer edit")
        buffer.acknowledge(old, uncertain: false)
        #expect(buffer.text == "Newer edit")
        let current = buffer.delivery()
        buffer.acknowledge(current, uncertain: true)
        buffer.append("Next recording")
        buffer.acknowledge(current, uncertain: true)
        #expect(buffer.text == "Next recording" && buffer.uncertain.count == 1)
        buffer.discardUncertain(current.id)
        #expect(buffer.text == "Next recording" && buffer.uncertain.isEmpty)
    }
    @Test func requestsStayUnderOneMinuteAndCoverTwoMinutes() {
        let chunks = SpeechAudioPolicy.chunks(sampleCount: 16000 * 150)
        #expect(chunks.count == 3)
        #expect(chunks.last?.upperBound == 16000 * 120)
        #expect(chunks.allSatisfy { $0.count <= 16000 * 50 })
        #expect(chunks[0].upperBound - chunks[1].lowerBound == 16000)
        #expect(SpeechAudioPolicy.chunks(sampleCount: 0).isEmpty)
    }
    @Test func overlappingTimestampsDoNotDuplicateBoundaryWords() {
        let chunks = SpeechAudioPolicy.chunks(sampleCount: 16000 * 70)
        let merged = SpeechAudioPolicy.merge([
            [.init(text: "before", start: 49, duration: 0.2), .init(text: "crossing", start: 49.6, duration: 0.2)],
            [.init(text: "before", start: 0, duration: 0.2), .init(text: "crossing", start: 0.6, duration: 0.2), .init(text: "after", start: 2, duration: 0.2)]
        ], chunks: chunks, language: .english)
        #expect(merged == "before crossing after")
    }
    @Test func chineseDoesNotAcquireEnglishWordSpaces() {
        let text = SpeechAudioPolicy.merge([[.init(text: "你好", start: 0, duration: 0.2), .init(text: "世界", start: 0.3, duration: 0.2)]],
            chunks: [0..<16000], language: .chinese)
        #expect(text == "你好世界")
    }
    @Test func cancelledAndDuplicateOperationsCannotAdvanceNewSession() {
        var state = SpeechSessionState()
        let old = state.begin()!
        #expect(state.begin() == nil)
        state.reset()
        let current = state.begin()!
        let staleAccepted = state.transition(.recording, generation: old)
        #expect(!staleAccepted)
        let currentAccepted = state.transition(.recording, generation: current)
        #expect(currentAccepted)
        #expect(state.phase == .recording)
    }
}
