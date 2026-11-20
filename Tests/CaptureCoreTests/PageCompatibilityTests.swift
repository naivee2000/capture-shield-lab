import Foundation
import Testing
@testable import CaptureCore

struct PageCompatibilityTests {
    @Test func diagnosticsAreBoundedAndExcludeArbitraryPageData() throws {
        var metadata: [String: Any] = ["profile": "navigation-rail", "sidebar": "expanded", "reason": "ready",
            "eligible": true, "surfaces": 5, "decorations": 1, "opaque": 0, "chat": "SECRET DRAFT", "url": "PRIVATE URL"]
        let report = try #require(PageCompatibility(metadata: metadata))
        #expect(report.layout == .navigationRail && report.opaque == 0)
        #expect(!report.text.contains("SECRET") && !report.text.contains("PRIVATE"))
        metadata["reason"] = "SECRET DRAFT"
        #expect(PageCompatibility(metadata: metadata) == nil)
        metadata["reason"] = "ready"; metadata["surfaces"] = -1
        #expect(PageCompatibility(metadata: metadata) == nil)
        metadata["surfaces"] = 101
        #expect(PageCompatibility(metadata: metadata) == nil)
    }
    @Test func webKitUpgradeNoticeIsIndependentOfOSBuild() throws {
        let name = "CaptureShield-WebKit-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(!SystemCompatibility.recordWebKitBuild("100", in: defaults))
        #expect(!SystemCompatibility.recordWebKitBuild("100", in: defaults))
        #expect(!SystemCompatibility.recordWebKitBuild("unknown", in: defaults))
        #expect(SystemCompatibility.recordWebKitBuild("101", in: defaults))
        #expect(!SystemCompatibility.recordWebKitBuild("101", in: defaults))
    }
}
