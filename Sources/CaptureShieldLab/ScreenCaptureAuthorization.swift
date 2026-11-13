import Foundation

@MainActor enum ScreenCaptureAuthorization {
    static func ensure(defaults: UserDefaults, permission: any ScreenCapturePermissionChecking) throws {
        if permission.preflight() { return }
        if !defaults.bool(forKey: "ScreenshotPermissionRequested") {
            defaults.set(true, forKey: "ScreenshotPermissionRequested")
            _ = permission.request()
        }
        guard permission.preflight() else {
            throw SpeechFailure(stage: .permission, code: 1,
                message: "Allow CaptureShieldLab in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch. CaptureProbe has a separate permission.")
        }
    }
}
