import Foundation

/// XCTest's runner and the application may have different preferences containers.
/// Seed only this disposable app's preview domain, once per test. No account data.
enum PreviewTestConfiguration {
    private struct Seed: Decodable {
        let token: UUID
        let compact: Bool
        let speechFailure: Bool
    }
    static func apply(bundleID: String? = Bundle.main.bundleIdentifier, payload: String? = nil,
                      seedFile: String? = ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_SEED_FILE"]) {
        guard let bundleID, bundleID.hasPrefix("dev.naivee2000.captureshield.uitest."),
              let payload = payload ?? launchPayload(at: seedFile),
              let seed = try? JSONDecoder().decode(Seed.self, from: Data(payload.utf8)),
              let defaults = UserDefaults(suiteName: bundleID + ".preview") else { return }
        guard defaults.string(forKey: "UITestSeedToken") != seed.token.uuidString else { return }
        defaults.removePersistentDomain(forName: bundleID + ".preview")
        defaults.set("normal", forKey: "ChatSharingMode")
        defaults.set(90, forKey: "ChatZoomPercent")
        defaults.set(seed.compact ? "{{100, 100}, {640, 480}}" : "{{100, 100}, {980, 700}}", forKey: "ChatWindowFrame")
        defaults.set("synthetic.offline.audio", forKey: "SpeechSourceBundleID")
        defaults.set(seed.speechFailure, forKey: "PreviewSpeechFailure")
        defaults.set(seed.token.uuidString, forKey: "UITestSeedToken")
    }
    private static func launchPayload(at path: String?) -> String? {
        guard let path, path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 4097) <= 4096,
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
