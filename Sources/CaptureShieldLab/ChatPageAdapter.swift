import Foundation
import WebKit
import CaptureCore

@MainActor enum ChatPageAdapter {
    static let world = WKContentWorld.world(name: "CaptureShieldPresentation")

    static func disableInputSuggestions(in defaults: UserDefaults = .standard, persist: Bool = true) {
        // App-domain defaults consumed by WebKit's macOS TextChecker, not global OS preferences.
        // Set before creating WebViews; availability still requires testing on each WebKit version.
        let keys = ["WebAutomaticSpellingCorrectionEnabled", "WebContinuousSpellCheckingEnabled",
                    "WebGrammarCheckingEnabled", "WebAutomaticTextReplacementEnabled",
                    "WebAutomaticQuoteSubstitutionEnabled", "WebAutomaticDashSubstitutionEnabled",
                    "NSAutomaticSpellingCorrectionEnabled", "NSAutomaticTextCompletionEnabled"]
        if persist { keys.forEach { defaults.set(false, forKey: $0) } }
        else { defaults.register(defaults: Dictionary(uniqueKeysWithValues: keys.map { ($0, false) })) }
    }

    static func install(in configuration: WKWebViewConfiguration, preview: Bool = false, mode: ChatSharingMode = .normal) {
        let source = script(preview: preview, mode: mode)
        let controller = configuration.userContentController
        guard !controller.userScripts.contains(where: { $0.source == source }) else { return }
        let others = controller.userScripts.filter { !$0.source.hasPrefix("const captureShieldPreview =") }
        controller.removeAllUserScripts(); others.forEach(controller.addUserScript)
        configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: world))
    }

    static func applyMode(_ mode: ChatSharingMode, in webView: WKWebView) async {
        let reply = try? await webView.evaluateJavaScript("(()=>{const a=window.captureShieldPresentation;return a?{eligible:a.setMode('\(mode.rawValue)'),documentID:a.identity}:null;})()", in: nil, contentWorld: world)
        guard let reply = reply as? [String: Any], let token = reply["documentID"] as? String,
              let eligible = reply["eligible"] as? Bool, await isCurrent(token, in: webView) else { return }
        _ = WebBackgroundCompatibility.setTransparent(eligible, in: webView)
    }
    static func identity(in webView: WKWebView) async -> String? {
        (try? await webView.evaluateJavaScript("window.captureShieldPresentation?.identity ?? null", in: nil, contentWorld: world)) as? String
    }
    static func isCurrent(_ token: String, in webView: WKWebView) async -> Bool { await identity(in: webView) == token }

    enum SidebarResult: String {
        case expanded, collapsed, unavailable, timeout, stale
        case notReady = "not-ready"
        var succeeded: Bool { self == .expanded || self == .collapsed }
    }
    static func toggleSidebar(in webView: WKWebView) async -> SidebarResult {
        let url = webView.url
        guard let token = await identity(in: webView) else { return .notReady }
        let result = try? await webView.callAsyncJavaScript("return await (window.captureShieldPresentation?.toggleSidebar() ?? 'not-ready');",
            arguments: [:], in: nil, contentWorld: world)
        guard webView.url == url, await isCurrent(token, in: webView) else { return .stale }
        return SidebarResult(rawValue: result as? String ?? "") ?? .unavailable
    }
    static func check(in webView: WKWebView) async -> PageCompatibility {
        let url = webView.url
        let result = try? await webView.evaluateJavaScript("window.captureShieldPresentation?.check() ?? null", in: nil, contentWorld: world)
        guard webView.url == url else { var value = PageCompatibility(); value.reason = .stale; return value }
        guard let result = result as? [String: Any], let value = PageCompatibility(metadata: result),
              result["version"] as? String == PageLayoutRules.version, let token = result["documentID"] as? String else {
            var value = PageCompatibility(); value.reason = .unavailable; return value
        }
        guard await isCurrent(token, in: webView) else { var value = PageCompatibility(); value.reason = .stale; return value }
        return value
    }

    static func script(preview: Bool = false, mode: ChatSharingMode = .normal) -> String {
        "const captureShieldPreview = \(preview ? "true" : "false"); const captureShieldInitialMode = '\(mode.rawValue)';\n" + #"""
        (() => {
          if (window.captureShieldPresentation?.version === '0.6.7.1') return;
          window.captureShieldPresentation?.dispose?.();
          const allowed = () => captureShieldPreview
            ? location.href === 'about:blank'
            : location.protocol === 'https:' && location.hostname === 'chatgpt.com'
              && !/^\/(auth|login|signup|settings)(\/|$)/.test(location.pathname);
          const rendered = element => {
            if (!element || element.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
            if (typeof element.checkVisibility === 'function' && !element.checkVisibility({opacityProperty:true,visibilityProperty:true,contentVisibilityAuto:true})) return false;
            const style = getComputedStyle(element), rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && rect.width > 0 && rect.height > 0;
          };
          const visible = element => {
            if (!rendered(element)) return false;
            const rect = element.getBoundingClientRect();
            return rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight;
          };
          const editorSelector = '[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt';
          /* LAYOUT_RULES */
          let userChoseSidebar = false;
          let scheduled = false, oldTheme = null, themed = false, mode = captureShieldInitialMode, lastReport = '';
          let textareaHeights = new Map();
          const set = (node, name, value) => { if (node.getAttribute(name) !== value) node.setAttribute(name, value); };
          const isAuthentication = () => [...document.querySelectorAll('input[type="password"],input[type="email"],input[autocomplete="current-password"]')].some(visible);
          const theme = enabled => {
            const root = document.documentElement;
            if (enabled) {
              if (!themed) oldTheme = { data:root.getAttribute('data-theme'), dark:root.classList.contains('dark'), light:root.classList.contains('light') };
              themed = true;
              set(root,'data-cs-chat-page','');
              set(root,'data-cs-mode',mode);
              if (root.hasAttribute('data-theme')) set(root,'data-theme','dark');
              else { if(root.classList.contains('light')) root.classList.remove('light'); if(!root.classList.contains('dark')) root.classList.add('dark'); }
            } else if (themed) {
              root.removeAttribute('data-cs-chat-page');
              root.removeAttribute('data-cs-mode');
              for (const [node, original] of textareaHeights) {
                if (original.value) node.style.setProperty('height', original.value, original.priority);
                else node.style.removeProperty('height');
              }
              textareaHeights.clear();
              if (oldTheme.data !== null) set(root,'data-theme',oldTheme.data);
              root.classList.toggle('dark',oldTheme.dark); root.classList.toggle('light',oldTheme.light);
              themed = false;
            }
          };
          const publish = () => {
            const value=report(), signature=JSON.stringify(value);
            if(signature!==lastReport) { lastReport=signature; window.webkit?.messageHandlers?.captureShieldAppearance?.postMessage(value); }
          };
          const update = () => {
            scheduled = false;
            if (disposed) return;
            if (!allowed() || isAuthentication()) { theme(false); syncMarkers(new Map()); publish(); return; }
            const editors = [...document.querySelectorAll(editorSelector)].filter(rendered);
            if (editors.length !== 1 && !knownShell()) { theme(false); syncMarkers(new Map()); publish(); return; }
            const editor = editors.length === 1 ? editors[0] : null;
            if (!document.getElementById('capture-shield-compact')) {
              const style = document.createElement('style'); style.id = 'capture-shield-compact';
              style.textContent = `
                html[data-cs-chat-page] { color-scheme:dark; background:transparent!important; }
                html[data-cs-chat-page] body, html[data-cs-chat-page] [data-cs-surface] { background-color:transparent!important; background-image:none!important; }
                html[data-cs-chat-page] [data-cs-backdrop-before]::before, html[data-cs-chat-page] [data-cs-backdrop-after]::after { background-color:transparent!important; background-image:none!important; }
                html[data-cs-chat-page] [data-cs-editor] { min-height:24px!important; max-height:var(--cs-editor-max,160px)!important; overflow-y:auto!important; }
                html[data-cs-chat-page] [data-cs-editor-wrap] { margin-block:2px!important; }
                html[data-cs-chat-page] [data-cs-composer-body] { padding-block:4px!important; }
                html[data-cs-chat-page] [data-cs-thumbnail] { box-sizing:border-box!important; width:var(--cs-thumb-size,64px)!important; min-width:var(--cs-thumb-size,64px)!important; max-width:var(--cs-thumb-size,64px)!important; height:var(--cs-thumb-size,64px)!important; min-height:0!important; max-height:var(--cs-thumb-size,64px)!important; flex-shrink:0!important; background-size:contain!important; background-repeat:no-repeat!important; background-position:center!important; }
                html[data-cs-chat-page] [data-cs-thumbnail] img, html[data-cs-chat-page] [data-cs-thumb-paint] { max-width:100%!important; max-height:100%!important; width:100%!important; height:100%!important; object-fit:contain; background-size:contain!important; background-repeat:no-repeat!important; background-position:center!important; }
              `;
              document.head.appendChild(style);
            }
            theme(true);
            applyBackground(editor);
            initialCollapse();
            publish();
            if (!editor) return;
            const scope = editor.closest('form') || editor.closest('[data-composer-body]');
            let thumbnailCount = 0;
            if (scope) {
              const cards = scope.querySelectorAll('[data-testid="file-thumbnail"],[data-testid="attachment-preview"],[data-testid="composer-file"],button[aria-haspopup],[role="button"][aria-haspopup]');
              for (const card of cards) {
                const known = card.matches('[data-testid="file-thumbnail"],[data-testid="attachment-preview"],[data-testid="composer-file"]');
                const labels = [card.getAttribute('aria-label'),card.getAttribute('title'),...(card.getAttribute('aria-labelledby')||'').split(/\s+/).map(id=>document.getElementById(id)?.textContent?.trim())];
                const namedImage = labels.some(value => /\.(png|jpe?g|webp|gif|heic)$/i.test(value || ''));
                const image = card.querySelector('img');
                const paint = [card,...card.querySelectorAll('div,span')].find(node => /url\(["']?(blob:|data:image\/)/.test(getComputedStyle(node).backgroundImage));
                if (!(known || namedImage) || !(image || paint) || !rendered(card)) continue;
                set(card,'data-cs-thumbnail',''); if (paint && paint !== card) set(paint,'data-cs-thumb-paint','');
                thumbnailCount++;
              }
            }
            document.documentElement.style.setProperty('--cs-thumb-size', innerHeight < 540 ? '56px' : '64px');
            const editorMax = Math.min(160, Math.max(56, Math.floor(innerHeight * (thumbnailCount ? 0.20 : 0.25))));
            document.documentElement.style.setProperty('--cs-editor-max', `${editorMax}px`);
            set(editor,'data-cs-editor','');
            set(editor,'spellcheck','false'); set(editor,'autocorrect','off');
            set(editor,'autocapitalize','off'); set(editor,'writingsuggestions','false');
            const wrap = editor.closest('[data-rich-text-layout]');
            if (wrap) set(wrap,'data-cs-editor-wrap','');
            const body = editor.closest('[data-composer-body]');
            if (body) set(body,'data-cs-composer-body','');
            if (editor instanceof HTMLTextAreaElement) {
              if (!textareaHeights.has(editor)) textareaHeights.set(editor, {value:editor.style.getPropertyValue('height'),priority:editor.style.getPropertyPriority('height')});
              // Geometry only: never copy, inspect or log the user's draft.
              const top = editor.scrollTop;
              editor.style.setProperty('height','auto','important');
              editor.style.setProperty('height',`${Math.min(editorMax, Math.max(24, editor.scrollHeight))}px`,'important');
              editor.scrollTop = top;
              for (const node of textareaHeights.keys()) if (!node.isConnected) textareaHeights.delete(node);
            }
          };
          // Coalesce relevant mutations. Ignore our own style writes so streamed
          // messages and textarea sizing do not create a self-sustaining loop.
          const schedule = () => { if (!disposed && !scheduled) { scheduled = true; setTimeout(update, 50); } };
          const events = new AbortController();
          document.addEventListener('click', event => {
            if (!event.isTrusted || !(event.target instanceof Element)) return;
            const button=event.target.closest('button');
            if(button && (button.matches(sidebarSelector) || button===railHome())) userChoseSidebar=true;
          }, {capture:true,signal:events.signal});
          window.captureShieldPresentation = {
            version:adapterVersion,
            identity:documentID,
            setMode(value) { mode = value === 'legacy' ? 'legacy' : 'normal'; update(); return themed; },
            check() { return report(); },
            async toggleSidebar() {
              if (!allowed() || isAuthentication()) return 'unavailable';
              userChoseSidebar=true;
              if(sidebarOperation?.automatic) await sidebarOperation.promise;
              if(disposed) return 'stale';
              return startSidebar(sidebar().state==='expanded'?'collapsed':'expanded');
            },
            dispose() {
              disposed=true; events.abort(); observer.disconnect(); resizeObserver.disconnect();
              theme(false); syncMarkers(new Map()); document.getElementById('capture-shield-compact')?.remove();
            }
          };
          addEventListener('resize', schedule, {signal:events.signal});
          addEventListener('popstate', schedule, {signal:events.signal});
          addEventListener('pageshow', schedule, {signal:events.signal});
          document.addEventListener('input', schedule, {capture:true,signal:events.signal});
          document.addEventListener('load', schedule, {capture:true,signal:events.signal});
          const rootStyle = () => [...document.documentElement.style].filter(k=>!k.startsWith('--cs-')).sort()
            .map(k=>[k,document.documentElement.style.getPropertyValue(k),document.documentElement.style.getPropertyPriority(k)]).join('|');
          let previousRootStyle=rootStyle();
          const observer=new MutationObserver(records=>{
            if(records.some(r=>{
              if(r.type!=='attributes'||r.attributeName!=='style') return true;
              if(r.target===document.documentElement) { const next=rootStyle(),changed=next!==previousRootStyle;previousRootStyle=next;return changed; }
              return r.target===document.body || ownedMarkers.has(r.target);
            })) schedule();
          });
          observer.observe(document.documentElement, {
            childList:true, subtree:true, attributes:true,
            attributeFilter:['contenteditable','spellcheck','autocorrect','writingsuggestions','data-theme','aria-expanded','aria-hidden','hidden','inert','data-state','class','style']
          });
          const resizeObserver=new ResizeObserver(schedule); resizeObserver.observe(document.documentElement);
          update(); setTimeout(schedule,260);
        })();
        """#.replacingOccurrences(of: "/* LAYOUT_RULES */", with: PageLayoutRules.script)
    }
}
