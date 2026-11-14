import AppKit
import WebKit
import Testing
import CaptureCore
@testable import CaptureShieldLab

@MainActor @Suite(.serialized) struct CompactUITests {
    private func owner() -> ChatWindow {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let window = ChatWindow(configuration: config, isMain: false, preferences: .init(mode: .normal), preview: true)
        window.window?.title = "CaptureShield synthetic layout test"; window.window?.orderFront(nil)
        return window
    }
    private func wait(_ web: WKWebView, _ expression: String) async throws {
        for _ in 0..<120 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw SpeechFailure(stage: .insertion, code: 408, message: "Synthetic layout did not settle")
    }
    @Test func compactStateTransitionsKeepTextAndVisibleStop() {
        let owner = owner(); defer { owner.closeTestFixture() }
        owner.window?.setFrame(NSRect(x: 100, y: 100, width: 640, height: 480), display: true)
        #expect(owner.window?.frame.size == NSSize(width: 640, height: 480))
        owner.showSpeechPane(true)
        let pane = owner.speechPane
        for phase in [SpeechSessionState.Phase.idle, .preparing, .recording, .transcribing, .ready] {
            pane.update(phase: phase, busy: false, inserting: false, uncertain: false, sourceName: "Synthetic application with a very long name")
            owner.window?.contentView?.layoutSubtreeIfNeeded()
            #expect(pane.preferredHeight == 36)
            #expect(pane.record.frame.width >= 40)
            #expect(pane.record.isHidden == false)
            #expect(owner.webView.frame.height >= 300)
            if phase == .recording { #expect(pane.record.title == "Stop" && pane.record.isEnabled) }
        }
        pane.setTranscript("Synthetic editable text 中文")
        pane.update(phase: .ready, busy: false, inserting: false, uncertain: false, sourceName: "Fixture")
        pane.toggleTranscript()
        #expect(pane.result.isEditable)
        #expect(pane.preferredHeight <= 188)
        var edited = ""
        pane.editAction = { edited = $0 }
        pane.result.string = "Edited 中文"; pane.textDidChange(Notification(name: NSText.didChangeNotification))
        pane.toggleTranscript(); pane.toggleSettings(); pane.toggleSettings()
        owner.applyPreferences(.init(mode: .legacy)); owner.applyPreferences(.init(mode: .normal))
        #expect(edited == "Edited 中文" && pane.result.string == edited)
        pane.setTranscript(""); pane.update(phase: .idle, busy: false, inserting: false, uncertain: false, sourceName: "Fixture")
        #expect(pane.preferredHeight == 36 && !pane.transcriptExpanded)
    }
    @Test func backgroundOnlyAlphaKeepsChildrenAndSheetsOpaque() {
        let owner = owner(); defer { owner.closeTestFixture() }
        for mode in [ChatSharingMode.normal, .legacy, .normal, .legacy] {
            owner.applyPreferences(.init(mode: mode))
            #expect(owner.window?.alphaValue == 1)
            #expect(owner.window?.backgroundColor.alphaComponent == CGFloat(mode.backgroundOpacity))
            #expect(owner.webView.alphaValue == 1 && owner.speechPane.alphaValue == 1)
            let sheet = NSWindow(); owner.configureAppearance(of: sheet)
            #expect(sheet.alphaValue == 1)
            #expect(sheet.sharingType == (mode == .legacy ? .none : .readOnly))
        }
    }
    @Test func composerShrinksWithoutTouchingDraftImageOrCode() async throws {
        let owner = owner(); defer { owner.webView.stopLoading(); owner.closeTestFixture() }
        owner.webView.loadHTMLString("""
        <html><style>body{background:#101010;color:white;margin:0}main{background:#101010;height:100vh}
        textarea{width:90%;height:200px}pre{background:rgb(30,40,50)}</style><body><main>
        <pre id="code">const synthetic = 42;</pre><form data-composer-body><img id="attachment" width="48" height="48" alt="Synthetic image">
        <textarea id="prompt-textarea">Existing draft 中文</textarea><button type="submit">Send</button></form>
        <script>window.sends=0;document.querySelector('form').onsubmit=e=>{e.preventDefault();window.sends++}</script></main></body></html>
        """, baseURL: nil)
        try await wait(owner.webView, "!!document.querySelector('[data-cs-editor]')")
        let large = try await owner.webView.evaluateJavaScript("parseFloat(getComputedStyle(document.querySelector('textarea')).maxHeight)") as! Double
        owner.window?.setFrame(NSRect(x: 100, y: 100, width: 640, height: 480), display: true)
        owner.showSpeechPane(true)
        try await wait(owner.webView, "parseFloat(getComputedStyle(document.querySelector('textarea')).maxHeight) < \(large)")
        _ = try await owner.webView.evaluateJavaScript("document.querySelector('textarea').value = 'Synthetic line\\n'.repeat(40);document.querySelector('textarea').dispatchEvent(new Event('input',{bubbles:true}))")
        try await wait(owner.webView, "document.querySelector('textarea').scrollHeight > document.querySelector('textarea').clientHeight")
        owner.applyPreferences(.init(mode: .legacy))
        try await wait(owner.webView, "document.documentElement.dataset.csMode === 'legacy'")
        let safe = try await owner.webView.evaluateJavaScript("document.querySelector('textarea').value === 'Synthetic line\\n'.repeat(40) && !!document.querySelector('#attachment') && window.sends === 0 && getComputedStyle(document.querySelector('#code')).backgroundColor === 'rgb(30, 40, 50)' && getComputedStyle(document.querySelector('main')).opacity === '1'") as? Bool
        #expect(safe == true)
        _ = try await owner.webView.evaluateJavaScript("document.body.insertAdjacentHTML('afterbegin','<input type=password>')")
        try await wait(owner.webView, "!document.documentElement.hasAttribute('data-cs-chat-page')")
        #expect(try await owner.webView.evaluateJavaScript("document.querySelector('textarea').style.height") as? String == "")
    }
    @Test func transparentWebBackgroundProbe() async throws {
        let owner = owner(); defer { owner.webView.stopLoading(); owner.closeTestFixture() }
        owner.applyPreferences(.init(mode: .legacy))
        owner.webView.loadHTMLString("""
        <html><body style='margin:0;color:white'><main style='height:100vh'>
        <textarea id='prompt-textarea'>Synthetic text</textarea>
        <img style='position:absolute;left:100px;top:100px;width:40px;height:40px' src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='40' height='40'%3E%3Crect width='40' height='40' fill='red'/%3E%3C/svg%3E">
        <div style='position:absolute;left:100px;top:160px;font:bold 48px sans-serif'>TEXT</div>
        </main></body></html>
        """, baseURL: nil)
        try await wait(owner.webView, "document.documentElement.dataset.csMode === 'legacy'")
        try await Task.sleep(for: .milliseconds(200))
        let image = try await owner.webView.takeSnapshot(configuration: nil)
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let blank = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 30, y: bitmap.pixelsHigh - 30)?.usingColorSpace(.deviceRGB))
        #expect(blank.alphaComponent < 0.01)
        let width = try #require(try await owner.webView.evaluateJavaScript("innerWidth") as? Double)
        let scale = Double(bitmap.pixelsWide) / width
        let foreground = try #require(bitmap.colorAt(x: Int(120 * scale), y: Int(120 * scale))?.usingColorSpace(.deviceRGB))
        #expect(foreground.alphaComponent > 0.99 && foreground.redComponent > 0.99)
        var solidTextPixels = 0
        for y in Int(165 * scale)..<Int(210 * scale) {
            for x in Int(100 * scale)..<Int(240 * scale) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.99 && color.redComponent > 0.99 { solidTextPixels += 1 }
            }
        }
        #expect(solidTextPixels > 50)
    }
    @Test func attachmentThumbnailShrinksButItsActionsAndOutsideImagesSurvive() async throws {
        let owner = owner(); defer { owner.webView.stopLoading(); owner.closeTestFixture() }
        owner.window?.setFrame(NSRect(x: 100, y: 100, width: 640, height: 480), display: true)
        owner.webView.loadHTMLString("""
        <html><body><img id="reply-image" width="200" height="200"><form>
        <button id="file" type="button" aria-haspopup="dialog" aria-label="synthetic.png" style="width:120px;height:120px"><img width="120" height="120" alt="Synthetic"></button>
        <button id="remove" type="button" aria-label="Remove file">Remove</button>
        <textarea id="prompt-textarea">Existing draft 中文</textarea><button type="submit">Send</button></form>
        <script>window.opens=0;window.removes=0;window.sends=0;document.querySelector('#file').onclick=()=>window.opens++;
        document.querySelector('#remove').onclick=()=>window.removes++;document.querySelector('form').onsubmit=e=>{e.preventDefault();window.sends++};</script></body></html>
        """, baseURL: nil)
        try await wait(owner.webView, "document.querySelector('#file').hasAttribute('data-cs-thumbnail')")
        let measured = try await owner.webView.evaluateJavaScript("""
        (()=>{const card=document.querySelector('#file');card.click();document.querySelector('#remove').click();
        return {height:card.getBoundingClientRect().height,outside:document.querySelector('#reply-image').getBoundingClientRect().height,
        draft:document.querySelector('textarea').value==='Existing draft 中文',opens:window.opens,removes:window.removes,sends:window.sends};})()
        """) as! [String: Any]
        #expect(abs((measured["height"] as! Double) - 56) < 0.1)
        #expect(abs((measured["outside"] as! Double) - 200) < 0.1)
        #expect(measured["draft"] as? Bool == true)
        #expect(measured["opens"] as? Int == 1 && measured["removes"] as? Int == 1 && measured["sends"] as? Int == 0)
    }
}
