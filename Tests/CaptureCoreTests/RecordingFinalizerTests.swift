import Foundation
import Testing
@testable import CaptureCore

@MainActor struct RecordingFinalizerTests {
    @Test func stopAndQuitAwaitTheSameFinalization() async throws {
        let finalizer = RecordingFinalizer()
        var calls = 0, firstDone = false, secondDone = false
        var release: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            await finalizer.finish {
                calls += 1
                await withCheckedContinuation { release = $0 }
            }
            firstDone = true
        }
        for _ in 0..<100 {
            if release != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let second = Task { @MainActor in
            await finalizer.finish { calls += 1 }
            secondDone = true
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!firstDone && !secondDone)
        release?.resume()
        await first.value; await second.value
        #expect(calls == 1 && firstDone && secondDone)
    }
    @Test func cancelledTimerCannotCancelFinalization() async {
        let finalizer = RecordingFinalizer()
        var wasCancelled = true
        let caller = Task { @MainActor in
            await finalizer.finish { wasCancelled = Task.isCancelled }
        }
        caller.cancel()
        await caller.value
        #expect(!wasCancelled)
    }
}
