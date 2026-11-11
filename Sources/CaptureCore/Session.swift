import Foundation
import CoreGraphics

public enum ProtectionMode: String, Codable, CaseIterable, Sendable {
    case ordinary, legacy, maskControl, protectedMask
    public var title: String {
        switch self {
        case .ordinary: "Ordinary"
        case .legacy: "Legacy sharing"
        case .maskControl: "Mask control"
        case .protectedMask: "Protected mask"
        }
    }
    public var usesMask: Bool { self == .maskControl || self == .protectedMask }
}

/// File-based IPC is confined to a fresh, mode-0700 temporary directory per probe.
/// Only synthetic test configuration and window geometry are exchanged, never typed text.
public struct LabCommand: Codable, Sendable {
    public var revision: Int
    public var mode: ProtectionMode
    public var visible: Bool
    public var frame: CGRect
    public var quit: Bool
    public init(revision: Int, mode: ProtectionMode, visible: Bool, frame: CGRect, quit: Bool = false) {
        self.revision = revision; self.mode = mode; self.visible = visible
        self.frame = frame; self.quit = quit
    }
}

public struct LabState: Codable, Sendable {
    public var heartbeat = Date()
    public var revision: Int
    public var mode: ProtectionMode
    public var visible: Bool
    public var ready: Bool
    public var windowNumber: Int
    public var frame: CGRect
    public var error: String?
    public init(revision: Int, mode: ProtectionMode, visible: Bool, ready: Bool,
                windowNumber: Int, frame: CGRect, error: String?) {
        self.revision = revision; self.mode = mode; self.visible = visible
        self.ready = ready; self.windowNumber = windowNumber; self.frame = frame; self.error = error
    }
}

public enum SessionIO {
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

public struct StageResult: Codable, Sendable {
    public var mode: ProtectionMode
    public var verdict: Verdict
    public var reason: String
    public var sampleCount: Int
    public var worstMismatch: Double?
    public var worstMeanError: Double?
    public var localConfirmed: Bool?
    public init(mode: ProtectionMode, verdict: Verdict, reason: String, sampleCount: Int = 0,
                worstMismatch: Double? = nil, worstMeanError: Double? = nil, localConfirmed: Bool? = nil) {
        self.mode = mode; self.verdict = verdict; self.reason = reason; self.sampleCount = sampleCount
        self.worstMismatch = worstMismatch; self.worstMeanError = worstMeanError; self.localConfirmed = localConfirmed
    }
}

public struct MeetingResult: Codable, Sendable {
    public var app: String
    public var verdict: Verdict = .notTested
    public var reason = "Requires three independent receiver trials with exact versions and whole-display sharing."
    public init(app: String) { self.app = app }
}

public struct RunReport: Codable, Sendable {
    public var schemaVersion = 2
    public var id: String
    public var createdAt = Date()
    public var os: String
    public var architecture = "arm64"
    public var appVersion = "0.3.0"
    public var surface: String? = "native-editor"
    public var captureMethod = "ScreenCaptureKit SCStream, full display, empty exclusion list"
    public var displayID: UInt32
    public var displayFrame: CGRect
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var testFrame: CGRect
    public var order: String
    public var stages: [StageResult] = []
    public var meetings = ["Zoom", "Google Meet (Chrome)", "Microsoft Teams"].map { MeetingResult(app: $0) }
    public var error: String?
    public init(id: String, os: String, displayID: UInt32, displayFrame: CGRect,
                pixelWidth: Int, pixelHeight: Int, testFrame: CGRect, order: String) {
        self.id = id; self.os = os; self.displayID = displayID; self.displayFrame = displayFrame
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.testFrame = testFrame; self.order = order
    }
}
