import Foundation

struct AudioCaptureStop: Sendable {
    let samples: [Float]
    let terminationConfirmed: Bool
    let failure: SpeechFailure?
    static let empty = Self(samples: [], terminationConfirmed: true, failure: nil)
}

/// Native transport seam: tests exercise the same start/stop ownership without
/// granting capture permission or creating a real ScreenCaptureKit stream.
@MainActor protocol AudioStreamTransport: AnyObject {
    func start() async throws
    func stop() async throws
    func takeSamples() -> [Float]
}

@MainActor final class AudioCaptureLifecycle {
    typealias Factory = @MainActor (AudioSource, @escaping @Sendable (Int, Bool) -> Void) async throws -> any AudioStreamTransport
    @MainActor private final class Lease {
        var transport: (any AudioStreamTransport)?
        var start: Task<Void, any Error>?
        var stop: Task<AudioCaptureStop, Never>?
        var terminal = false
        var failure: SpeechFailure?
    }
    private var lease: Lease?
    private let factory: Factory
    var failed: ((Int) -> Void)?
    var terminationConfirmed: Bool { lease == nil }
    init(factory: @escaping Factory) { self.factory = factory }

    func start(source: AudioSource) async throws {
        guard lease == nil else {
            throw SpeechFailure(stage: .capture, code: 409, message: "The previous capture has not finished. Wait for recovery before recording again.")
        }
        let lease = Lease(); self.lease = lease
        let task = Task { @MainActor in
            try Task.checkCancellation()
            let transport = try await self.factory(source) { [weak self, weak lease] code, terminal in
                Task { @MainActor in
                    guard let self, let lease, self.lease === lease else { return }
                    lease.terminal = lease.terminal || terminal
                    lease.failure = SpeechFailure(stage: .capture, code: code, message: "Audio capture was interrupted. Recovered text needs review.")
                    self.failed?(code)
                }
            }
            // Keep ownership even if cancellation arrived while constructing it.
            lease.transport = transport
            try Task.checkCancellation()
            try await transport.start()
            try Task.checkCancellation()
        }
        lease.start = task
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func stop() async -> AudioCaptureStop {
        guard let lease else { return .empty }
        if let task = lease.stop { return await task.value }
        lease.start?.cancel()
        let task = Task { @MainActor in
            // A non-cooperative native start remains owned. Never start another
            // stream merely because the UI deadline or Task.cancel fired.
            _ = try? await lease.start?.value
            var failure = lease.failure
            if let transport = lease.transport, !lease.terminal {
                do { try await transport.stop(); lease.terminal = true }
                catch { failure = SpeechFailure(stage: .capture, code: (error as? SpeechFailure)?.code ?? (error as NSError).code,
                    message: "Stopping audio capture failed. Retry recovery; another recording is blocked until capture ends.") }
            }
            failure = failure ?? lease.failure
            let confirmed = lease.transport == nil || lease.terminal
            let samples = confirmed ? (lease.transport?.takeSamples() ?? []) : []
            if self.lease === lease, confirmed { self.lease = nil }
            lease.stop = nil
            return AudioCaptureStop(samples: samples, terminationConfirmed: confirmed, failure: failure)
        }
        lease.stop = task
        return await task.value
    }
}
