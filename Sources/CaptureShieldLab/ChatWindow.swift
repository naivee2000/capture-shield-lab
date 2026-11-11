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

@MainActor final class ChatWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: ChatWebView
    let isMain: Bool
    private(set) var preferences: ChatPreferences
    private let defaults: UserDefaults
    private let preview: Bool
    private let status = NSTextField(labelWithString: "Loading…")
    private let back = NSButton(title: "‹", target: nil, action: nil)
    private let forward = NSButton(title: "›", target: nil, action: nil)
    private let modeControl = NSSegmentedControl(labels: ["Normal", "Legacy"], trackingMode: .selectOne, target: nil, action: nil)
    private let zoomLabel = NSButton(title: "90%", target: nil, action: nil)
    private let smaller = NSButton(title: "A−", target: nil, action: nil)
    private let larger = NSButton(title: "A+", target: nil, action: nil)
    var makePopup: ((WKWebViewConfiguration) -> WKWebView?)?
    var hideAll: (() -> Void)?
    var closePopup: (() -> Void)?
    var askToClear: (() -> Void)?
    var didFinish: (() -> Void)?
    var changePreferences: ((ChatPreferences) -> Void)?
    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration, isMain: Bool, preferences: ChatPreferences = ChatPreferences(),
         defaults: UserDefaults = .standard, preview: Bool = false) {
        self.isMain = isMain; self.preferences = preferences; self.defaults = defaults; self.preview = preview
        ChatPageAdapter.disableInputSuggestions(persist: !preview)
        ChatPageAdapter.install(in: configuration, preview: preview)
        webView = ChatWebView(frame: .zero, configuration: configuration)
        let saved = isMain ? defaults.string(forKey: "ChatWindowFrame").map(NSRectFromString) : nil
        let frame = WindowPlacement.restore(saved, screens: NSScreen.screens.map(\.visibleFrame))
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = preview ? "CaptureShield — UI Preview" : (isMain ? "CaptureShield — ChatGPT" : "CaptureShield — Web window")
        window.level = .normal; window.hidesOnDeactivate = false
        window.backgroundColor = .black; window.hasShadow = false
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 640, height: 480)
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        window.delegate = self
        buildContent(window)
        // Saved rectangles are outer frames. Apply after installing native window chrome.
        window.setFrame(frame, display: false)
        applyPreferences(preferences)
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.back.isEnabled = self?.webView.canGoBack == true }
        }, webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.forward.isEnabled = self?.webView.canGoForward == true }
        }]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(_ window: NSWindow) {
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = root
        status.font = .systemFont(ofSize: 11); status.maximumNumberOfLines = 2
        status.setAccessibilityLabel("Page status")
        for view in [webView, status] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor), webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor), webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4), status.heightAnchor.constraint(equalToConstant: 28)
        ])
        back.target = self; back.action = #selector(goBack); back.setAccessibilityLabel("Back")
        forward.target = self; forward.action = #selector(goForward); forward.setAccessibilityLabel("Forward")
        modeControl.target = self; modeControl.action = #selector(selectMode); modeControl.setAccessibilityLabel("Sharing mode")
        smaller.target = self; smaller.action = #selector(zoomOut); smaller.setAccessibilityLabel("Decrease page size")
        larger.target = self; larger.action = #selector(zoomIn); larger.setAccessibilityLabel("Increase page size")
        zoomLabel.target = self; zoomLabel.action = #selector(resetZoom); zoomLabel.setAccessibilityLabel("Reset page size to 90 percent")
        let toolbar = NSToolbar(identifier: "CaptureShieldChatToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("navigation"), .init("sidebar"), .flexibleSpace, .init("sharingMode"), .init("zoom"), .init("hide")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "navigation":
            item.label = "Navigation"
            let home = NSButton(image: NSImage(systemSymbolName: "house", accessibilityDescription: "ChatGPT home")!, target: self, action: #selector(goHome))
            let reload = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload page")!, target: self, action: #selector(reloadPage))
            item.view = group([back, forward, home, reload])
        case "sidebar":
            item.label = "Sidebar"
            item.view = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")!, target: self, action: #selector(toggleSidebar))
        case "sharingMode": item.label = "Sharing mode"; item.view = modeControl
        case "zoom": item.label = "Page size"; item.view = group([smaller, zoomLabel, larger])
        case "hide":
            item.label = "Hide"
            item.view = NSButton(image: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide chat windows")!, target: self, action: #selector(hideOrClose))
        default: return nil
        }
        return item
    }
    private func group(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views); stack.spacing = 4; stack.orientation = .horizontal
        return stack
    }
    var ownedWindows: [NSWindow] {
        guard let window else { return [] }
        return [window] + (window.attachedSheet.map { [$0] } ?? [])
    }
    func applyPreferences(_ value: ChatPreferences) {
        preferences = value
        for owned in ownedWindows { configureAppearance(of: owned) }
        webView.pageZoom = Double(value.zoomPercent) / 100
        modeControl.selectedSegment = value.mode == .normal ? 0 : 1
        zoomLabel.title = "\(value.zoomPercent)%"
        smaller.isEnabled = value.zoomPercent > 70; larger.isEnabled = value.zoomPercent < 140
    }
    func configureAppearance(of window: NSWindow) {
        window.sharingType = preferences.mode == .legacy ? .none : .readOnly
        window.alphaValue = preferences.mode.opacity; window.level = .normal; window.hasShadow = false
    }
    private func request(_ value: ChatPreferences) {
        if let changePreferences { changePreferences(value) } else { applyPreferences(value) }
    }
    @objc private func selectMode() {
        var next = preferences; next.mode = modeControl.selectedSegment == 0 ? .normal : .legacy; request(next)
    }
    @objc private func zoomOut() { var next = preferences; next.changeZoom(by: -1); request(next) }
    @objc private func zoomIn() { var next = preferences; next.changeZoom(by: 1); request(next) }
    @objc private func resetZoom() { var next = preferences; next.resetZoom(); request(next) }
    @objc private func toggleSidebar() {
        Task { [weak self] in
            guard let self else { return }
            if !(await ChatPageAdapter.toggleSidebar(in: self.webView)) {
                self.setStatus("Sidebar control unavailable on this page. Use the website's sidebar button.")
            }
        }
    }
    func present() {
        guard let window else { return }
        configureAppearance(of: window)
        window.setFrame(WindowPlacement.restore(window.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: false)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(webView)
        NSApp.activate()
    }
    func setStatus(_ text: String) { status.stringValue = text }
    @objc func goHome() {
        if preview { webView.loadHTMLString(ChatPreview.html, baseURL: nil) }
        else { webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    }
    @objc func reloadPage() { webView.reload() }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func hideOrClose() { if isMain { hideAll?() } else { closePopup?() } }
    @objc private func clearLogin() { askToClear?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideOrClose(); return true }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        if isMain, let window { defaults.set(NSStringFromRect(window.frame), forKey: "ChatWindowFrame") }
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
        window?.subtitle = webView.url?.host ?? "Offline preview"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setStatus("Text chat · ⌘⇧Space hides/shows · Normal is shareable; verify Legacy on your receiver")
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
        configureAppearance(of: alert.window)
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
