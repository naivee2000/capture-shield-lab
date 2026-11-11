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
    func close() { controller.webView.stopLoading(); controller.window?.close() }
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
    @Test func toolbarCanUseTheKnownCollapsedSidebarOpenerBeforeHover() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("""
        <html><body><button style="opacity:0" aria-label="打开边栏" aria-controls="ds-sidebar" aria-expanded="false">Open</button>
        <textarea id="mobile-composer-prompt"></textarea><script>window.openCalls=0;document.querySelector('button').onclick=()=>window.openCalls++;</script>
        </body></html>
        """)
        try await page.wait("document.querySelector('textarea')?.getAttribute('spellcheck') === 'false'")
        #expect(await ChatPageAdapter.toggleSidebar(in: page.controller.webView))
        let calls = try await page.controller.webView.evaluateJavaScript("window.openCalls") as? Int
        #expect(calls == 1)
    }
    @Test func offscreenCloseButtonDoesNotPreventReopeningSidebar() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load("""
        <html><body><button id="open" aria-label="打开边栏" aria-controls="ds-sidebar" aria-expanded="false">Open</button>
        <button id="close" style="position:absolute;left:-400px;top:0;width:40px" aria-label="关闭边栏" aria-controls="ds-sidebar">Close</button>
        <textarea id="mobile-composer-prompt"></textarea>
        <script>window.openCalls=0;window.closeCalls=0;document.querySelector('#open').onclick=()=>window.openCalls++;document.querySelector('#close').onclick=()=>window.closeCalls++;</script>
        </body></html>
        """)
        try await page.wait("document.querySelector('textarea')?.getAttribute('spellcheck') === 'false'")
        #expect(await ChatPageAdapter.toggleSidebar(in: page.controller.webView))
        let calls = try await page.controller.webView.evaluateJavaScript("[window.openCalls,window.closeCalls]") as? [Int]
        #expect(calls == [1, 0])
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
            <div data-composer-markdown contenteditable="true">Synthetic editor</div>
            <script>setTimeout(()=>{const b=document.querySelector('button');b.onclick=()=>b.setAttribute('aria-expanded',String(b.getAttribute('aria-expanded')!=='true'));b.setAttribute('aria-expanded','true');document.body.dataset.hydrated='true';},150)</script>
            </body></html>
            """
            page.load(html)
            try await page.wait("document.body.dataset.hydrated === 'true' && document.querySelector('button').getAttribute('aria-expanded') === 'false'")
        }
    }
    @Test func compactPageDisablesSuggestionsAndDoesNotFightUserSidebarChoice() async throws {
        let page = PageFixture(); defer { page.close() }
        page.load(ChatPreview.html)
        try await page.wait("document.querySelector('[data-cs-editor]')?.getAttribute('writingsuggestions') === 'false'")
        let initial = try await page.controller.webView.evaluateJavaScript("document.querySelector('[aria-controls=\"app-shell-sidebar\"]').getAttribute('aria-expanded')") as? String
        #expect(initial == "false")
        #expect(await ChatPageAdapter.toggleSidebar(in: page.controller.webView))
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
}
