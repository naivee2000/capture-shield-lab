import Foundation

/// A bounded, content-free report. Never accept arbitrary strings from a page.
public struct PageCompatibility: Sendable, Equatable {
    public enum Layout: String, Sendable { case classic, navigationRail = "navigation-rail", unknown }
    public enum Sidebar: String, Sendable { case expanded, collapsed, unavailable }
    public enum Reason: String, Sendable {
        case ready, unchecked, authentication
        case unsupportedPage = "unsupported-page", unrecognizedLayout = "unrecognized-layout"
        case opaqueSurface = "opaque-page-surface", stale, unavailable
    }
    public var layout: Layout = .unknown
    public var sidebar: Sidebar = .unavailable
    public var reason: Reason = .unchecked
    public var eligible = false
    public var surfaces = 0
    public var decorations = 0
    public var opaque = 0
    public init() {}
    public init?(metadata: [String: Any]) {
        guard let layout = Layout(rawValue: metadata["profile"] as? String ?? ""),
              let sidebar = Sidebar(rawValue: metadata["sidebar"] as? String ?? ""),
              let reason = Reason(rawValue: metadata["reason"] as? String ?? ""),
              let eligible = metadata["eligible"] as? Bool,
              let surfaces = metadata["surfaces"] as? Int, (0...100).contains(surfaces),
              let decorations = metadata["decorations"] as? Int, (0...100).contains(decorations),
              let opaque = metadata["opaque"] as? Int, (0...100).contains(opaque) else { return nil }
        self.layout = layout; self.sidebar = sidebar; self.reason = reason; self.eligible = eligible
        self.surfaces = surfaces; self.decorations = decorations; self.opaque = opaque
    }
    public var text: String {
        "Page layout: \(layout.rawValue); sidebar: \(sidebar.rawValue)\nPage check: \(reason.rawValue); surfaces: \(surfaces); decorative layers: \(decorations); remaining painted layers: \(opaque)\nPage check is structural; desktop transparency and receiver hiding require separate verification."
    }
}
