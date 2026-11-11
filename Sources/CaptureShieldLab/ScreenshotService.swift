import AppKit
import ScreenCaptureKit

@MainActor final class ScreenshotService {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    static func pointerDisplay() -> CGDirectDisplayID? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    }
    func capture(displayID: CGDirectDisplayID?) async throws -> CGImage {
        guard let displayID else { throw ImageInputError.message("No display is available.") }
        if !CGPreflightScreenCaptureAccess() {
            if !defaults.bool(forKey: "ScreenshotPermissionRequested") {
                defaults.set(true, forKey: "ScreenshotPermissionRequested")
                _ = CGRequestScreenCaptureAccess()
            }
            guard CGPreflightScreenCaptureAccess() else {
                throw ImageInputError.message("Allow CaptureShieldLab in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch. CaptureProbe has a separate permission.")
            }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let own = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw ImageInputError.message("The selected display or this application's capture identity is unavailable. Try again.")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [own], exceptingWindows: [])
        let config = SCScreenshotConfiguration()
        config.showsCursor = false; config.dynamicRange = .sdr; config.fileURL = nil
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        guard config.width > 0, config.height > 0, config.width <= 16384, config.height <= 16384,
              config.width * config.height <= 64_000_000 else { throw ImageInputError.message("Display image is too large to capture safely.") }
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        guard let image = output.sdrImage else { throw ImageInputError.message("No screenshot was returned. Nothing was added.") }
        return image
    }
}
