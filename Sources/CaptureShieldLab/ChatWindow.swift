import AppKit
import WebKit
import CaptureCore

/// No native context menu that can open an unprotected browser or download a file.
/// Edit menu and standard keyboard shortcuts remain available.
@MainActor final class ChatWebView: WKWebView {
    var pasteImage: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {}
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
}

@MainActor enum PlainTextPaste {
    static func insert(into window: NSWindow?) {
        let board = NSPasteboard.general
        if ImagePreparation.clipboardHasImage(board) {
            var view = window?.firstResponder as? NSView
            while let current = view {
                if let web = current as? ChatWebView, let paste = web.pasteImage { paste(); return }
                view = current.superview
            }
        }
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
    let composition = CompositionTracker()
    let webView: ChatWebView
    let isMain: Bool
    lazy var images = ImageAttachmentCoordinator(owner: self)
    private(set) var preferences: ChatPreferences
    private let defaults: UserDefaults
    let preview: Bool
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
    var togglePrivateCursor: (() -> Void)?
    private let cursorButton = NSButton(title: "Private Cursor", target: nil, action: nil)
    private var observations: [NSKeyValueObservation] = []
    private lazy var screenshots = ScreenshotService(defaults: defaults)
    private var screenshotTask: Task<Void, Never>?
    private var screenshotGeneration = 0
    private var compatibilityPanel: CompatibilityPanel?
    private var osUpgradeNotice = false
    private var lastStatus = "Loading…"
    private var shortcutWarning = ""
    let speechPane = SpeechPane()
    lazy var speech: SpeechCoordinator = {
        if preview {
            return SpeechCoordinator(owner: self, defaults: defaults, capture: PreviewAudioCapture(),
                                     backend: PreviewSpeechBackend(failure: defaults.bool(forKey: "PreviewSpeechFailure")))
        }
        return SpeechCoordinator(owner: self, defaults: defaults)
    }()
    var toggleRecording: (() -> Void)?
    var showTranscription: (() -> Void)?
    private let recordButton = NSButton(title: "Record", target: nil, action: nil)
    private var speechHeight: NSLayoutConstraint!
    private let statusBar = NSView()
    private var statusHeight: NSLayoutConstraint!
    private var appearanceBridge: WebAppearanceBridge?


    init(configuration: WKWebViewConfiguration, isMain: Bool, preferences: ChatPreferences = ChatPreferences(),
         defaults: UserDefaults = .standard, preview: Bool = false) {
        self.isMain = isMain; self.preferences = preferences; self.defaults = defaults; self.preview = preview
        let scripts = configuration.userContentController.userScripts
        configuration.userContentController = WKUserContentController()
        scripts.forEach { configuration.userContentController.addUserScript($0) }
        ChatPageAdapter.disableInputSuggestions(persist: !preview)
        ChatPageAdapter.install(in: configuration, preview: preview, mode: preferences.mode)
        composition.install(in: configuration)
        webView = ChatWebView(frame: .zero, configuration: configuration)
        let saved = isMain ? defaults.string(forKey: "ChatWindowFrame").map(NSRectFromString) : nil
        let frame = WindowPlacement.restore(saved, screens: NSScreen.screens.map(\.visibleFrame))
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = preview ? "CaptureShield — UI Preview" : (isMain ? "CaptureShield — ChatGPT" : "CaptureShield — Web window")
        window.setAccessibilityIdentifier(isMain ? "chat-window" : "chat-popup")
        window.standardWindowButton(.closeButton)?.setAccessibilityIdentifier("window-close")
        window.standardWindowButton(.miniaturizeButton)?.setAccessibilityIdentifier("window-minimize")
        window.standardWindowButton(.zoomButton)?.setAccessibilityIdentifier("window-zoom")
        window.level = .normal; window.hidesOnDeactivate = false
        window.backgroundColor = .black; window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        appearanceBridge = WebAppearanceBridge(webView: webView, preview: preview)
        appearanceBridge?.unavailable = { [weak self] in
            guard let self, self.preferences.mode == .legacy else { return }
            self.setStatus("Background transparency is unavailable in this WebKit version. Text remains fully opaque; Legacy sharing is unchanged.")
        }
        window.delegate = self
        buildContent(window)
        // Saved rectangles are outer frames. Apply after installing native window chrome.
        window.setFrame(frame, display: false)
        applyPreferences(preferences)
        // contentMinSize takes precedence over minSize. Derive it from the real
        // toolbar/titlebar metrics instead of assuming a fixed chrome height.
        window.contentMinSize = window.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: 640, height: 480)).size
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.pasteImage = { [weak self] in self?.pasteImage() }

        webView.allowsBackForwardNavigationGestures = true
        observations = [webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.back.isEnabled = self?.webView.canGoBack == true }
        }, webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.forward.isEnabled = self?.webView.canGoForward == true }
        }, webView.observe(\.url, options: [.old, .new]) { [weak self] _, change in
            MainActor.assumeIsolated {
                if change.oldValue != change.newValue { self?.cancelScreenshot(); self?.images.invalidate() }
            }
        }]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildContent(_ window: NSWindow) {
        let root = NSView(); root.wantsLayer = true
        window.contentView = root
        status.font = .systemFont(ofSize: 12); status.maximumNumberOfLines = 1; status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setAccessibilityLabel("Page status")
        status.setAccessibilityIdentifier("page-status")
        let details = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Page status details")!, target: self, action: #selector(showStatusDetails))
        let dismiss = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss page notice")!, target: self, action: #selector(dismissStatus))
        for button in [details, dismiss] { button.controlSize = .small }
        speechPane.isHidden = true
        speechHeight = speechPane.heightAnchor.constraint(equalToConstant: 0)
        speechHeight.isActive = true
        speechPane.heightChanged = { [weak self] in self?.updateSpeechHeight() }
        for view in [webView, speechPane, statusBar] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        for view in [status, details, dismiss] { view.translatesAutoresizingMaskIntoConstraints = false; statusBar.addSubview(view) }
        statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 0); statusHeight.isActive = true; statusBar.isHidden = true
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor), webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor), webView.bottomAnchor.constraint(equalTo: speechPane.topAnchor),
            speechPane.leadingAnchor.constraint(equalTo: root.leadingAnchor), speechPane.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            speechPane.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor), statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8), status.trailingAnchor.constraint(equalTo: details.leadingAnchor, constant: -6),
            details.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -4), dismiss.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
            status.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor), details.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor), dismiss.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
        back.target = self; back.action = #selector(goBack); back.setAccessibilityLabel("Back")
        forward.target = self; forward.action = #selector(goForward); forward.setAccessibilityLabel("Forward")
        modeControl.target = self; modeControl.action = #selector(selectMode); modeControl.setAccessibilityLabel("Sharing mode")
        smaller.target = self; smaller.action = #selector(zoomOut); smaller.setAccessibilityLabel("Decrease page size")
        larger.target = self; larger.action = #selector(zoomIn); larger.setAccessibilityLabel("Increase page size")
        zoomLabel.target = self; zoomLabel.action = #selector(resetZoom); zoomLabel.setAccessibilityLabel("Reset page size to 90 percent")
        modeControl.setAccessibilityIdentifier("sharing-mode")
        smaller.setAccessibilityIdentifier("zoom-out"); larger.setAccessibilityIdentifier("zoom-in")
        zoomLabel.setAccessibilityIdentifier("zoom-reset")
        recordButton.setAccessibilityIdentifier("toolbar-record")
        let toolbar = NSToolbar(identifier: "CaptureShieldChatToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("navigation"), .init("sidebar"), .init("screenshot"), .init("imagePreview"), .init("record"), .init("transcript"), .flexibleSpace, .init("sharingMode"), .init("compatibility"), .init("cursor"), .init("zoom"), .init("hide")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "imagePreview" {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Images"; item.toolTip = "Paste Image or review a prepared image"
            item.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Images")
            let menu = NSMenu()
            for (title, action) in [("Paste Image", #selector(pasteImage)), ("Review prepared image", #selector(reviewImage))] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
            }
            if preview {
                let sample = NSMenuItem(title: "Load sample image (offline)", action: #selector(loadPreviewImage), keyEquivalent: "")
                sample.target = self; menu.addItem(sample)
            }
            item.menu = menu; return item
        }
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
        case "screenshot":
            item.label = "Screenshot"; item.toolTip = "Screenshot (\(ChatKeyboard.screenshotLabel))"
            item.view = NSButton(image: NSImage(systemSymbolName: "camera", accessibilityDescription: "Screenshot")!, target: self, action: #selector(takeScreenshot))
        case "sharingMode":
            item.label = "Sharing mode"; item.view = modeControl; item.visibilityPriority = .high
            let entry = NSMenuItem(title: "Sharing mode", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Sharing mode")
            for (index, title) in ["Normal", "Legacy"].enumerated() {
                let child = NSMenuItem(title: title, action: #selector(selectModeFromMenu(_:)), keyEquivalent: "")
                child.target = self; child.tag = index; menu.addItem(child)
            }
            entry.submenu = menu; item.menuFormRepresentation = entry
        case "record":
            item.label = "Record / Stop"; item.toolTip = "Record selected app audio (\(ChatKeyboard.recordLabel))"
            item.visibilityPriority = .high
            recordButton.target = self; recordButton.action = #selector(recordAudio); item.view = recordButton
        case "compatibility":
            item.label = "Compatibility"; item.toolTip = "Compatibility and local diagnostics"
            item.view = NSButton(image: NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "Compatibility")!, target: self, action: #selector(showCompatibility))
        case "transcript":
            item.label = "Transcription"
            let button = NSButton(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcription settings and pending text")!, target: self, action: #selector(reviewTranscript))
            button.setAccessibilityIdentifier("toolbar-transcript")
            item.view = button
        case "cursor":
            item.label = "Private Cursor"; cursorButton.target = self; cursorButton.action = #selector(toggleCursor)
            cursorButton.image = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "Private Cursor")
            cursorButton.imagePosition = .imageOnly; cursorButton.setAccessibilityLabel("Private Cursor")
            cursorButton.setAccessibilityIdentifier("private-cursor-toggle")
            cursorButton.setButtonType(.pushOnPushOff); item.view = cursorButton
        case "zoom":
            item.label = "Page size"; item.view = group([smaller, zoomLabel, larger])
            let entry = NSMenuItem(title: "Page size", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Page size")
            for (title, action, id) in [("Decrease page size", #selector(zoomOut), "zoom-out-menu"),
                ("Reset page size to 90 percent", #selector(resetZoom), "zoom-reset-menu"),
                ("Increase page size", #selector(zoomIn), "zoom-in-menu")] {
                let child = NSMenuItem(title: title, action: action, keyEquivalent: "")
                child.target = self; child.setAccessibilityIdentifier(id); menu.addItem(child)
            }
            entry.submenu = menu; item.menuFormRepresentation = entry
        case "hide":
            item.label = "Hide"
            item.view = NSButton(image: NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide chat windows")!, target: self, action: #selector(hideOrClose))
        default: return nil
        }
        if let button = item.view as? NSButton {
            let entry = NSMenuItem(title: item.label, action: button.action, keyEquivalent: "")
            entry.target = button.target
            entry.setAccessibilityIdentifier("toolbar-menu-" + identifier.rawValue)
            item.menuFormRepresentation = entry
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
        ChatPageAdapter.install(in: webView.configuration, preview: preview, mode: value.mode)
        Task { [weak self] in
            guard let self else { return }
            await ChatPageAdapter.applyMode(self.preferences.mode, in: self.webView)
        }
        modeControl.selectedSegment = value.mode == .normal ? 0 : 1
        zoomLabel.title = "\(value.zoomPercent)%"
        smaller.isEnabled = value.zoomPercent > 70; larger.isEnabled = value.zoomPercent < 140
    }
    func configureAppearance(of window: NSWindow) {
        WindowProtection.apply(to: window, mode: preferences.mode)
        ChatAppearance.apply(to: window, mode: preferences.mode)
    }
    private func request(_ value: ChatPreferences) {
        if let changePreferences { changePreferences(value) } else { applyPreferences(value) }
    }
    @objc private func selectMode() {
        var next = preferences; next.mode = modeControl.selectedSegment == 0 ? .normal : .legacy; request(next)
    }
    @objc private func selectModeFromMenu(_ sender: NSMenuItem) {
        modeControl.selectedSegment = sender.tag; selectMode()
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
    func setStatus(_ text: String) {
        lastStatus = text
        status.stringValue = shortcutWarning + (osUpgradeNotice ? "macOS changed: retest sharing. " : "") + text
        status.toolTip = status.stringValue
        let routine = (text == "Loading…" || text == ChatKeyboard.summary) && shortcutWarning.isEmpty && !osUpgradeNotice
        statusBar.isHidden = routine; statusHeight.constant = routine ? 0 : 28
    }
    func setShortcutWarning(_ text: String) { shortcutWarning = text.isEmpty ? "" : text + " "; setStatus(lastStatus) }
    func noteOSUpgrade() { osUpgradeNotice = true; setStatus(lastStatus) }
    func showSpeechPane(_ show: Bool) { speechPane.isHidden = !show; updateSpeechHeight() }
    private func updateSpeechHeight() {
        speechHeight.constant = speechPane.isHidden ? 0 : speechPane.preferredHeight
    }
    @objc private func dismissStatus() { statusBar.isHidden = true; statusHeight.constant = 0 }
    @objc private func showStatusDetails() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Page status"; alert.informativeText = status.stringValue
        alert.addButton(withTitle: "Done"); configureAppearance(of: alert.window)
        alert.beginSheetModal(for: window)
    }
    func updateRecordButton(recording: Bool, enabled: Bool) { recordButton.title = recording ? "Stop" : "Record"; recordButton.isEnabled = enabled }
    @objc private func recordAudio() { toggleRecording?() }
    @objc private func reviewTranscript() { showTranscription?() }
    func compatibilitySummary() -> CompatibilitySummary {
        CompatibilitySummary(os: ProcessInfo.processInfo.operatingSystemVersion, build: SystemCompatibility.osBuild,
                             mode: preferences.screenshotMode, permissionGranted: screenshots.permissionGranted,
                             failure: screenshots.lastFailure, speechDiagnostic: (isMain ? speech.diagnostic + "\n" : "") +
                             "Web background: \(webView.responds(to: NSSelectorFromString("_setDrawsBackground:")) ? "appearance compatibility hook available (non-public WebKit)" : "unsupported; web backdrop remains opaque")")
    }
    func selectScreenshotMode(_ mode: ScreenshotMode) {
        cancelScreenshot()
        var next = preferences; next.screenshotMode = mode; request(next)
        setStatus("Screenshot method: \(mode.title). Click Screenshot when ready; nothing was captured or uploaded.")
    }
    @objc func showCompatibility() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = CompatibilityPanel(snapshot: { [weak self] in
            self?.compatibilitySummary() ?? CompatibilitySummary(os: ProcessInfo.processInfo.operatingSystemVersion,
                build: SystemCompatibility.osBuild, mode: .auto, permissionGranted: false)
        }, selectMode: { [weak self] mode in self?.selectScreenshotMode(mode) }, didClose: { [weak self] in
            self?.compatibilityPanel = nil; self?.osUpgradeNotice = false
            if let self { self.setStatus(self.lastStatus) }
        })
        compatibilityPanel = panel; configureAppearance(of: panel.window)
        window.beginSheet(panel.window)
    }
    func updateCursorButton(enabled: Bool, available: Bool) {
        cursorButton.state = enabled ? .on : .off
        cursorButton.isEnabled = available && preferences.mode == .legacy
        cursorButton.toolTip = available ? "Experimental local pointer · \(ChatKeyboard.cursorLabel) toggles · Esc restores" : "Not receiver-verified. Test only with --chat-preview."
    }
    @objc private func toggleCursor() { togglePrivateCursor?() }
    func move(_ direction: WindowDirection) {
        guard let window, let screen = window.screen else { return }
        window.setFrame(WindowPlacement.moved(window.frame, direction: direction, visibleFrame: screen.visibleFrame), display: true)
    }
    @objc private func takeScreenshot() { captureScreenshot() }
    @objc func pasteImage() {
        cancelScreenshot()
        do { images.prepare(try ImagePreparation.clipboard(.general)) }
        catch { setStatus((error as? ImageInputError)?.localizedDescription ?? "Could not read this image. Use a single PNG/JPEG.") }
    }
    @objc private func reviewImage() {
        if images.image != nil { images.showPreview() }
        else { setStatus("Use Screenshot or Paste Image to prepare an image.") }
    }
    func captureScreenshot(displayID: CGDirectDisplayID? = nil) {
        guard screenshotTask == nil, window?.attachedSheet == nil else { return }
        let target = displayID ?? ScreenshotService.pointerDisplay()
        let generation = screenshotGeneration
        setStatus("Capturing one screen…")
        screenshotTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.screenshotGeneration { self.screenshotTask = nil } }
            do {
                let image = try await self.screenshots.capture(displayID: target, mode: self.preferences.screenshotMode)
                guard !Task.isCancelled, generation == self.screenshotGeneration else { return }
                self.present(); self.images.prepare(image)
            } catch {
                guard !Task.isCancelled, generation == self.screenshotGeneration else { return }
                self.present()
                let message = (error as? ScreenshotError)?.localizedDescription ?? "Screenshot failed. Open Compatibility… to check permission or select Compatible."
                self.setStatus(message); self.images.showCaptureFailure(message)
            }
        }
    }
    func cancelScreenshot() { screenshotGeneration += 1; screenshotTask?.cancel(); screenshotTask = nil }
    @objc func goHome() {
        if preview { webView.loadHTMLString(ChatPreview.html, baseURL: nil) }
        else { webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    }
    @objc func reloadPage() { webView.reload() }
    @objc private func loadPreviewImage() { if preview { images.prepare(ChatPreview.sampleImage()) } }
    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func hideOrClose() {
        if isMain { if let hideAll { hideAll() } else { window?.orderOut(nil) } }
        else { closePopup?() }
    }
    @objc private func clearLogin() { askToClear?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideOrClose(); return !isMain }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) {
        saveFrame(); speechPane.resizeForContentHeight(window?.contentView?.bounds.height ?? 480)
    }
    private func saveFrame() {
        if isMain, let window { defaults.set(NSStringFromRect(window.frame), forKey: "ChatWindowFrame") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard WebNavigationPolicy.allows(navigationAction.request.url), !navigationAction.shouldPerformDownload else {
            setStatus("This app does not open external apps, local navigation or downloads.")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType { decisionHandler(.allow) }
        else { setStatus("Downloads are not supported."); decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        _ = WebBackgroundCompatibility.setTransparent(false, in: webView)
        composition.reset(); cancelScreenshot(); images.invalidate(); setStatus("Loading…")
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Only the host is displayed: URLs may contain login codes or private conversation IDs.
        window?.subtitle = webView.url?.host ?? "Offline preview"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await ChatPageAdapter.applyMode(preferences.mode, in: webView) }
        let generation = composition.generation
        Task { await composition.synchronize(in: webView, generation: generation) }
        setStatus(ChatKeyboard.summary)
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
        composition.reset(); images.invalidate(); cancelScreenshot()
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
        Task { @MainActor [weak self] in
            guard let self else { completionHandler(nil); return }
            completionHandler(await self.images.supply(to: frame))
        }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        setStatus("Camera and microphone are not supported."); decisionHandler(.deny)
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
    // The async delegate form avoids SDK-specific completion-block isolation
    // annotations while still using WebKit's public confirmation callback.
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard let window, window.isVisible, window.attachedSheet == nil else { return false }
        return await withCheckedContinuation { continuation in
            dialog(message, cancel: true).beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
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
