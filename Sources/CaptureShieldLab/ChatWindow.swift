import AppKit
import WebKit
import CaptureCore

/// No native context menu that can open an unprotected browser or download a file.
/// Edit menu and standard keyboard shortcuts remain available.
@MainActor final class ChatWebView: WKWebView {
    override func rightMouseDown(with event: NSEvent) {}
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
}

@MainActor enum PlainTextPaste {
    static func insert(into window: NSWindow?) {
        let board = NSPasteboard.general
        guard let text = ChatInteraction.pasteText(board.string(forType: .string), representations: board.types?.map(\.rawValue) ?? []),
              let input = window?.firstResponder as? any NSTextInputClient else { NSSound.beep(); return }
        // Insert native text without exposing image/HTML clipboard representations to the website.
        input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    static func installMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
                var view = event.window?.firstResponder as? NSView
                while let current = view {
                    if current is ChatWebView { insert(into: event.window); return true }
                    view = current.superview
                }
                return false
            }
            return handled ? nil : event
        }
    }
}

@MainActor final class ChatWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: ChatWebView
    let isMain: Bool
    private let status = NSTextField(labelWithString: "Loading…")
    private let address = NSTextField(labelWithString: "chatgpt.com")
    private let back = NSButton(title: "‹", target: nil, action: nil)
    private let forward = NSButton(title: "›", target: nil, action: nil)
    var makePopup: ((WKWebViewConfiguration) -> WKWebView?)?
    var hideAll: (() -> Void)?
    var closePopup: (() -> Void)?
    var askToClear: (() -> Void)?
    var didFinish: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, isMain: Bool) {
        self.isMain = isMain
        webView = ChatWebView(frame: .zero, configuration: configuration)
        let saved = isMain ? UserDefaults.standard.string(forKey: "ChatWindowFrame").map(NSRectFromString) : nil
        let frame = WindowPlacement.restore(saved, screens: NSScreen.screens.map(\.visibleFrame))
        let panel = LabPanel(contentRect: frame, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        // Set before content is installed or the window is first presented.
        panel.sharingType = .none
        panel.title = isMain ? "CaptureShield — ChatGPT" : "CaptureShield — Web window"
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 640, height: 480)
        panel.collectionBehavior = [.fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)
        buildContent(panel)
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.back.isEnabled = self?.webView.canGoBack == true }
        }, webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.forward.isEnabled = self?.webView.canGoForward == true }
        }]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(_ panel: NSWindow) {
        let root = NSView(); root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.08, blue: 0.12, alpha: 1).cgColor
        root.layer?.cornerRadius = 12; root.layer?.masksToBounds = true
        panel.contentView = root
        let drag = DragBar()
        let brand = NSTextField(labelWithString: "CAPTURE / SHIELD")
        brand.font = .systemFont(ofSize: 12, weight: .bold); brand.textColor = .systemTeal
        address.font = .systemFont(ofSize: 12); address.lineBreakMode = .byTruncatingMiddle
        address.setAccessibilityLabel("Website host")
        let mode = NSTextField(labelWithString: "Legacy sharing · verify on your receiver")
        mode.font = .systemFont(ofSize: 11); mode.textColor = .secondaryLabelColor
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadPage))
        let home = NSButton(title: "ChatGPT", target: self, action: #selector(goHome))
        let hide = NSButton(title: isMain ? "Hide" : "Close", target: self, action: #selector(hideOrClose))
        let clear = NSButton(title: "Clear login…", target: self, action: #selector(clearLogin))
        clear.isHidden = !isMain
        back.target = self; back.action = #selector(goBack); back.setAccessibilityLabel("Back")
        forward.target = self; forward.action = #selector(goForward); forward.setAccessibilityLabel("Forward")
        let controls = NSStackView(views: [back, forward, home, reload, clear, hide])
        controls.spacing = 6; controls.orientation = .horizontal
        status.font = .systemFont(ofSize: 11); status.maximumNumberOfLines = 2
        status.setAccessibilityLabel("Page status")
        for view in [drag, brand, address, mode, controls, webView, status] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: root.topAnchor), drag.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: root.trailingAnchor), drag.heightAnchor.constraint(equalToConstant: 38),
            brand.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), brand.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            address.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 18), address.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            address.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            controls.leadingAnchor.constraint(equalTo: brand.leadingAnchor), controls.topAnchor.constraint(equalTo: drag.bottomAnchor, constant: 3),
            mode.leadingAnchor.constraint(equalTo: brand.leadingAnchor), mode.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 7),
            webView.topAnchor.constraint(equalTo: mode.bottomAnchor, constant: 10), webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor), webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: brand.leadingAnchor), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10), status.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    func present() {
        guard let window else { return }
        window.sharingType = .none
        window.setFrame(WindowPlacement.restore(window.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: false)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(webView)
        NSApp.activate()
    }
    func setStatus(_ text: String) { status.stringValue = text }
    @objc func goHome() { webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    @objc func reloadPage() { webView.reload() }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func hideOrClose() { if isMain { hideAll?() } else { closePopup?() } }
    @objc private func clearLogin() { askToClear?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideOrClose(); return false }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        if isMain, let window { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "ChatWindowFrame") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard WebNavigationPolicy.allows(navigationAction.request.url), !navigationAction.shouldPerformDownload else {
            setStatus("This text-only build does not open external apps, local files or downloads.")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType { decisionHandler(.allow) }
        else { setStatus("Downloads are not supported in this text-only build."); decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { setStatus("Loading…") }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Only the host is displayed: URLs may contain login codes or private conversation IDs.
        address.stringValue = webView.url?.host ?? "Local page"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setStatus("Text chat · ⌘⇧Space shows/hides all chat windows · sharing compatibility is unverified")
        didFinish?()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadFailed(error) }
    private func loadFailed(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        // Do not log localized network errors, which can include sensitive full URLs.
        setStatus("Page could not load (code \(error.code)). Check your connection, then Reload or choose ChatGPT.")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setStatus("Web content stopped. Choose Reload to recover. Messages are never automatically resent.")
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard window?.isVisible == true, WebNavigationPolicy.allows(navigationAction.request.url) else { return nil }
        return makePopup?(configuration)
    }
    func webViewDidClose(_ webView: WKWebView) { if !isMain { closePopup?() } }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        setStatus("Attachments are not supported in this text-only build."); completionHandler(nil)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        setStatus("Camera and microphone are not supported in this text-only build."); decisionHandler(.deny)
    }
    private func dialog(_ message: String, cancel: Bool = false) -> NSAlert {
        let alert = NSAlert(); alert.messageText = "Message from \(webView.url?.host ?? "web page")"
        alert.informativeText = String(message.prefix(2000))
        alert.addButton(withTitle: "OK")
        if cancel { alert.addButton(withTitle: "Cancel") }
        alert.window.sharingType = .none; alert.window.hasShadow = false
        return alert
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        guard let window, window.isVisible, window.attachedSheet == nil else { completionHandler(); return }
        dialog(message).beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let window, window.isVisible, window.attachedSheet == nil else { completionHandler(false); return }
        dialog(message, cancel: true).beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        guard let window, window.isVisible, window.attachedSheet == nil else { completionHandler(nil); return }
        let alert = dialog(prompt, cancel: true)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24)); input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil) }
    }
}
