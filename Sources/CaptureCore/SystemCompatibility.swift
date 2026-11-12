import Foundation
import Darwin

public enum ScreenshotMode: String, CaseIterable, Sendable {
    case auto, compatible
    public var title: String { self == .auto ? "Auto" : "Compatible" }
}

public enum ScreenshotEngine: String, Sendable {
    case modern, compatible
    public var title: String { self == .modern ? "Modern screenshot API" : "Compatible screenshot API" }
}

public enum SystemCompatibility {
    public static let minimumVersion = "15.6"
    public static func supports(_ os: OperatingSystemVersion) -> Bool {
        os.majorVersion > 15 || (os.majorVersion == 15 && os.minorVersion >= 6)
    }
    public static func screenshotEngine(os: OperatingSystemVersion, mode: ScreenshotMode) -> ScreenshotEngine {
        mode == .auto && os.majorVersion >= 26 ? .modern : .compatible
    }
    public static func versionString(_ os: OperatingSystemVersion) -> String {
        "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
    public static var osBuild: String {
        var count = 0
        guard sysctlbyname("kern.osversion", nil, &count, nil, 0) == 0, count > 1 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.osversion", &bytes, &count, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    /// Returns an upgrade notice once per changed build, never changes sharing preferences.
    public static func recordOSBuild(_ build: String, in defaults: UserDefaults) -> Bool {
        guard build != "unknown", !build.isEmpty else { return false }
        let previous = defaults.string(forKey: "LastSeenOSBuild")
        defaults.set(build, forKey: "LastSeenOSBuild")
        return previous != nil && previous != build
    }
}

public struct BuildIdentity: Sendable {
    public let version: String
    public let build: String
    public let commit: String
    public init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unbundled"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        commit = bundle.object(forInfoDictionaryKey: "CaptureShieldBuildCommit") as? String ?? "unknown"
    }
}

public enum CaptureFailureStage: String, Sendable { case display, permission, content, dimensions, capture }

/// Deliberately excludes error descriptions/userInfo, paths, URLs and page data.
public struct CaptureFailure: Equatable, Sendable {
    public let stage: CaptureFailureStage
    public let code: Int
    public init(stage: CaptureFailureStage, code: Int) { self.stage = stage; self.code = code }
}

public struct CompatibilitySummary: Sendable {
    public var osVersion: String
    public var osBuild: String
    public var app: BuildIdentity
    public var mode: ScreenshotMode
    public var engine: ScreenshotEngine
    public var permissionGranted: Bool
    public var failure: CaptureFailure?
    public init(os: OperatingSystemVersion, build: String, app: BuildIdentity = BuildIdentity(), mode: ScreenshotMode,
                permissionGranted: Bool, failure: CaptureFailure? = nil) {
        osVersion = SystemCompatibility.versionString(os); osBuild = build; self.app = app; self.mode = mode
        engine = SystemCompatibility.screenshotEngine(os: os, mode: mode)
        self.permissionGranted = permissionGranted; self.failure = failure
    }
    public var text: String {
        """
        CaptureShield \(app.version) (build \(app.build))
        Commit: \(app.commit)
        macOS: \(osVersion) (\(osBuild))
        Runtime minimum: macOS \(SystemCompatibility.minimumVersion), Apple Silicon
        Screenshot selection: \(mode.title)
        Screenshot implementation: \(engine.title)
        Screen Recording preflight: \(permissionGranted ? "allowed" : "not granted or stale; check System Settings")
        Last screenshot error: \(failure.map { "\($0.stage.rawValue), code \($0.code)" } ?? "none")
        OS-specific runtime tests: see the repository compatibility record.
        Receiver hiding: NOT VERIFIED by this diagnostic. Retest after OS/client updates.
        """
    }
}
