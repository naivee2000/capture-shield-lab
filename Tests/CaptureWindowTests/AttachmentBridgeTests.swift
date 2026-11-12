import Testing
import AppKit
import WebKit
import CaptureCore
@testable import CaptureShieldLab

@MainActor struct AttachmentBridgeTests {
    private func fixture() -> ChatWindow {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let controller = ChatWindow(configuration: config, isMain: false, preferences: ChatPreferences(mode: .normal), preview: true)
        controller.window?.orderFront(nil)
        return controller
    }
    private func wait(_ web: WKWebView, _ expression: String) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw ImageInputError.message("Synthetic attachment state timed out: \(expression)")
    }
    private func waitPhase(_ controller: ChatWindow, _ phase: ImageAttachmentCoordinator.Phase, seconds: Int = 5) async throws {
        for _ in 0..<(seconds * 25) {
            if controller.images.phase == phase { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        throw ImageInputError.message("Attachment phase not reached: \(phase)")
    }
    @Test func newlyCreatedUnrelatedInputOutsideComposerIsNotAnAttachment() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.window?.close() }
        controller.webView.loadHTMLString("""
        <form><div id="prompt-textarea" contenteditable="true">Draft</div><button id="composer-plus-btn" type="button">+</button></form>
        <script>window.wrong=0;document.querySelector('button').onclick=()=>{const file=document.createElement('input');file.type='file';file.onchange=()=>window.wrong++;document.body.append(file)};</script>
        """, baseURL: nil)
        try await wait(controller.webView, "typeof window.wrong === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await Task.sleep(for: .milliseconds(400))
        #expect(try await controller.webView.evaluateJavaScript("window.wrong") as? Int == 0)
        #expect(controller.images.phase == .ready)
    }
    @Test func decorativeImageDoesNotConfirmAttachment() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        _ = try await controller.webView.evaluateJavaScript("const icon=document.createElement('img');icon.src='data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\"><rect width=\"16\" height=\"16\" fill=\"red\"/></svg>';document.body.append(icon)")
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.images.phase == .handedToPage)
        #expect(controller.images.image != nil)
    }
    @Test func temporaryComposerInvisibilityPreservesCrop() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        _ = try await controller.webView.evaluateJavaScript("document.querySelector('[contenteditable]').hidden=true")
        try await Task.sleep(for: .milliseconds(400))
        #expect(controller.images.image != nil)
        #expect(controller.images.phase != .idle)
    }
    @Test func navigationResetRejectsDelayedOldCompositionSnapshot() async throws {
        let controller = fixture(); defer { controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        await controller.composition.synchronize(in: controller.webView)
        _ = try await controller.webView.evaluateJavaScript("Object.defineProperty(window,'captureShieldCompositionState',{get(){const end=Date.now()+100;while(Date.now()<end){};return {document:'old-test-document',composing:false}}});true", in: nil, contentWorld: ChatPageAdapter.world)
        let pending = Task { await controller.composition.synchronize(in: controller.webView) }
        try await Task.sleep(for: .milliseconds(30))
        controller.composition.reset()
        await pending.value
        #expect(controller.composition.document == nil)
        #expect(controller.composition.composing == nil)
    }
    static let html = """
    <html><body><div data-composer-markdown contenteditable="true">Existing synthetic draft</div>
    <input type="file" accept="image/png,image/jpeg" id="file"><button id="send">Send</button>
    <script>window.changes=0;window.sent=0;document.querySelector('#file').onchange=async e=>{window.changes++;window.bytes=(await e.target.files[0].arrayBuffer()).byteLength;};document.querySelector('#send').onclick=()=>window.sent++;</script></body></html>
    """
    @Test func attachmentButtonCanCreateAGenericInputLazily() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString("""
        <form><div id="prompt-textarea" contenteditable="true">Synthetic draft</div>
        <button type="button" id="composer-plus-btn" aria-label="Add photos & files">+</button></form>
        <input type="file" id="unrelated">
        <script>window.changes=0;window.sent=0;
        document.querySelector('form').onsubmit=e=>{e.preventDefault();window.sent++};
        document.querySelector('#composer-plus-btn').onclick=()=>setTimeout(()=>{
          const file=document.createElement('input');file.type='file';file.hidden=true;document.querySelector('form').append(file);
          file.onchange=async()=>{window.bytes=(await file.files[0].arrayBuffer()).byteLength;window.changes++;
            const img=document.createElement('img');img.src=URL.createObjectURL(file.files[0]);img.width=100;img.height=100;img.alt=file.files[0].name;document.querySelector('form').append(img);const remove=document.createElement('button');remove.type='button';remove.setAttribute('aria-label','Remove file');remove.textContent='Remove';document.querySelector('form').append(remove);};
        },100);</script>
        """, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        let values = try await controller.webView.evaluateJavaScript("[window.changes,window.sent,document.querySelector('#unrelated').files.length]") as? [Int]
        #expect(values == [1,0,0])
        #expect(try await controller.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').textContent") as? String == "Synthetic draft")
        try await waitPhase(controller, .visible)
        #expect(controller.images.image == nil)
    }
    @Test func fileCallbackWithoutVisibleAttachmentKeepsCropForRecovery() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        #expect(controller.images.image != nil)
        #expect(controller.images.phase == .handedToPage)
        try await waitPhase(controller, .failed, seconds: 35)
        #expect(controller.images.image != nil)
        #expect(controller.window?.contentView?.subviews.compactMap { $0 as? ImagePreview }.first?.isHidden == false)
    }
    @Test func missingCallbackTimesOutWithoutLosingCropOrSending() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html.replacingOccurrences(of: "image/png,image/jpeg", with: "application/pdf"), baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        #expect(controller.images.phase == .ready)
        try await waitPhase(controller, .failed, seconds: 35)
        #expect(controller.images.image != nil)
        #expect(try await controller.webView.evaluateJavaScript("[window.changes,window.sent]") as? [Int] == [0,0])
    }
    @Test func unrelatedFileChooserCannotConsumePreparedImage() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html.replacingOccurrences(of: "image/png,image/jpeg", with: "application/pdf"), baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        _ = try await controller.webView.evaluateJavaScript("document.querySelector('#file').click()")
        try await Task.sleep(for: .milliseconds(200))
        #expect(try await controller.webView.evaluateJavaScript("window.changes") as? Int == 0)
        #expect(controller.images.phase == .ready)
    }
    @Test func recognizedMenuCanOpenAnExistingGenericComposerInput() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.window?.close() }
        controller.webView.loadHTMLString("""
        <form><div id="prompt-textarea" contenteditable="true">Synthetic draft</div>
        <input type="file" id="file" hidden><button type="button" id="composer-plus-btn">+</button></form>
        <script>window.changes=0;document.querySelector('#composer-plus-btn').onclick=()=>{
          const menu=document.createElement('button');menu.setAttribute('role','menuitem');menu.textContent='Add photos & files';document.body.append(menu);
          menu.onclick=()=>document.querySelector('#file').click();};
        document.querySelector('#file').onchange=()=>window.changes++;</script>
        """, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.changes === 1")
        #expect(controller.images.phase == .handedToPage)
    }
    @Test func uploadErrorPreservesCropAndDoesNotRepeatDelivery() async throws {
        let controller = fixture(); defer { controller.images.close(); controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        _ = try await controller.webView.evaluateJavaScript("const error=document.createElement('div');error.setAttribute('role','alert');error.textContent='Upload failed';document.body.append(error)")
        try await waitPhase(controller, .failed)
        #expect(controller.images.image != nil)
        #expect(try await controller.webView.evaluateJavaScript("[window.changes,window.sent]") as? [Int] == [1,0])
    }
    @Test func webCompositionAndPopupTrackersAreIndependent() async throws {
        let first = fixture(); defer { first.images.close(); first.window?.close() }
        first.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(first.webView, "typeof window.changes === 'number'")
        await first.composition.synchronize(in: first.webView)
        #expect(first.composition.composing == false)
        _ = try await first.webView.evaluateJavaScript("document.querySelector('[contenteditable]').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}))")
        for _ in 0..<50 where first.composition.composing != true { try await Task.sleep(for: .milliseconds(20)) }
        #expect(first.composition.composing == true)
        let second = ChatWindow(configuration: first.webView.configuration, isMain: false, preview: true)
        defer { second.window?.close() }
        second.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(second.webView, "typeof window.changes === 'number'")
        await second.composition.synchronize(in: second.webView)
        #expect(second.composition.composing == false)
        #expect(first.composition.composing == true)
        _ = try await first.webView.evaluateJavaScript("document.querySelector('[contenteditable]').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}))")
        for _ in 0..<50 where first.composition.composing != false { try await Task.sleep(for: .milliseconds(20)) }
        #expect(first.composition.composing == false)
        // WebKit can deliver the IME processing key after compositionend. 229 alone
        // must not latch an already committed composition back on forever.
        _ = try await first.webView.evaluateJavaScript("document.querySelector('[contenteditable]').dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,keyCode:229,isComposing:false}))")
        try await Task.sleep(for: .milliseconds(100))
        #expect(first.composition.composing == false)
        first.composition.reset()
        #expect(first.composition.composing == nil)
    }
    @Test func confirmedImageUsesNativeUploadWithoutSendingOrChangingDraft() async throws {
        let controller = fixture(); defer { controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html, baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        let before = try await controller.webView.evaluateJavaScript("window.changes") as? Int
        #expect(before == 0)
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        await controller.images.confirm()
        let values = try await controller.webView.evaluateJavaScript("[window.changes,window.sent]") as? [Int]
        #expect(values == [1,0])
        let draft = try await controller.webView.evaluateJavaScript("document.querySelector('[contenteditable]').textContent") as? String
        #expect(draft == "Existing synthetic draft")
    }
    @Test func navigationDiscardsPendingImageAndUnknownInputsDoNotReceiveIt() async throws {
        let controller = fixture(); defer { controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html.replacingOccurrences(of: "image/png,image/jpeg", with: "application/pdf"), baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        let changes = try await controller.webView.evaluateJavaScript("window.changes") as? Int
        #expect(changes == 0)
        controller.webView.loadHTMLString("<html><body>Next document</body></html>", baseURL: nil)
        try await wait(controller.webView, "document.body?.textContent === 'Next document'")
        #expect(controller.images.image == nil)
    }
    @Test func preparationFailureIsVisibleInsideThePreview() async throws {
        let controller = fixture(); defer { controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString("<html><body>Unknown page</body></html>", baseURL: nil)
        try await wait(controller.webView, "document.body?.textContent === 'Unknown page'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        let preview = controller.window?.contentView?.subviews.compactMap { $0 as? ImagePreview }.first
        let visibleText = preview?.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.map(\.stringValue).joined(separator: " ") ?? ""
        #expect(visibleText.contains("Open a ChatGPT chat"))
    }
    @Test func reopeningFallbackPreviewAllowsARevisedCropToBeConfirmed() async throws {
        let controller = fixture(); defer { controller.webView.stopLoading(); controller.window?.close() }
        controller.webView.loadHTMLString(Self.html.replacingOccurrences(of: "image/png,image/jpeg", with: "application/pdf"), baseURL: nil)
        try await wait(controller.webView, "typeof window.changes === 'number'")
        controller.images.prepare(try ImagePreparation.decode(ImagePipelineTests.fixture()))
        await controller.images.confirm()
        controller.images.showPreview()
        _ = try await controller.webView.evaluateJavaScript("document.querySelector('#file').accept='image/png';")
        await controller.images.confirm()
        try await wait(controller.webView, "window.bytes > 0")
        let count = try await controller.webView.evaluateJavaScript("window.changes") as? Int
        #expect(count == 1)
    }
}
