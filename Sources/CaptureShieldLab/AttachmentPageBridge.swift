import WebKit
import CaptureCore

@MainActor enum AttachmentPageBridge {
    private static let contextScript = #"""
    (() => {
      const editor = document.querySelector('[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt');
      const visible = e => { const r=e.getBoundingClientRect(),s=getComputedStyle(e); return !e.closest('[hidden],[inert],[aria-hidden="true"]') && r.width>0 && r.height>0 && s.display!=='none' && s.visibility!=='hidden'; };
      if (!editor || !visible(editor) || [...document.querySelectorAll('input[type="password"],input[type="email"]')].some(visible)) return null;
      window.captureShieldAttachmentDocument ??= "__DOCUMENT_ID__";
      return location.href + '\n' + window.captureShieldAttachmentDocument;
    })()
    """#
    static func context(in webView: WKWebView, preview: Bool) async -> String? {
        guard AttachmentPolicy.allows(webView.url, preview: preview) else { return nil }
        return (try? await webView.evaluateJavaScript(contextScript.replacingOccurrences(of: "__DOCUMENT_ID__", with: UUID().uuidString), in: nil, contentWorld: ChatPageAdapter.world)) as? String
    }
    static func request(in webView: WKWebView, preview: Bool) async -> Bool {
        guard AttachmentPolicy.allows(webView.url, preview: preview) else { return false }
        return (try? await webView.evaluateJavaScript(#"""
        (() => {
          const inputs=[...document.querySelectorAll('input[type="file"]')].filter(e=>!e.disabled && /image\/|\.png|\.jpe?g/i.test(e.accept));
          const editor=document.querySelector('[data-composer-markdown],#prompt-textarea,#mobile-composer-prompt');
          const form=editor?.closest('form');
          const local=form ? inputs.filter(e=>form.contains(e)) : [];
          const selected=local.length===1 ? local[0] : inputs.length===1 ? inputs[0] : null;
          if (!selected) return false;
          selected.click(); return true;
        })()
        """#, in: nil, contentWorld: ChatPageAdapter.world)) as? Bool ?? false
    }
}
