import AppKit
import WebKit
import CaptureCore

@MainActor final class ImageAttachmentCoordinator {
    enum Phase: Equatable { case idle, preparing, ready, handedToPage, visible, failed }
    private weak var owner: ChatWindow?
    private(set) var image: CGImage?
    private(set) var phase: Phase = .idle
    private var view: ImagePreview?
    private var prepared: Data?
    private var consent = AttachmentConsent()
    private var epoch = UUID()
    private var monitor: Task<Void, Never>?
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
    func showCaptureFailure(_ message: String) {
        if let view, !view.isHidden { view.showMessage(message) }
    }
    func showPreview() {
        guard let root = owner?.window?.contentView, let view else { return }
        let mayHaveUploaded = phase == .handedToPage || phase == .failed
        resetRequest(); phase = .idle
        view.busy(false)
        view.showMessage(mayHaveUploaded
            ? "Check the chat for an existing attachment before adding again. Reviewing cancels the previous confirmation; it cannot undo a website upload."
            : "Drag to crop, or keep the full image. Adding may upload it to ChatGPT; send your message yourself.")
        if view.superview == nil { view.frame = root.bounds; view.autoresizingMask = [.width, .height]; root.addSubview(view) }
        view.isHidden = false; owner?.window?.makeFirstResponder(view)
    }
    private func resetRequest() {
        epoch = UUID(); consent.cancel(); prepared = nil; monitor?.cancel(); monitor = nil
    }
    func invalidate() {
        resetRequest(); phase = .idle; image = nil
        if let view, owner?.window?.firstResponder === view { owner?.window?.makeFirstResponder(owner?.webView) }
        view?.removeFromSuperview(); view = nil
    }
    func confirm(cropped: CGImage? = nil) async {
        guard phase == .idle || phase == .failed, let image = cropped ?? image, let owner else { return }
        resetRequest(); phase = .preparing; view?.busy(true)
        let current = epoch
        do {
            let data = try await Task.detached { try ImagePreparation.png(image) }.value
            guard current == epoch else { return }
            guard let document = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview), current == epoch else {
                throw ImageInputError.message("Open a ChatGPT chat with an available image attachment control, then try again. No image was uploaded.")
            }
            prepared = data; consent.arm(document: document); phase = .ready
            view?.isHidden = true; owner.window?.makeFirstResponder(owner.webView)
            let triggered = await AttachmentPageBridge.request(in: owner.webView, preview: owner.preview)
            guard current == epoch else { return }
            if phase == .ready {
                owner.setStatus(triggered ? "Image prepared. Waiting for the webpage file chooser…" : "Attachment control not identified. Click ChatGPT's + → Add photos & files, or use Image Preview to cancel/review.")
            }
            monitor = Task { [weak self] in await self?.verifyDelivery(epoch: current, document: document) }
        } catch {
            guard current == epoch else { return }
            fail((error as? ImageInputError)?.localizedDescription ?? "Could not prepare the image. Nothing was added.")
        }
    }
    private func verifyDelivery(epoch current: UUID, document: String) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !Task.isCancelled, current == epoch, ContinuousClock.now < deadline, let owner {
            let identity = await AttachmentPageBridge.identity(in: owner.webView, preview: owner.preview)
            guard !Task.isCancelled, current == epoch else { return }
            guard let identity else { fail("Could not observe the current document. Crop retained; check the page before retrying."); return }
            guard identity == document else { invalidate(); return }
            guard !Task.isCancelled, current == epoch else { return }
            if phase == .ready { await AttachmentPageBridge.advance(in: owner.webView) }
            guard !Task.isCancelled, current == epoch else { return }
            let observation = await AttachmentPageBridge.observe(in: owner.webView)
            guard !Task.isCancelled, current == epoch else { return }
            if phase == .handedToPage {
                switch observation {
                case .visible:
                    phase = .visible; image = nil; view?.removeFromSuperview(); view = nil
                    owner.setStatus("Attachment visible in the composer. Check its upload status, then send manually. Your draft was not changed.")
                    return
                case .failed: fail("The webpage reports an upload error. Crop retained. Check/remove any existing attachment before retrying."); return
                case .uploading: owner.setStatus("Attachment thumbnail visible; webpage upload is still in progress. Nothing was sent.")
                case .stale: fail("Attachment display could not be verified. Crop retained. Check the webpage before retrying."); return
                case .pending: break
                }
            }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        }
        guard !Task.isCancelled, current == epoch else { return }
        fail(phase == .handedToPage
             ? "The file was handed to the webpage, but no completed attachment preview was confirmed within 30 seconds. Crop retained; check the chat before retrying."
             : "No file chooser callback within 30 seconds. Crop retained. Try Add to Chat again, then click the webpage's + → Add photos & files.")
    }
    private func fail(_ message: String) {
        consent.cancel(); prepared = nil; phase = .failed
        view?.busy(false); view?.isHidden = false; view?.showMessage(message); owner?.setStatus(message)
    }
    func supply(to frame: WKFrameInfo) async -> [URL]? {
        guard phase == .ready, let owner, owner.window?.isVisible == true, frame.isMainFrame,
              AttachmentPolicy.allows(frame.request.url, preview: owner.preview),
              owner.preview || (frame.securityOrigin.protocol == "https" && frame.securityOrigin.host == "chatgpt.com"),
              let data = prepared else {
            owner?.setStatus("Use Screenshot or Paste Image, review it, then choose Add to Chat."); return nil
        }
        let current = epoch
        guard let document = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview),
              current == epoch, await AttachmentPageBridge.permitsChooser(in: owner.webView),
              current == epoch, consent.consume(document: document) else { return nil }
        do {
            if store == nil { store = try AttachmentTemporaryStore() }
            let url = try store!.writePNG(data)
            phase = .handedToPage; prepared = nil
            await AttachmentPageBridge.didDeliver(in: owner.webView, filename: url.lastPathComponent)
            guard current == epoch else { return nil }
            owner.setStatus("File handed to webpage. Waiting for an attachment preview; nothing was sent.")
            return [url]
        } catch {
            fail("Could not create the temporary image. Nothing was added."); return nil
        }
    }
    func close() { invalidate(); store?.close(); store = nil }
}
