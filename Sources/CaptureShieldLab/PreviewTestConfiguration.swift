import Foundation

/// XCTest's runner and the application may have different preferences containers.
/// Seed only this disposable app's preview domain, once per test. No account data.
enum PreviewTestConfiguration {
    private struct Seed: Decodable {
        let token: UUID
        let compact: Bool
        let speechFailure: Bool
    }
    static func normalizedArguments(_ arguments: [String], bundleID: String? = Bundle.main.bundleIdentifier) -> [String] {
        guard arguments.count == 3, arguments[0] == "--chat-preview", arguments[1] == "--ui-test-setup",
              arguments[2].utf8.count <= 8192, let bytes = Data(base64Encoded: arguments[2]), bytes.count <= 4096,
              let payload = String(data: bytes, encoding: .utf8), apply(bundleID: bundleID, payload: payload) else { return arguments }
        return ["--chat-preview"]
    }
    @discardableResult static func apply(bundleID: String? = Bundle.main.bundleIdentifier, payload: String?) -> Bool {
        guard let bundleID, bundleID.hasPrefix("dev.naivee2000.captureshield.uitest."),
              let payload,
              let seed = try? JSONDecoder().decode(Seed.self, from: Data(payload.utf8)),
              let defaults = UserDefaults(suiteName: bundleID + ".preview") else { return false }
        guard defaults.string(forKey: "UITestSeedToken") != seed.token.uuidString else { return true }
        defaults.removePersistentDomain(forName: bundleID + ".preview")
        defaults.set("normal", forKey: "ChatSharingMode")
        defaults.set(90, forKey: "ChatZoomPercent")
        defaults.set(seed.compact ? "{{100, 100}, {640, 480}}" : "{{100, 100}, {980, 700}}", forKey: "ChatWindowFrame")
        defaults.set("synthetic.offline.audio", forKey: "SpeechSourceBundleID")
        defaults.set(seed.speechFailure, forKey: "PreviewSpeechFailure")
        defaults.set(seed.token.uuidString, forKey: "UITestSeedToken")
        return true
    }
}
