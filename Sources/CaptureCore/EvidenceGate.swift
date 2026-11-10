import Foundation
import CoreGraphics

public enum EvidenceGate {
    public static func acceptsFrame(presentation: Double, notBefore: Double, sequence: Int, after: Int) -> Bool {
        presentation.isFinite && notBefore.isFinite && presentation >= notBefore && sequence > after
    }
    public static func displayIndex(id: UInt32, currentIDs: [UInt32]) -> Int? { currentIDs.firstIndex(of: id) }
    public static func liveState(_ state: LabState, revision: Int, mode: ProtectionMode, frame: CGRect,
                                 processAlive: Bool, now: Date) -> Bool {
        let age = now.timeIntervalSince(state.heartbeat)
        return processAlive && age >= 0 && age < 2 && state.ready && state.error == nil
            && state.revision == revision && state.mode == mode && state.visible && state.frame == frame
    }
}

public struct RunValidity {
    public private(set) var failure: String?
    public init() {}
    public mutating func interrupt(_ reason: String) { if failure == nil { failure = reason } }
    public func canConfigure(rendererHealthy: Bool) -> Bool { mayContinue && rendererHealthy }
    public var mayContinue: Bool { failure == nil }
}
