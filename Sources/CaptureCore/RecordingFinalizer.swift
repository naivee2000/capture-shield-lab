import Foundation

@MainActor public final class RecordingFinalizer {
    private var task: Task<Void, Never>?
    public init() {}
    public func finish(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        // Unstructured task owns finalization, independently of an auto-stop timer's cancellation.
        // Every caller (Stop, Quit, stream error) awaits this same operation.
        if task == nil { task = Task { await operation() } }
        await task?.value
    }
}
