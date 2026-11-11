import Testing
import Foundation
import CoreGraphics
@testable import CaptureCore

struct ChatPolicyTests {
    @Test func repeatedHidePreservesEveryPendingPopup() {
        let hidden = ChatInteraction.pendingRestore(previous: [], visible: [1, 2])
        #expect(ChatInteraction.pendingRestore(previous: hidden, visible: []) == [1, 2])
        #expect(ChatInteraction.pendingRestore(previous: hidden, visible: [1, 3]) == [1, 2, 3])
    }
    @Test func pasteKeepsUnicodeTextButNeverFileOrImageRepresentations() {
        #expect(ChatInteraction.pasteText("你好 🌍", representations: ["public.utf8-plain-text", "public.html"]) == "你好 🌍")
        for type in ["public.png", "public.tiff", "public.jpeg", "public.file-url", "com.adobe.pdf"] {
            #expect(ChatInteraction.pasteText("image or file fallback", representations: [type, "public.utf8-plain-text"]) == nil)
        }
        #expect(ChatInteraction.pasteText(nil, representations: ["public.html"]) == nil)
    }
    @Test func recorderLaunchNeverOpensPersonalChat() throws {
        #expect(try LaunchMode.parse([]) == .chat)
        #expect(try LaunchMode.parse(["--chat-preview"]) == .chatPreview)
        #expect(throws: (any Error).self) { try LaunchMode.parse(["--chat-preview", "--session", "/tmp/synthetic"]) }
        #expect(try LaunchMode.parse(["--lab"]) == .lab(session: nil, web: false))
        #expect(try LaunchMode.parse(["--session", "/tmp/synthetic"]) == .lab(session: "/tmp/synthetic", web: false))
        #expect(try LaunchMode.parse(["--session", "/tmp/synthetic", "--web-test"]) == .lab(session: "/tmp/synthetic", web: true))
        #expect(throws: (any Error).self) { try LaunchMode.parse(["--session"]) }
        #expect(throws: (any Error).self) { try LaunchMode.parse(["--unknown"]) }
    }
    @Test func navigationDoesNotLaunchExternalAppsOrReadLocalFiles() {
        for value in ["https://chatgpt.com/", "https://auth.openai.com/log-in", "https://example.org/article", "about:blank"] {
            #expect(WebNavigationPolicy.allows(URL(string: value)))
        }
        for value in ["http://chatgpt.com/", "file:///etc/passwd", "javascript:alert(1)", "mailto:a@example.com", "x-apple.systempreferences:com.apple.preference", "https://user:password@example.org/", "data:text/html,hello"] {
            #expect(!WebNavigationPolicy.allows(URL(string: value)))
        }
        #expect(!WebNavigationPolicy.allows(nil))
    }
    @Test func disconnectedDisplayRestoresWindowInsideCurrentDisplay() {
        let visible = CGRect(x: 0, y: 40, width: 1280, height: 740)
        let restored = WindowPlacement.restore(CGRect(x: 3000, y: 200, width: 1800, height: 1200), screens: [visible])
        #expect(visible.contains(restored))
        #expect(restored.width >= 640 && restored.height >= 480)
        let invalid = CGRect(x: CGFloat.nan, y: 0, width: 900, height: 700)
        #expect(visible.contains(WindowPlacement.restore(invalid, screens: [visible])))
    }
    @Test func negativeOriginDisplayAndVisibleSavedPositionArePreserved() {
        let screens = [CGRect(x: 0, y: 40, width: 1440, height: 860), CGRect(x: -1600, y: 0, width: 1600, height: 1000)]
        let saved = CGRect(x: -1500, y: 200, width: 900, height: 700)
        #expect(WindowPlacement.restore(saved, screens: screens) == saved)
        #expect(screens[0].contains(WindowPlacement.restore(nil, screens: screens)))
    }
}
