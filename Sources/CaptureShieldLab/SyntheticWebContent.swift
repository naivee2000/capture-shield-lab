import AppKit
import WebKit

/// Offline, disposable renderer control. Never accesses the chat website data store.
@MainActor final class SyntheticWebContent: NSObject, WKNavigationDelegate {
    let view: ChatWebView
    private(set) var ready = false
    private(set) var error: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = ChatWebView(frame: .zero, configuration: config)
        super.init()
        view.navigationDelegate = self
        view.loadHTMLString(Self.html, baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed() }
    private func failed() { ready = false; error = "Synthetic WebView did not load or its process stopped. Rerun the test." }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    private static let html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'none'">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    :root { color-scheme: dark; font: 16px -apple-system, sans-serif; background: #102437; color: white }
    body { padding: 16px; margin: 0 } h2 { font-size: 18px; margin: 0 0 12px; color: #66e6cd }
    textarea { box-sizing: border-box; width: 100%; min-height: 80px; font: 16px monospace; padding: 10px; background: #18364d; color: white; border: 1px solid #54859c }
    button { margin: 12px 0; padding: 8px 14px } #reply { min-height: 70px; white-space: pre-wrap }
    </style></head><body><h2>WEBVIEW CONTROL — SYNTHETIC ONLY</h2>
    <textarea aria-label="Synthetic web editor">Type here / 在此输入 — Marker 8642</textarea>
    <button id="send">Stream synthetic reply</button><div id="reply" aria-live="polite">Ready. No network, account or real conversation data.</div>
    <p>Scroll control: 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ</p>
    <p>Background must stay complete on the receiver.</p><p>A black rectangle is a failure.</p>
    <script>
    document.querySelector('#send').onclick = () => {
      const button = document.querySelector('#send'), reply = document.querySelector('#reply');
      button.disabled = true; reply.textContent = '';
      const text = 'Synthetic streaming response. 中文输入与复制测试。 Other windows must remain visible and update normally.';
      let index = 0; const timer = setInterval(() => {
        reply.textContent += text[index++];
        if (index === text.length) { clearInterval(timer); button.disabled = false; }
      }, 65);
    };
    </script></body></html>
    """
}
