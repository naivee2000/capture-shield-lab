import AppKit
import WebKit
import CaptureCore

/// Keep capture eligibility separate from visual compositing. Content and all
/// of its ancestors stay at full alpha; only a single backdrop paints at 80%.
@MainActor enum ChatAppearance {
    static func background(_ mode: ChatSharingMode) -> NSColor {
        NSColor(srgbRed: 16 / 255, green: 16 / 255, blue: 16 / 255, alpha: mode.backgroundOpacity)
    }

    static func apply(to window: NSWindow, mode: ChatSharingMode) {
        window.alphaValue = 1
        window.isOpaque = mode == .normal
        window.backgroundColor = background(mode)
        window.titlebarAppearsTransparent = true
        // A second translucent backdrop on the content view would compound alpha.
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// WebKit on macOS still paints an opaque document base even when both CSS
/// and the public underPageBackgroundColor are clear. This appearance-only
/// compatibility hook is NOT public API. Keep it isolated and capability-gated;
/// it does not change any capture permission or system privacy indicator.
@MainActor enum WebBackgroundCompatibility {
    static func setTransparent(_ enabled: Bool, in webView: WKWebView) -> Bool {
        let setter = NSSelectorFromString("_setDrawsBackground:")
        guard webView.responds(to: setter), webView.responds(to: NSSelectorFromString("_drawsBackground")) else { return false }
        // KVC's setter lookup includes _set<Key>:. The selector check above
        // prevents undefined-key access when WebKit removes the property.
        webView.setValue(!enabled, forKey: "drawsBackground")
        webView.underPageBackgroundColor = enabled ? .clear : nil
        return true
    }
}

/// Receives only presentation eligibility, never page text or editor contents.
@MainActor final class WebAppearanceBridge: NSObject, WKScriptMessageHandler {
    static let name = "captureShieldAppearance"
    private weak var webView: WKWebView?
    private let preview: Bool
    var unavailable: (() -> Void)?
    init(webView: WKWebView, preview: Bool) {
        self.webView = webView; self.preview = preview
        super.init()
        webView.configuration.userContentController.add(self, contentWorld: ChatPageAdapter.world, name: Self.name)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView, message.webView === webView, message.frameInfo.isMainFrame,
              let enabled = message.body as? Bool else { return }
        let url = message.frameInfo.request.url
        let allowed = preview ? url?.absoluteString == "about:blank" :
            (url?.scheme == "https" && url?.host == "chatgpt.com" && url == webView.url)
        if !WebBackgroundCompatibility.setTransparent(enabled && allowed, in: webView), enabled && allowed { unavailable?() }
    }
}
