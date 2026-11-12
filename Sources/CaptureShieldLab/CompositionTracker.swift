import WebKit

/// Only composition state crosses the bridge. Never read marked text or editor values.
@MainActor final class CompositionTracker: NSObject, WKScriptMessageHandler {
    private(set) var composing: Bool?
    private(set) var document: String?
    private(set) var generation = 0
    func reset() { generation += 1; composing = nil; document = nil }
    func synchronize(in webView: WKWebView, generation expected: Int? = nil) async {
        let current = expected ?? generation
        guard current == generation else { return }
        guard let body = try? await webView.evaluateJavaScript("window.captureShieldCompositionState ? {document:window.captureShieldCompositionState.document,composing:window.captureShieldCompositionState.composing} : null", in: nil, contentWorld: ChatPageAdapter.world) as? [String: Any],
              let id = body["document"] as? String, let value = body["composing"] as? Bool else { return }
        guard current == generation else { return }
        document = id; composing = value
    }
    func install(in configuration: WKWebViewConfiguration) {
        // Popup configurations may carry scripts from the opener, but get a new handler.
        let content = configuration.userContentController
        content.removeScriptMessageHandler(forName: "captureShieldComposition", contentWorld: ChatPageAdapter.world)
        content.add(self, contentWorld: ChatPageAdapter.world, name: "captureShieldComposition")
        if !content.userScripts.contains(where: { $0.source == Self.script }) {
            content.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ChatPageAdapter.world))
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              body.count == 2, let value = body["composing"] as? Bool, let id = body["document"] as? String else { return }
        guard document == id else { return }
        composing = value
    }
    static let script = #"""
    (()=>{
      if(window.captureShieldCompositionState)return;
      const state={composing:false,document:String(Date.now())+Math.random()};
      window.captureShieldCompositionState=state;
      const post=()=>window.webkit.messageHandlers.captureShieldComposition.postMessage({composing:state.composing,document:state.document});
      document.addEventListener('compositionstart',()=>{state.composing=true;post()},true);
      document.addEventListener('compositionend',()=>{state.composing=false;post()},true);
      document.addEventListener('keydown',e=>{if(e.isComposing){state.composing=true;post()}},true);
      document.addEventListener('DOMContentLoaded',post,{once:true});
      // Blur does not force false: an outstanding composition remains conservative.
      post();
    })()
    """#
}
