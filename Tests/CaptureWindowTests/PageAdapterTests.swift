import Testing
import AppKit
import WebKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor private final class PageFixture {
    let controller: ChatWindow
    init(preview: Bool = true) {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        controller = ChatWindow(configuration: configuration, isMain: false,
                                preferences: ChatPreferences(mode: .normal), preview: preview)
        controller.window?.title = "CaptureShield automated synthetic test"
        controller.window?.orderFront(nil)
    }
    func load(_ html: String) { controller.webView.loadHTMLString(html, baseURL: nil) }
    func close() { controller.webView.stopLoading(); controller.closeTestFixture() }
    func wait(_ expression: String) async throws {
        for _ in 0..<100 {
            if (try? await controller.webView.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let installed = try? await controller.webView.evaluateJavaScript("typeof window.captureShieldPresentation", in: nil, contentWorld: ChatPageAdapter.world)
        throw FixtureError.timeout(expression, String(describing: installed))
    }
    enum FixtureError: Error { case timeout(String, String) }
}

@MainActor struct PageAdapterTests {
    @Test func alreadyCollapsedHistoryIsNotClosedAfterWebsiteOpensIt() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.railHTML.replacingOccurrences(of: "let historyOpen=true,pinned=true", with: "let historyOpen=false,pinned=false"))
        try await page.wait("!!document.querySelector('[data-cs-editor]')")
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('#fixture-home').click()")
        try await page.wait("!document.querySelector('#fixture-history').hidden")
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await page.controller.webView.evaluateJavaScript("!document.querySelector('#fixture-history').hidden") as? Bool == true)
        #expect(try await page.controller.webView.evaluateJavaScript("typeof window.captureShieldPresentation.toggleSidebar", in: nil, contentWorld: ChatPageAdapter.world) as? String == "undefined")
    }
    @Test func failedInitialCollapseDoesNotRetryOnEveryMutation() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("<button aria-controls='ds-sidebar' aria-expanded='true'>Close</button><nav id='ds-sidebar'>History</nav><textarea id='prompt-textarea'>Draft</textarea><script>window.calls=0;document.querySelector('button').onclick=()=>window.calls++;</script>")
        try await page.wait("window.calls===1")
        for _ in 0..<3 {
            _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('textarea').dispatchEvent(new Event('input',{bubbles:true}))")
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try await page.controller.webView.evaluateJavaScript("window.calls") as? Int == 1)
    }
    @Test func signedOutComposerIgnoresHiddenLoginFieldsAndUsesCloseControl() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("""
        <html><body><input type="email" hidden>
        <button id="open" aria-label="打开边栏" aria-controls="ds-sidebar" aria-expanded="true">Open</button>
        <nav id="ds-sidebar"><button id="close" aria-label="关闭边栏" aria-controls="ds-sidebar">Close</button></nav>
        <textarea id="mobile-composer-prompt" spellcheck="true"></textarea>
        <script>window.openCalls=0;document.querySelector('#open').onclick=()=>{window.openCalls++;document.querySelector('nav').hidden=false;};document.querySelector('#close').onclick=()=>{document.querySelector('nav').hidden=true;document.querySelector('#open').setAttribute('aria-expanded','false');};</script>
        </body></html>
        """)
        try await page.wait("document.querySelector('textarea')?.getAttribute('spellcheck') === 'false' && document.querySelector('nav').hidden")
        let opened = try await page.controller.webView.evaluateJavaScript("window.openCalls") as? Int
        #expect(opened == 0)
    }
    @Test func sidebarCollapseWaitsForHydrationAndHandlesRestoredOpenState() async throws {
        for initial in ["true", "false"] {
            let page = PageFixture(); defer { page.close() }
            let html = """
            <html><body><button aria-controls="app-shell-sidebar" aria-expanded="\(initial)">Sidebar</button>
            <nav id="app-shell-sidebar">Synthetic history</nav><div data-composer-markdown contenteditable="true">Synthetic editor</div>
            <script>setTimeout(()=>{const b=document.querySelector('button');b.onclick=()=>{b.setAttribute('aria-expanded',String(b.getAttribute('aria-expanded')!=='true'));document.querySelector('nav').hidden=b.getAttribute('aria-expanded')==='false'};b.setAttribute('aria-expanded','true');document.body.dataset.hydrated='true';},150)</script>
            </body></html>
            """
            page.load(html)
            try await page.wait("document.body.dataset.hydrated === 'true' && document.querySelector('button').getAttribute('aria-expanded') === 'false'")
        }
    }
    @Test func compactPageDisablesSuggestionsAndDoesNotFightUserSidebarChoice() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.html)
        try await page.wait("document.querySelector('[data-cs-editor]')?.getAttribute('writingsuggestions') === 'false' && document.querySelector('[aria-controls=\"app-shell-sidebar\"]').getAttribute('aria-expanded') === 'false'")
        let initial = try await page.controller.webView.evaluateJavaScript("document.querySelector('[aria-controls=\"app-shell-sidebar\"]').getAttribute('aria-expanded')") as? String
        #expect(initial == "false")
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('[aria-controls=\"app-shell-sidebar\"]').click()")
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('[data-composer-markdown]').textContent = 'Synthetic typing 中文';")
        try await Task.sleep(for: .milliseconds(200))
        let expanded = try await page.controller.webView.evaluateJavaScript("document.querySelector('[aria-controls=\"app-shell-sidebar\"]').getAttribute('aria-expanded')") as? String
        #expect(expanded == "true")
        let maxHeight = try await page.controller.webView.evaluateJavaScript("getComputedStyle(document.querySelector('[data-cs-editor]')).maxHeight") as? String
        #expect(maxHeight == "160px")
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('[data-composer-markdown]').outerHTML = '<div data-composer-markdown contenteditable=\"true\" spellcheck=\"true\">Replacement synthetic editor</div>'")
        try await page.wait("document.querySelector('[data-composer-markdown]')?.getAttribute('spellcheck') === 'false'")
    }
    @Test func authenticationAndUnknownMarkupRemainUntouched() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("<html data-theme='light'><body><input type='password' spellcheck='true'><div data-composer-markdown contenteditable='true' spellcheck='true'>Synthetic</div></body></html>")
        try await page.wait("document.readyState === 'complete' && !!document.querySelector('input')")
        let unchanged = try await page.controller.webView.evaluateJavaScript("document.documentElement.getAttribute('data-theme') === 'light' && document.querySelector('[contenteditable]').getAttribute('spellcheck') === 'true' && !document.getElementById('capture-shield-compact')") as? Bool
        #expect(unchanged == true)
        page.load("<html data-theme='light'><body><div contenteditable='true' id='unknown'>Synthetic unknown editor</div></body></html>")
        try await page.wait("document.readyState === 'complete' && !!document.querySelector('#unknown')")
        let untouched = try await page.controller.webView.evaluateJavaScript("document.documentElement.getAttribute('data-theme') === 'light' && !document.getElementById('capture-shield-compact')") as? Bool
        #expect(untouched == true)
    }
    @Test func liveAdapterDoesNotModifyNonChatGPTDocuments() async throws {
        let page = PageFixture(preview: false); defer { page.close() }
        page.load(ChatPreview.html)
        try await page.wait("document.readyState === 'complete' && !!document.querySelector('[data-composer-markdown]')")
        let untouched = try await page.controller.webView.evaluateJavaScript("document.querySelector('[data-composer-markdown]').getAttribute('spellcheck') === 'true' && !document.getElementById('capture-shield-compact')") as? Bool
        #expect(untouched == true)
    }
    @Test func duplicateOrUnrelatedHomeControlsAreNeverClicked() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("""
        <html><body><button aria-expanded="false">Home</button><aside id="app-shell-sidebar"><nav>
        <button aria-expanded="false">Home</button><button aria-expanded="false">Home</button></nav></aside>
        <main><textarea id="prompt-textarea"></textarea></main><script>window.calls=0;document.querySelectorAll('button').forEach(b=>b.onclick=()=>window.calls++);</script></body></html>
        """)
        try await page.wait("!!document.querySelector('[data-cs-editor]')")
        #expect(await ChatPageAdapter.check(in: page.controller.webView).sidebar == .unavailable)
        #expect(try await page.controller.webView.evaluateJavaScript("window.calls") as? Int == 0)
    }
    @Test func checkIsReadOnlyAndRecognizedShellSurvivesHiddenEditor() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.railHTML)
        try await page.wait("document.querySelector('#fixture-history')?.hidden === true")
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('[contenteditable]').hidden=true")
        try await page.wait("document.querySelector('[contenteditable]').hidden && document.documentElement.hasAttribute('data-cs-chat-page')")
        for _ in 0..<3 {
            let report = await ChatPageAdapter.check(in: page.controller.webView)
            #expect(report.layout == .navigationRail && report.eligible && report.sidebar == .collapsed && report.reason == .ready)
        }
        #expect(try await page.controller.webView.evaluateJavaScript("document.querySelector('#fixture-history').hidden") as? Bool == true)
        _ = try await page.controller.webView.evaluateJavaScript("document.body.innerHTML='<div contenteditable=true>Unknown synthetic page</div>'")
        try await page.wait("!document.documentElement.hasAttribute('data-cs-chat-page')")
        #expect(await ChatPageAdapter.check(in: page.controller.webView).reason == .unrecognizedLayout)
    }
    @Test func structuralClassChangesAndWrappersDoNotBreakTheAdapter() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.railHTML.replacingOccurrences(of: ">Home</button>", with: ">首页</button>"))
        try await page.wait("document.querySelector('#fixture-history')?.hidden === true")
        _ = try await page.controller.webView.evaluateJavaScript("""
        document.querySelectorAll('main,aside,nav,button').forEach((e,i)=>e.className='changed-hash-'+i);
        const editor=document.querySelector('[contenteditable]'), wrapper=document.createElement('div');
        editor.before(wrapper);wrapper.append(editor);editor.outerHTML=editor.outerHTML;
        """)
        _ = try await page.controller.webView.evaluateJavaScript("document.querySelector('#fixture-home').click()")
        #expect(await ChatPageAdapter.check(in: page.controller.webView).layout == .navigationRail)
    }
    @Test func settledPresentationDoesNotKeepMutatingTheDOM() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.railHTML)
        try await page.wait("document.querySelector('#fixture-history')?.hidden === true")
        try await Task.sleep(for: .milliseconds(200))
        _ = try await page.controller.webView.evaluateJavaScript("window.mutations=0;new MutationObserver(m=>window.mutations+=m.length).observe(document.documentElement,{attributes:true,attributeFilter:['class','data-theme']})")
        for _ in 0..<3 { _ = await ChatPageAdapter.check(in: page.controller.webView) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await page.controller.webView.evaluateJavaScript("window.mutations") as? Int == 0)
    }
}
