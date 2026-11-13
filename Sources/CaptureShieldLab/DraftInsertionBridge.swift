import AppKit
import WebKit

@MainActor enum DraftInsertionBridge {
    enum Outcome: String { case inserted, blocked, stale, unavailable, uncertain }
    static func append(_ text: String, token: String, context: String, owner: ChatWindow) async -> Outcome {
        guard owner.isMain, owner.window?.isVisible == true, owner.window?.isMiniaturized != true,
              owner.window?.attachedSheet == nil, NSApp.modalWindow == nil else { return .blocked }
        await owner.composition.synchronize(in: owner.webView)
        guard owner.composition.composing == false,
              (owner.window?.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true else { return .blocked }
        guard await AttachmentPageBridge.identity(in: owner.webView, preview: owner.preview) == context else { return .stale }
        guard owner.window?.isVisible == true, owner.window?.isMiniaturized != true, owner.window?.attachedSheet == nil else { return .blocked }
        do {
            let value = try await owner.webView.callAsyncJavaScript(script,
                arguments: ["text": text, "token": token, "context": context], in: nil, contentWorld: ChatPageAdapter.world)
            return (value as? String).flatMap(Outcome.init(rawValue:)) ?? .uncertain
        } catch { return .uncertain }
    }
    // Draft contents remain inside the page. Only an outcome crosses this bridge.
    // execCommand performs an editing operation with undo/input events; never set
    // innerHTML/textContent/value or synthesize Enter/submit/send clicks.
    static let script = #"""
    if(location.href+'\n'+window.captureShieldAttachmentDocument!==context)return 'stale';
    if(window.captureShieldCompositionState?.composing!==false)return 'blocked';
    const editors=[...document.querySelectorAll('[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt')].filter(e=>{
      const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&!e.closest('[hidden],[inert],[aria-hidden="true"]')&&s.display!=='none'&&s.visibility!=='hidden'&&!e.disabled&&!e.readOnly;
    });
    if(editors.length!==1)return 'unavailable';
    const states=window.captureShieldDraftInsertions??=new Map();
    if(states.has(token))return states.get(token);
    const editor=editors[0],read=()=>editor instanceof HTMLTextAreaElement?editor.value:(editor.textContent??'');
    const before=read();
    // innerText includes layout-generated terminal newlines in the live composer.
    // Compare text nodes, leaving existing paragraph/attachment structure intact.
    const addition=(before.length&&!/\s$/.test(before)?' ':'')+text;
    editor.focus({preventScroll:true});
    if(document.activeElement!==editor)return 'unavailable';
    if(editor instanceof HTMLTextAreaElement)editor.setSelectionRange(editor.value.length,editor.value.length);
    else{const r=document.createRange();r.selectNodeContents(editor);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r);}
    states.set(token,'uncertain');
    document.execCommand('insertText',false,addition);
    const after=read(),expected=before+addition;
    const comparable=s=>editor instanceof HTMLTextAreaElement?s:s.replace(/\u00a0/g,' ');
    const verified=comparable(after)===comparable(expected);
    const outcome=verified?'inserted':'uncertain';states.set(token,outcome);return outcome;
    """#
}
