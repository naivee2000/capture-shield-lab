import WebKit
import CaptureCore

@MainActor enum AttachmentPageBridge {
    enum Observation: String { case pending, uploading, visible, failed, stale }
    private static let contextScript = #"""
    (() => {
      const editors=[...document.querySelectorAll('[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt')];
      const visible=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return !e.closest('[hidden],[inert],[aria-hidden="true"]')&&r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';};
      if(editors.filter(visible).length!==1||[...document.querySelectorAll('input[type="password"],input[type="email"]')].some(visible))return null;
      window.captureShieldAttachmentDocument??="__DOCUMENT_ID__";
      return location.href+'\n'+window.captureShieldAttachmentDocument;
    })()
    """#
    static func context(in webView: WKWebView, preview: Bool) async -> String? {
        guard AttachmentPolicy.allows(webView.url, preview: preview) else { return nil }
        return (try? await webView.evaluateJavaScript(contextScript.replacingOccurrences(of: "__DOCUMENT_ID__", with: UUID().uuidString), in: nil, contentWorld: ChatPageAdapter.world)) as? String
    }
    static func identity(in webView: WKWebView, preview: Bool) async -> String? {
        guard AttachmentPolicy.allows(webView.url, preview: preview) else { return nil }
        return (try? await webView.evaluateJavaScript("window.captureShieldAttachmentDocument ? location.href+'\\n'+window.captureShieldAttachmentDocument : null", in: nil, contentWorld: ChatPageAdapter.world)) as? String
    }
    /// Opt-in development diagnostic: control structure only, no values or page text.
    static func controlDiagnostics(in webView: WKWebView, preview: Bool) async -> String {
        guard AttachmentPolicy.allows(webView.url, preview: preview) else { return "Unsupported page" }
        return (try? await webView.evaluateJavaScript(#"""
        (()=>{
          const editors=[...document.querySelectorAll('[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt')];
          const editor=editors[0], scope=(editor?.closest('form')||editor?.closest('[data-composer-body]'));
          const ancestors=[];for(let e=editor?.parentElement;e&&ancestors.length<7;e=e.parentElement)ancestors.push({tag:e.tagName,id:e.id,role:e.getAttribute('role'),composerBody:e.hasAttribute('data-composer-body')});
          return JSON.stringify({editors:editors.length,scope:scope?.tagName||null,ancestors,
            inputs:[...document.querySelectorAll('input[type="file"]')].map(e=>({accept:e.accept,disabled:e.disabled,inScope:!!scope?.contains(e),form:!!e.form,sameForm:!!editor?.closest('form')&&e.form===editor.closest('form')})),
            trigger:[...document.querySelectorAll('button')].filter(e=>e.id==='composer-plus-btn'||/^(Add files|Add photos|添加文件|添加照片)/.test(e.getAttribute('aria-label')||'')).map(e=>({id:e.id,label:e.getAttribute('aria-label'),expanded:e.getAttribute('aria-expanded'),controls:e.getAttribute('aria-controls')}))});
        })()
        """#, in: nil, contentWorld: ChatPageAdapter.world)) as? String ?? "Control inspection unavailable"
    }
    // The bridge retains DOM references, never composer text or network credentials.
    // Generic inputs need composer/form association or a synchronous click from a
    // recognized attachment action. Merely appearing elsewhere is never association.
    static func request(in webView: WKWebView, preview: Bool) async -> Bool {
        guard await context(in: webView, preview: preview) != nil else { return false }
        let script = "const captureShieldAttachmentPreview=\(preview);\n" + #"""
        (()=>{
          window.captureShieldAttachment?.cancel();
          const editor=[...document.querySelectorAll('[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt')].find(e=>e.getBoundingClientRect().height>0);
          const scope=(editor?.closest('form')||editor?.closest('[data-composer-body]'))||(captureShieldAttachmentPreview?document.body:null);
          if(!scope)return false;
          const visible=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return !e.closest('[hidden],[inert],[aria-hidden="true"]')&&r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';};
          const files=()=>[...document.querySelectorAll('input[type="file"]')];
          const associated=new WeakSet(), images=new Map([...scope.querySelectorAll('img')].map(e=>[e,e.getAttribute('src')]));
          const initialAlerts=new Set(scope.querySelectorAll('[role="alert"]'));
          const initialPopups=new Set(scope.querySelectorAll('button[aria-haspopup],[role="button"][aria-haspopup]'));
          const backgroundThumbnails=new Map();
          const state={editor,scope,href:location.href,clicked:false,opened:false,menuClicked:false,delivered:false,filename:null};
          const events=new AbortController();state.cancel=()=>events.abort();
          const acceptsImage=e=>!e.accept||/^(\*|\*\/\*)$/.test(e.accept.trim())||/image\/|\.png|\.jpe?g/i.test(e.accept);
          const inComposer=e=>scope.contains(e)||(scope instanceof HTMLFormElement&&e.form===scope);
          const imageInput=e=>!e.disabled&&acceptsImage(e)&&(associated.has(e)||(inComposer(e)&&(state.opened||!!e.accept)));
          const label=e=>{const aria=e.getAttribute('aria-label');if(aria)return aria.trim();const copy=e.cloneNode(true);copy.querySelectorAll('kbd,[aria-hidden="true"]').forEach(n=>n.remove());return (copy.textContent||'').replace(/\s+/g,' ').trim();};
          const attachmentButton=e=>e&&scope.contains(e)&&(e.id==='composer-plus-btn'||/^(Add photos & files|Add photos and files|Add files and more|Add files|Attach files|Attach|添加照片和文件|添加照片与文件|添加文件等内容|添加文件等|添加文件|上传文件)$/.test(label(e)));
          const menuLabel=e=>/^(Add photos & files|Add photos and files|Upload from computer|Upload files|添加照片和文件|添加照片与文件|从计算机上传|上传文件)(?:\s*(?:Upload from computer|从计算机上传))?$/.test(label(e));
          const menuRoot=()=>{const id=state.trigger?.getAttribute('aria-controls');return id?document.getElementById(id):null;};
          const attachmentMenu=e=>e&&e!==state.trigger&&state.opened&&!!menuRoot()&&menuRoot().contains(e)&&menuLabel(e);
          document.addEventListener('click',e=>{
            const button=e.target.closest?.('button');const isTrigger=button===state.trigger||(!state.trigger&&attachmentButton(button));
            if(isTrigger)state.trigger=button;
            if(isTrigger||attachmentMenu(e.target.closest?.('button,[role="menuitem"]'))){
              state.opened=true;state.inAttachmentAction=true;queueMicrotask(()=>state.inAttachmentAction=false);
            }
            if(e.target instanceof HTMLInputElement&&e.target.type==='file'){
              if(state.inAttachmentAction&&acceptsImage(e.target))associated.add(e.target);
              if(imageInput(e.target)){state.input=e.target;state.clicked=true;state.pickerAuthorized=true;}
            }
          },{capture:true,signal:events.signal});
          document.addEventListener('change',e=>{if(e.target===state.input&&state.delivered&&[...e.target.files].some(f=>f.name===state.filename))state.fileChanged=true;},{capture:true,signal:events.signal});
          state.permitChooser=()=>{const permitted=state.pickerAuthorized&&state.input?.isConnected&&imageInput(state.input);state.pickerAuthorized=false;return !!permitted;};
          state.advance=()=>{
            if(!editor.isConnected||location.href!==state.href)return false;
            if(state.clicked)return true;
            if(!state.opened){
              const buttons=[...scope.querySelectorAll('button')].filter(e=>visible(e)&&!e.disabled&&attachmentButton(e));
              if(buttons.length>1)return false;
              if(buttons.length===1){state.opened=true;state.trigger=buttons[0];buttons[0].click();return true;}
            }
            if(!state.menuClicked){
              const items=[...(menuRoot()?.querySelectorAll('button,[role="menuitem"]')||[])].filter(e=>visible(e)&&!e.disabled&&e.getAttribute('aria-disabled')!=='true'&&!e.querySelector('button,[role="menuitem"]')&&attachmentMenu(e));
              if(items.length===1){state.menuClicked=true;items[0].click();return true;}
              // Some popup triggers use pointerdown instead of click. Try once, only
              // when this recognized trigger still explicitly reports closed.
              if(!state.pointerAttempted&&state.trigger?.getAttribute('aria-expanded')==='false'){
                state.pointerAttempted=true;
                for(const type of ['pointerdown','pointerup'])state.trigger.dispatchEvent(new PointerEvent(type,{bubbles:true,cancelable:true,pointerId:1,pointerType:'mouse',isPrimary:true,button:0,buttons:type==='pointerdown'?1:0}));
                return true;
              }
            }
            const eligible=files().filter(imageInput);
            // The current site has multiple specialized image controls plus one
            // generic file input in the same chat form. Prefer that unique generic
            // control only after the recognized attachment trigger was activated.
            const generic=state.trigger&&state.opened&&scope instanceof HTMLFormElement
              ? eligible.filter(e=>e.form===scope&&(!e.accept||/^(\*|\*\/\*)$/.test(e.accept.trim()))) : [];
            const selected=generic.length===1?generic[0]:eligible.length===1?eligible[0]:null;
            if(selected){state.clicked=true;state.input=selected;selected.click();return true;}
            return false;
          };
          state.observe=()=>{
            if(!editor.isConnected||location.href!==state.href)return 'stale';
            if(!state.delivered||!state.fileChanged)return 'pending';
            const alerts=[...scope.querySelectorAll('[role="alert"]')].filter(e=>!initialAlerts.has(e)&&visible(e));
            if(alerts.some(e=>/fail|error|unable|limit|失败|错误|无法|限制/i.test(e.textContent||'')))return 'failed';
            const associatedPreview=e=>{
              const known=e.closest('[data-testid="file-thumbnail"],[data-testid="attachment-preview"],[data-testid="composer-file"]');
              const card=known||e.parentElement;
              if(!card)return false;
              const named=e.getAttribute('alt')===state.filename||(known&&(known.textContent||'').includes(state.filename))||
                [...card.querySelectorAll('[title],[aria-label]')].some(n=>n.getAttribute('title')===state.filename||n.getAttribute('aria-label')===state.filename);
              const removable=[...card.querySelectorAll('button[aria-label]')].some(b=>visible(b)&&/^(Remove file|Remove image|Remove attachment|删除文件|移除文件|删除图片|移除图片|删除附件|移除附件)$/.test(b.getAttribute('aria-label')||''));
              return named&&removable;
            };
            const added=[...scope.querySelectorAll('img')].filter(e=>(!images.has(e)||images.get(e)!==e.getAttribute('src'))&&visible(e)&&e.complete&&e.naturalWidth>0&&associatedPreview(e));
            // Current ChatGPT uses a filename-labelled popup thumbnail; Remove
            // lives inside its menu and is not permanently visible. Match only
            // the newly delivered filename, never arbitrary decorative images.
            const popupPreview=[...scope.querySelectorAll('button[aria-haspopup],[role="button"][aria-haspopup]')].some(card=>{
              if(initialPopups.has(card)||!visible(card)||card.getAttribute('aria-haspopup')==='false')return false;
              const named=card.getAttribute('aria-label')===state.filename||card.getAttribute('title')===state.filename||
                (card.getAttribute('aria-labelledby')||'').split(/\s+/).some(id=>document.getElementById(id)?.textContent?.trim()===state.filename);
              if(!named)return false;
              if([...card.querySelectorAll('img')].some(e=>visible(e)&&e.complete&&e.naturalWidth>0))return true;
              return [card,...card.querySelectorAll('*')].some(e=>{
                if(!visible(e))return false;
                const match=getComputedStyle(e).backgroundImage.match(/^url\(["']?(blob:[^"')]+|data:image\/[^"')]+)["']?\)$/);
                if(!match)return false;
                const url=match[1];
                if(!backgroundThumbnails.has(url)){const image=new Image();image.src=url;backgroundThumbnails.set(url,image);}
                const image=backgroundThumbnails.get(url);return image.complete&&image.naturalWidth>0;
              });
            });
            if(!added.length&&!popupPreview)return 'pending';
            if([...scope.querySelectorAll('[role="progressbar"],[aria-busy="true"]')].some(visible))return 'uploading';
            return 'visible';
          };
          window.captureShieldAttachment=state;
          return state.advance();
        })()
        """#
        return (try? await webView.evaluateJavaScript(script, in: nil, contentWorld: ChatPageAdapter.world)) as? Bool ?? false
    }
    static func permitsChooser(in webView: WKWebView) async -> Bool {
        (try? await webView.evaluateJavaScript("window.captureShieldAttachment?.permitChooser() ?? false", in: nil, contentWorld: ChatPageAdapter.world)) as? Bool ?? false
    }
    static func advance(in webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript("window.captureShieldAttachment?.advance() ?? false", in: nil, contentWorld: ChatPageAdapter.world)
    }
    static func didDeliver(in webView: WKWebView, filename: String) async {
        // JSON encoding avoids interpolating a file path into JavaScript source.
        guard let data = try? JSONSerialization.data(withJSONObject: [filename]), let literal = String(data: data, encoding: .utf8) else { return }
        _ = try? await webView.evaluateJavaScript("if(window.captureShieldAttachment){window.captureShieldAttachment.delivered=true;window.captureShieldAttachment.filename=\(literal)[0]}", in: nil, contentWorld: ChatPageAdapter.world)
    }
    static func observe(in webView: WKWebView) async -> Observation {
        let value = (try? await webView.evaluateJavaScript("window.captureShieldAttachment?.observe() ?? 'stale'", in: nil, contentWorld: ChatPageAdapter.world)) as? String
        return Observation(rawValue: value ?? "stale") ?? .stale
    }
    static func cancel(in webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript("window.captureShieldAttachment?.cancel(); delete window.captureShieldAttachment", in: nil, contentWorld: ChatPageAdapter.world)
    }
}
