import AppKit
import ScreenCaptureKit
import CaptureCore

@MainActor protocol ScreenshotBackend {
    var engine: ScreenshotEngine { get }
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage
}

@MainActor protocol ScreenCapturePermissionChecking {
    func preflight() -> Bool
    func request() -> Bool
}

@MainActor struct SystemScreenCapturePermission: ScreenCapturePermissionChecking {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
}

struct ScreenshotError: LocalizedError {
    let failure: CaptureFailure
    let message: String
    var errorDescription: String? { message }
}

/// Both APIs receive the same display identity, exclusion and pixel limits.
@MainActor private struct ScreenshotRequest {
    let filter: SCContentFilter
    let width: Int
    let height: Int
    init(displayID: CGDirectDisplayID) async throws {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        catch { throw ScreenshotError(failure: CaptureFailure(stage: .content, code: (error as NSError).code), message: "Could not read displays. Check screen recording permission.") }
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let own = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw ScreenshotError(failure: CaptureFailure(stage: .display, code: 1), message: "The selected display or this application's capture identity is unavailable.")
        }
        filter = SCContentFilter(display: display, excludingApplications: [own], exceptingWindows: [])
        width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 64_000_000 else {
            throw ScreenshotError(failure: CaptureFailure(stage: .dimensions, code: 1), message: "Display image is too large to capture safely.")
        }
    }
}

@available(macOS 26.0, *)
@MainActor struct ModernScreenshotBackend: ScreenshotBackend {
    let engine = ScreenshotEngine.modern
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        let request = try await ScreenshotRequest(displayID: displayID)
        let config = SCScreenshotConfiguration()
        config.showsCursor = false; config.dynamicRange = .sdr; config.fileURL = nil
        config.width = request.width; config.height = request.height
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: request.filter, configuration: config)
        guard let image = output.sdrImage else {
            throw ScreenshotError(failure: CaptureFailure(stage: .capture, code: 1), message: "No screenshot was returned. Nothing was added.")
        }
        return image
    }
}

@MainActor struct CompatibleScreenshotBackend: ScreenshotBackend {
    let engine = ScreenshotEngine.compatible
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        let request = try await ScreenshotRequest(displayID: displayID)
        let config = Self.configuration(width: request.width, height: request.height)
        return try await SCScreenshotManager.captureImage(contentFilter: request.filter, configuration: config)
    }
    static func configuration(width: Int, height: Int) -> SCStreamConfiguration {
        let config = IndependentCaptureConfiguration.make(width: width, height: height)
        config.captureDynamicRange = .SDR
        return config
    }
}

@MainActor final class ScreenshotService {
    private let defaults: UserDefaults
    private let permission: any ScreenCapturePermissionChecking
    private let backendFactory: @MainActor (ScreenshotEngine) -> any ScreenshotBackend
    private let os: OperatingSystemVersion
    private(set) var lastFailure: CaptureFailure?
    init(defaults: UserDefaults = .standard,
         permission: any ScreenCapturePermissionChecking = SystemScreenCapturePermission(),
         os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
         backendFactory: @escaping @MainActor (ScreenshotEngine) -> any ScreenshotBackend = ScreenshotService.makeBackend) {
        self.defaults = defaults; self.permission = permission; self.os = os; self.backendFactory = backendFactory
    }
    static func makeBackend(_ engine: ScreenshotEngine) -> any ScreenshotBackend {
        if engine == .modern, #available(macOS 26.0, *) { return ModernScreenshotBackend() }
        return CompatibleScreenshotBackend()
    }
    static func pointerDisplay() -> CGDirectDisplayID? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    }
    var permissionGranted: Bool { permission.preflight() }
    func capture(displayID: CGDirectDisplayID?, mode: ScreenshotMode = .auto) async throws -> CGImage {
        lastFailure = nil
        do {
            try Task.checkCancellation()
            guard let displayID else { throw ScreenshotError(failure: CaptureFailure(stage: .display, code: 0), message: "No display is available.") }
            do { try ScreenCaptureAuthorization.ensure(defaults: defaults, permission: permission) }
            catch { throw ScreenshotError(failure: CaptureFailure(stage: .permission, code: 1), message: error.localizedDescription) }
            let backend = backendFactory(SystemCompatibility.screenshotEngine(os: os, mode: mode))
            let image = try await backend.capture(displayID: displayID)
            try Task.checkCancellation()
            return image
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            let failure = (error as? ScreenshotError)?.failure ?? CaptureFailure(stage: .capture, code: (error as NSError).code)
            lastFailure = failure
            throw ScreenshotError(failure: failure, message: (error as? ScreenshotError)?.message ?? "Screenshot failed. Open Compatibility… to check permission or manually select Compatible. Nothing was uploaded.")
        }
    }
}
