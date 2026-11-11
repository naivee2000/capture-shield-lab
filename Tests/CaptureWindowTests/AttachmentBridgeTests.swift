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
    static let html = """
    <html><body><div data-composer-markdown contenteditable="true">Existing synthetic draft</div>
    <input type="file" accept="image/png,image/jpeg" id="file"><button id="send">Send</button>
    <script>window.changes=0;window.sent=0;document.querySelector('#file').onchange=async e=>{window.changes++;window.bytes=(await e.target.files[0].arrayBuffer()).byteLength;};document.querySelector('#send').onclick=()=>window.sent++;</script></body></html>
    """
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
