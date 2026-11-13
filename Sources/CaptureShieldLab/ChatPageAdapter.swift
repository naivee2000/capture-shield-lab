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
        let eligible = (try? await webView.evaluateJavaScript("window.captureShieldPresentation?.setMode('\(mode.rawValue)') ?? false", in: nil, contentWorld: world)) as? Bool ?? false
        _ = WebBackgroundCompatibility.setTransparent(eligible, in: webView)
    }

    static func toggleSidebar(in webView: WKWebView) async -> Bool {
        (try? await webView.evaluateJavaScript("window.captureShieldPresentation?.toggleSidebar() ?? false",
            in: nil, contentWorld: world)) as? Bool ?? false
    }

    static func script(preview: Bool = false, mode: ChatSharingMode = .normal) -> String {
        "const captureShieldPreview = \(preview ? "true" : "false"); const captureShieldInitialMode = '\(mode.rawValue)';\n" + #"""
        (() => {
          if (window.captureShieldPresentation) return;
          const allowed = () => captureShieldPreview
            ? location.href === 'about:blank'
            : location.protocol === 'https:' && location.hostname === 'chatgpt.com'
              && !/^\/(auth|login|signup|settings)(\/|$)/.test(location.pathname);
          const rendered = element => {
            if (!element || element.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
            const style = getComputedStyle(element), rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && rect.width > 0 && rect.height > 0;
          };
          const visible = element => {
            if (!rendered(element)) return false;
            const rect = element.getBoundingClientRect();
            return rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight;
          };
          const editorSelector = '[data-composer-markdown][contenteditable="true"],#prompt-textarea[contenteditable="true"],textarea#prompt-textarea,textarea#mobile-composer-prompt';
          const sidebarSelector = 'button[aria-controls="app-shell-sidebar"],button[aria-controls="ds-sidebar"],button[aria-label="Close sidebar"],button[aria-label="Hide sidebar"],button[aria-label="Open sidebar"],button[aria-label="关闭边栏"],button[aria-label="隐藏边栏"],button[aria-label="打开边栏"]';
          const sidebarButton = () => {
            const buttons = [...document.querySelectorAll(sidebarSelector)].filter(e => visible(e) && !e.disabled);
            return buttons.find(e => /^(Close sidebar|Hide sidebar|关闭边栏|隐藏边栏)$/.test(e.getAttribute('aria-label') || '')) || buttons[0]
              // The site's collapsed opener can be transparent until hovered. Its explicit
              // target and collapsed ARIA state identify it without clicking unrelated controls.
              || [...document.querySelectorAll('button[aria-controls="app-shell-sidebar"][aria-expanded="false"],button[aria-controls="ds-sidebar"][aria-expanded="false"]')].find(e => !e.disabled);
          };
          let userChoseSidebar = false, sidebarAttempts = 0, lastSidebarAttempt = 0, lastSidebarButton = null;
          let scheduled = false, oldTheme = null, themed = false, mode = captureShieldInitialMode, lastEligibility = null;
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
              else { root.classList.remove('light'); root.classList.add('dark'); }
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
            if (lastEligibility !== enabled) {
              lastEligibility = enabled;
              window.webkit?.messageHandlers?.captureShieldAppearance?.postMessage(enabled);
            }
          };
          const update = () => {
            scheduled = false;
            if (!allowed() || isAuthentication()) { theme(false); return; }
            const editors = [...document.querySelectorAll(editorSelector)].filter(rendered);
            if (editors.length !== 1) { theme(false); return; }
            const editor = editors[0];
            if (!document.getElementById('capture-shield-compact')) {
              const style = document.createElement('style'); style.id = 'capture-shield-compact';
              style.textContent = `
                html[data-cs-chat-page] { color-scheme:dark; background:transparent!important; }
                html[data-cs-chat-page] body, html[data-cs-chat-page] [data-cs-surface] { background-color:transparent!important; }
                html[data-cs-chat-page] [data-cs-editor] { min-height:24px!important; max-height:var(--cs-editor-max,160px)!important; overflow-y:auto!important; }
                html[data-cs-chat-page] [data-cs-editor-wrap] { margin-block:2px!important; }
                html[data-cs-chat-page] [data-cs-composer-body] { padding-block:4px!important; }
                html[data-cs-chat-page] [data-cs-thumbnail] { box-sizing:border-box!important; width:var(--cs-thumb-size,64px)!important; min-width:var(--cs-thumb-size,64px)!important; max-width:var(--cs-thumb-size,64px)!important; height:var(--cs-thumb-size,64px)!important; min-height:0!important; max-height:var(--cs-thumb-size,64px)!important; flex-shrink:0!important; background-size:contain!important; background-repeat:no-repeat!important; background-position:center!important; }
                html[data-cs-chat-page] [data-cs-thumbnail] img, html[data-cs-chat-page] [data-cs-thumb-paint] { max-width:100%!important; max-height:100%!important; width:100%!important; height:100%!important; object-fit:contain; background-size:contain!important; background-repeat:no-repeat!important; background-position:center!important; }
              `;
              document.head.appendChild(style);
            }
            theme(true);
            // Only known structural surfaces, never message contents, media or code.
            // A single native backdrop owns alpha. Layering translucent parent
            // colors would make some parts almost opaque again.
            for (let node = editor.parentElement; node && node !== document.body; node = node.parentElement) {
              if (node.matches('main,[role="main"]') || node.getBoundingClientRect().width >= innerWidth * 0.65)
                set(node,'data-cs-surface','');
            }
            document.querySelectorAll('main,[role="main"],#thread').forEach(node => set(node,'data-cs-surface',''));
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
            if (!userChoseSidebar) {
              const button = sidebarButton();
              if (button) {
                if (button !== lastSidebarButton) { lastSidebarButton = button; sidebarAttempts = 0; }
                const label = button.getAttribute('aria-label') || '';
                const open = button.getAttribute('aria-expanded') === 'true' || /^(Close sidebar|Hide sidebar|关闭边栏|隐藏边栏)$/.test(label);
                // SSR controls may exist before their click handlers. Recheck the actual state;
                // never turn a failed early click (or a pre-hydration closed state) into success.
                if (open && sidebarAttempts < 30 && Date.now() - lastSidebarAttempt >= 250) {
                  sidebarAttempts++; lastSidebarAttempt = Date.now(); button.click(); setTimeout(schedule, 250);
                }
              }
            }
          };
          // WebKit may stop animation frames when an ordinary window is covered.
          // A coalesced timer still reapplies attributes to replacement editors.
          const schedule = () => { if (!scheduled) { scheduled = true; setTimeout(update, 16); } };
          document.addEventListener('click', event => {
            if (event.isTrusted && event.target instanceof Element && event.target.closest(sidebarSelector)) userChoseSidebar = true;
          }, true);
          window.captureShieldPresentation = {
            setMode(value) { mode = value === 'legacy' ? 'legacy' : 'normal'; update(); return themed; },
            toggleSidebar() {
              if (!allowed() || isAuthentication()) return false;
              const button = sidebarButton(); if (!button) return false;
              userChoseSidebar = true; button.click(); return true;
            }
          };
          addEventListener('resize', schedule);
          document.addEventListener('input', schedule, true);
          document.addEventListener('load', schedule, true);
          new MutationObserver(schedule).observe(document.documentElement, {
            childList:true, subtree:true, attributes:true,
            attributeFilter:['contenteditable','spellcheck','autocorrect','writingsuggestions','data-theme','aria-expanded','class']
          });
          window.addEventListener('popstate', schedule);
          window.addEventListener('resize', schedule);
          update(); schedule();
        })();
        """#
    }
}
