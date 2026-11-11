import AppKit
import WebKit
import CaptureCore

@MainActor final class ImageAttachmentCoordinator {
    private weak var owner: ChatWindow?
    private(set) var image: CGImage?
    private var view: ImagePreview?
    private var prepared: Data?
    private var consent = AttachmentConsent()
    private var epoch = UUID()
    private var confirming = false
    private var store: AttachmentTemporaryStore?
    init(owner: ChatWindow) { self.owner = owner }
    func prepare(_ image: CGImage) {
        invalidate(); self.image = image
        let view = ImagePreview(image: image); self.view = view
        view.cancel = { [weak self] in self?.invalidate() }
        view.retake = { [weak owner] in owner?.captureScreenshot() }
        view.add = { [weak self] crop in Task { await self?.confirm(cropped: crop) } }
        showPreview()
    }
    func showPreview() {
        guard let root = owner?.window?.contentView, let view else { return }
        // Reviewing means editing again, not reusing the consent for an earlier crop.
        epoch = UUID(); consent.cancel(); prepared = nil; confirming = false
        view.busy(false)
        view.showMessage("Drag to crop, or keep the full image. Adding may upload it to ChatGPT; send your message yourself.")
        if view.superview == nil {
            view.frame = root.bounds; view.autoresizingMask = [.width, .height]; root.addSubview(view)
        }
        view.isHidden = false; owner?.window?.makeFirstResponder(view)
    }
    func invalidate() {
        epoch = UUID(); consent.cancel(); prepared = nil; confirming = false; image = nil
        if let view, owner?.window?.firstResponder === view { owner?.window?.makeFirstResponder(owner?.webView) }
        view?.removeFromSuperview(); view = nil
    }
    func confirm(cropped: CGImage? = nil) async {
        guard !confirming, let image = cropped ?? image, let owner else { return }
        confirming = true; view?.busy(true)
        let current = epoch
        do {
            let data = try await Task.detached { try ImagePreparation.png(image) }.value
            guard current == epoch else { return }
            guard let document = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview), current == epoch else {
                throw ImageInputError.message("Open a ChatGPT chat with an available image attachment control, then try again. No image was uploaded.")
            }
            prepared = data; consent.arm(document: document)
            view?.isHidden = true
            _ = await AttachmentPageBridge.request(in: owner.webView, preview: owner.preview)
            if current == epoch, prepared != nil {
                owner.setStatus("Image ready. If no attachment appears, use ChatGPT's + attachment button. Review/cancel with Image Preview. Nothing is sent automatically.")
            }
        } catch {
            guard current == epoch else { return }
            consent.cancel(); prepared = nil; confirming = false; view?.busy(false)
            let message = (error as? ImageInputError)?.localizedDescription ?? "Could not prepare the image. Nothing was added."
            view?.showMessage(message); owner.setStatus(message)
        }
    }
    func supply(to frame: WKFrameInfo) async -> [URL]? {
        guard let owner, owner.window?.isVisible == true, frame.isMainFrame,
              AttachmentPolicy.allows(frame.request.url, preview: owner.preview),
              owner.preview || (frame.securityOrigin.protocol == "https" && frame.securityOrigin.host == "chatgpt.com"),
              let data = prepared else {
            owner?.setStatus("Use Screenshot or Paste Image, review it, then choose Add to Chat."); return nil
        }
        let current = epoch
        guard let document = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview),
              current == epoch, consent.consume(document: document) else { return nil }
        do {
            if store == nil { store = try AttachmentTemporaryStore() }
            let url = try store!.writePNG(data)
            invalidate()
            owner.setStatus("Image handed to ChatGPT. Check its attachment preview/upload status, then send your message yourself.")
            return [url]
        } catch {
            confirming = false; prepared = nil; view?.busy(false); view?.isHidden = false
            let message = "Could not create the temporary image. Nothing was added."
            view?.showMessage(message); owner.setStatus(message); return nil
        }
    }
    func close() { invalidate(); store?.close(); store = nil }
}
