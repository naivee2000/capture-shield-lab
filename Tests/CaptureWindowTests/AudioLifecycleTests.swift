import Foundation
import Testing
@testable import CaptureShieldLab

/// Continuations make native delay/failure ordering deterministic, without a
/// real capture stream, a permission grant, or arbitrary sleeps.
@MainActor final class SpeechTestGate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor final class SpeechTestDeadlines {
    private var waits: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in waits[id] = (duration, continuation) }
        } onCancel: {
            Task { @MainActor in self.waits.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
        }
    }
    func contains(_ duration: Duration) -> Bool { waits.values.contains { $0.0 == duration } }
    func fire(_ duration: Duration) {
        let ids = waits.filter { $0.value.0 == duration }.map(\.key)
        for id in ids { waits.removeValue(forKey: id)?.1.resume() }
    }
}

@MainActor private final class Transport: AudioStreamTransport {
    var starts = 0, stops = 0, takes = 0
    var startGate: SpeechTestGate?
    var stopGate: SpeechTestGate?
    var stopFails = false
    func start() async throws { starts += 1; await startGate?.wait() }
    func stop() async throws {
        stops += 1; await stopGate?.wait()
        if stopFails { throw SpeechFailure(stage: .capture, code: 91, message: "Synthetic stop failure") }
    }
    func takeSamples() -> [Float] { takes += 1; return [0.2] }
}

@MainActor @Suite(.serialized) struct AudioLifecycleTests {
    private let source = AudioSource(bundleID: "synthetic", name: "Fixture", pid: -1)
    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(5)) }
        throw SpeechFailure(stage: .capture, code: 408, message: "Fixture did not settle")
    }
    @Test func tenSessionsOwnExactlyOneStreamAtATime() async throws {
        var transports: [Transport] = []
        let lifecycle = AudioCaptureLifecycle { _, _ in let transport = Transport(); transports.append(transport); return transport }
        for _ in 0..<10 {
            try await lifecycle.start(source: source)
            #expect(!lifecycle.terminationConfirmed)
            do { try await lifecycle.start(source: source); Issue.record("Duplicate start must fail") }
            catch { #expect((error as? SpeechFailure)?.code == 409) }
            #expect(await lifecycle.stop().terminationConfirmed)
            #expect(lifecycle.terminationConfirmed)
        }
        #expect(transports.count == 10)
        #expect(transports.allSatisfy { $0.starts == 1 && $0.stops == 1 && $0.takes == 1 })
    }
    @Test func duplicateStopWaitsForTheSameNativeCompletion() async throws {
        let transport = Transport(), gate = SpeechTestGate(); transport.stopGate = gate
        let lifecycle = AudioCaptureLifecycle { _, _ in transport }
        try await lifecycle.start(source: source)
        let first = Task { await lifecycle.stop() }
        try await wait { gate.entered }
        var secondFinished = false
        let second = Task { let value = await lifecycle.stop(); secondFinished = true; return value }
        for _ in 0..<10 { await Task.yield() }
        #expect(!secondFinished && !lifecycle.terminationConfirmed)
        #expect(transport.stops == 1)
        gate.release()
        let firstResult = await first.value, secondResult = await second.value
        #expect(firstResult.terminationConfirmed && secondResult.terminationConfirmed)
        #expect(transport.takes == 1 && lifecycle.terminationConfirmed)
    }
    @Test func cancelledStartMustSettleBeforeStopAndAnotherStart() async throws {
        let transport = Transport(), gate = SpeechTestGate(); transport.startGate = gate
        let lifecycle = AudioCaptureLifecycle { _, _ in transport }
        let start = Task { try await lifecycle.start(source: source) }
        try await wait { gate.entered }
        start.cancel()
        let stop = Task { await lifecycle.stop() }
        for _ in 0..<10 { await Task.yield() }
        #expect(transport.stops == 0 && !lifecycle.terminationConfirmed)
        gate.release()
        _ = try? await start.value
        #expect(await stop.value.terminationConfirmed)
        #expect(transport.stops == 1)
    }
    @Test func failedStopRetainsTransportUntilExplicitRetry() async throws {
        let transport = Transport(); transport.stopFails = true
        let lifecycle = AudioCaptureLifecycle { _, _ in transport }
        try await lifecycle.start(source: source)
        let first = await lifecycle.stop()
        #expect(!first.terminationConfirmed && first.failure?.code == 91)
        #expect(transport.takes == 0 && !lifecycle.terminationConfirmed)
        transport.stopFails = false
        #expect(await lifecycle.stop().terminationConfirmed)
        #expect(transport.stops == 2 && transport.takes == 1)
    }
    @Test func staleNativeFailureCannotInterruptANewerStream() async throws {
        var callbacks: [@Sendable (Int, Bool) -> Void] = []
        let lifecycle = AudioCaptureLifecycle { _, failure in callbacks.append(failure); return Transport() }
        var failures: [Int] = []; lifecycle.failed = { failures.append($0) }
        try await lifecycle.start(source: source); _ = await lifecycle.stop()
        try await lifecycle.start(source: source)
        callbacks[0](98, true)
        for _ in 0..<10 { await Task.yield() }
        #expect(failures.isEmpty && !lifecycle.terminationConfirmed)
        callbacks[1](99, true)
        try await wait { failures == [99] }
        let result = await lifecycle.stop()
        #expect(result.terminationConfirmed && result.failure?.code == 99)
    }
}
