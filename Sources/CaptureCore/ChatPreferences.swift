import Foundation

public enum ChatSharingMode: String, CaseIterable, Sendable {
    case normal, legacy
    public var opacity: Double { self == .legacy ? 0.8 : 1 }
}

public struct ChatPreferences: Equatable, Sendable {
    public var mode: ChatSharingMode
    public var screenshotMode: ScreenshotMode
    public private(set) var zoomPercent: Int
    public init(mode: ChatSharingMode = .legacy, zoomPercent: Int = 90, screenshotMode: ScreenshotMode = .auto) {
        self.mode = mode; self.screenshotMode = screenshotMode
        self.zoomPercent = Int((Double(min(140, max(70, zoomPercent))) / 10).rounded()) * 10
    }
    public mutating func changeZoom(by steps: Int) {
        zoomPercent = min(140, max(70, zoomPercent + min(14, max(-14, steps)) * 10))
    }
    public mutating func resetZoom() { zoomPercent = 90 }
    public static func load(from defaults: UserDefaults) -> Self {
        Self(mode: defaults.string(forKey: "ChatSharingMode").flatMap(ChatSharingMode.init(rawValue:)) ?? .legacy,
             zoomPercent: defaults.object(forKey: "ChatZoomPercent") == nil ? 90 : defaults.integer(forKey: "ChatZoomPercent"),
             screenshotMode: defaults.string(forKey: "ScreenshotMode").flatMap(ScreenshotMode.init(rawValue:)) ?? .auto)
    }
    public func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: "ChatSharingMode")
        defaults.set(screenshotMode.rawValue, forKey: "ScreenshotMode")
        defaults.set(zoomPercent, forKey: "ChatZoomPercent")
    }
}
