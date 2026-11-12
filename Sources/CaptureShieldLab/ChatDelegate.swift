import AppKit
import WebKit
import Carbon
import CaptureCore

@MainActor final class ChatDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var main: ChatWindow!
    private var popups: [ChatWindow] = []
    private var hotKey: EventHotKeyRef?
    private var screenshotHotKey: EventHotKeyRef?
    private var keyboardMonitor: Any?
    private let windowDiagnostics = WindowDiagnostics()
    private lazy var cursor = PrivateCursorController(experimental: preview) { [weak self] in
        guard let self, self.main != nil else { return [] }
        return ([self.main!] + self.popups).flatMap(\.ownedWindows)
    }

    private var hotKeyHandler: EventHandlerRef?
    private var hiddenWindows: [ChatWindow] = []
    private var clearing = false
    private var pasteMonitor: Any?
    private let preview: Bool
    private let defaults: UserDefaults
    private var preferences: ChatPreferences

    init(preview: Bool = false) {
        self.preview = preview
        let defaults = preview ? UserDefaults(suiteName: "\(Bundle.main.bundleIdentifier ?? "CaptureShield").preview")! : .standard
        self.defaults = defaults; preferences = ChatPreferences.load(from: defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PanelSharingProtection.configure(legacy: preferences.mode == .legacy)
        AttachmentTemporaryStore.cleanAbandoned()
        installMenu()
        let config = WKWebViewConfiguration(); config.websiteDataStore = preview ? .nonPersistent() : .default()
        main = ChatWindow(configuration: config, isMain: true, preferences: preferences, defaults: defaults, preview: preview)
        wire(main)
        main.present(); main.goHome()
        registerShortcut()
        pasteMonitor = PlainTextPaste.installMonitor()
        cursor.changed = { [weak self] in self?.refreshCursorButtons() }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) == nil }
            return handled ? nil : event
        }
        refreshCursorButtons()
        windowDiagnostics.startIfRequested()
    }
    private func wire(_ controller: ChatWindow) {
        controller.togglePrivateCursor = { [weak self] in self?.toggleCursor() }
        controller.updateCursorButton(enabled: cursor.enabled, available: cursor.available)
        controller.hideAll = { [weak self] in self?.hideAll() }
        controller.askToClear = { [weak self] in self?.clearLogin() }
        controller.changePreferences = { [weak self] settings in self?.updatePreferences(settings) }
        controller.makePopup = { [weak self] config in
            guard let self, !self.clearing, self.popups.count < 8 else { return nil }
            let popup = ChatWindow(configuration: config, isMain: false, preferences: self.preferences,
                                   defaults: self.defaults, preview: self.preview)
            self.wire(popup); self.popups.append(popup); popup.present()
            return popup.webView
        }
        controller.closePopup = { [weak self, weak controller] in
            guard let self, let controller else { return }
            controller.cancelScreenshot(); controller.images.close()
            self.cursor.suspend(); controller.webView.stopLoading(); controller.window?.orderOut(nil)
            self.popups.removeAll { $0 === controller }
            self.hiddenWindows.removeAll { $0 === controller }
        }
    }
    private func updatePreferences(_ next: ChatPreferences) {
        guard !clearing, main != nil else { return }
        if next.mode == .normal { cursor.disable() } else { cursor.suspend() }
        let controllers = [main!] + popups
        let owned = controllers.flatMap(\.ownedWindows)
        let visible = NSApp.orderedWindows.filter { owned.contains($0) && $0.isVisible && !$0.isMiniaturized }
        let key = NSApp.keyWindow
        let changedMode = next.mode != preferences.mode
        // Hide all owned surfaces first; no popup remains in the old mode during the update.
        if changedMode { visible.forEach { $0.orderOut(nil) } }
        PanelSharingProtection.configure(legacy: next.mode == .legacy)
        preferences = next; next.save(to: defaults)
        controllers.forEach { $0.applyPreferences(next) }
        refreshCursorButtons()
        if changedMode {
            visible.reversed().forEach { $0.orderFront(nil) }
            if NSApp.isActive, let key, visible.contains(key) { key.makeKey() }
        }
    }
    @objc private func hideAll() {
        guard !clearing, main != nil else { return }
        cursor.suspend()
        hiddenWindows = ChatInteraction.pendingRestore(previous: hiddenWindows,
            visible: ([main!] + popups).filter { $0.window?.isVisible == true })
        for controller in hiddenWindows {
            controller.cancelScreenshot()
            controller.window?.attachedSheet?.orderOut(nil)
            controller.window?.orderOut(nil)
        }
    }
    @objc private func showAll() {
        guard !clearing, main != nil else { return }
        main.present()
        for controller in hiddenWindows where controller !== main {
            controller.present(); controller.window?.attachedSheet?.orderFront(nil)
        }
        main.window?.attachedSheet?.orderFront(nil)
        hiddenWindows.removeAll()
    }
    @objc func toggleVisibility() {
        if ([main!] + popups).contains(where: { $0.window?.isVisible == true }) { hideAll() }
        else { showAll() }
    }
    @objc private func clearLogin() {
        guard !clearing, let window = main.window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Clear login data on this Mac?"
        alert.informativeText = "This closes chat popups and clears this app's cookies and website storage. Cloud conversations are not deleted. Unsaved input will be lost."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear local data")
        main.configureAppearance(of: alert.window)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.clearing = true; self.cursor.disable()
            ([self.main!] + self.popups).forEach { $0.cancelScreenshot(); $0.images.close() }
            for popup in self.popups { popup.webView.stopLoading(); popup.window?.orderOut(nil) }
            self.popups.removeAll(); self.hiddenWindows.removeAll()
            self.main.webView.stopLoading(); self.main.window?.orderOut(nil)
            let old = self.main!
            // Destroy all old views before reopening, so back/forward history cannot restore a signed-in page.
            self.main = nil
            old.webView.navigationDelegate = nil; old.webView.uiDelegate = nil
            let store = old.webView.configuration.websiteDataStore
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
                guard let self else { return }
                let config = WKWebViewConfiguration(); config.websiteDataStore = store
                self.main = ChatWindow(configuration: config, isMain: true, preferences: self.preferences,
                                       defaults: self.defaults, preview: self.preview)
                self.wire(self.main); self.clearing = false
                self.main.present(); self.main.goHome()
            }
        }
    }
    private func registerShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChatDelegate>.fromOpaque(context).takeUnretainedValue()
                if !owner.clearing {
                    if identifier.id == 1 { owner.toggleVisibility() }
                    if identifier.id == 2 { owner.takeScreenshot() }
                }
            }
            return noErr
        }, 1, &spec, context, &hotKeyHandler)
        let visibility = installed == noErr ? RegisterEventHotKey(ChatKeyboard.visibilityKey, ChatKeyboard.carbonModifiers,
            EventHotKeyID(signature: 0x43534844, id: 1), GetApplicationEventTarget(), 0, &hotKey) : installed
        let screenshot = installed == noErr ? RegisterEventHotKey(ChatKeyboard.screenshotKey, ChatKeyboard.carbonModifiers,
            EventHotKeyID(signature: 0x43534844, id: 2), GetApplicationEventTarget(), 0, &screenshotHotKey) : installed
        var missing: [String] = []
        if visibility != noErr { missing.append(ChatKeyboard.visibilityLabel) }
        if screenshot != noErr { missing.append(ChatKeyboard.screenshotLabel) }
        if !missing.isEmpty {
            let message = "Shortcut unavailable: " + missing.joined(separator: ", ") + ". Use the toolbar or app menu."
            main.setStatus(message); main.didFinish = { [weak self] in self?.main.setStatus(message) }
        }
    }
    private func activeChat() -> ChatWindow {
        popups.first { $0.window === NSApp.keyWindow } ?? main
    }
    private func refreshCursorButtons() {
        guard main != nil else { return }
        ([main!] + popups).forEach { $0.updateCursorButton(enabled: cursor.enabled, available: cursor.available) }
    }
    @objc private func toggleCursor() {
        guard cursor.available else { activeChat().setStatus("Private Cursor is not receiver-verified. Its experiment is available only in --chat-preview."); return }
        cursor.toggle(legacy: preferences.mode == .legacy)
    }
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if [123,124,125,126].contains(event.keyCode), ProcessInfo.processInfo.environment["CAPTURESHIELD_WINDOW_DIAGNOSTICS"] == "1" {
            let responder = NSApp.keyWindow?.firstResponder
            let data: [String: Any] = ["event": "movement-key", "active": NSApp.isActive,
                "eventWindow": event.window?.windowNumber ?? -1, "keyWindow": NSApp.keyWindow?.windowNumber ?? -1,
                "flags": event.modifierFlags.rawValue,
                "directMarked": (responder as? any NSTextInputClient)?.hasMarkedText().description ?? "unknown",
                "contextMarked": (responder as? NSView)?.inputContext?.client.hasMarkedText().description ?? "unknown",
                "currentMarked": NSTextInputContext.current?.client.hasMarkedText().description ?? "unknown",
                "webComposing": main?.composition.composing?.description ?? "unknown"]
            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) {
                try? FileHandle.standardError.write(contentsOf: json + Data([10]))
            }
        }
        guard NSApp.isActive, main != nil, !clearing,
              let controller = ([main!] + popups).first(where: { $0.window === event.window }) else { return event }
        if event.keyCode == 53 { cursor.disable(); return event }
        let responder = event.window?.firstResponder
        var ancestor = responder as? NSView
        var webFocused = false
        while let view = ancestor {
            if view === controller.webView { webFocused = true; break }
            ancestor = view.superview
        }
        let direct = (responder as? any NSTextInputClient)?.hasMarkedText()
        let contextual = NSTextInputContext.current?.client.hasMarkedText()
        let nativeMarked: Bool? = direct == true || contextual == true ? true : direct ?? contextual
        let marked = ChatKeyboard.blocksMovement(nativeMarked: nativeMarked, webFocused: webFocused, webComposing: controller.composition.composing)
        let modal = NSApp.modalWindow != nil || event.window?.attachedSheet != nil
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if !marked, !modal, flags == ChatKeyboard.modifiers, event.keyCode == ChatKeyboard.cursorKey {
            if !event.isARepeat { toggleCursor() }; return nil
        }
        if let direction = ChatKeyboard.direction(keyCode: event.keyCode, modifiers: event.modifierFlags, markedText: marked, modal: modal) {
            cursor.suspend(); controller.move(direction); return nil
        }
        return event
    }
    @objc private func loadSampleImage() { if preview { activeChat().images.prepare(ChatPreview.sampleImage()) } }
    @objc private func inspectAttachmentControls() {
        guard ProcessInfo.processInfo.environment["CAPTURESHIELD_ATTACHMENT_DIAGNOSTICS"] == "1" else { return }
        let controller = activeChat()
        Task {
            let metadata = await AttachmentPageBridge.controlDiagnostics(in: controller.webView, preview: preview)
            try? FileHandle.standardError.write(contentsOf: Data(("CAPTURESHIELD_ATTACHMENT " + metadata + "\n").utf8))
            controller.setStatus("Attachment control metadata recorded. No draft, chat text or credentials were read.")
        }
    }
    @objc private func takeScreenshot() {
        guard !clearing, main != nil, NSApp.modalWindow == nil, activeChat().window?.attachedSheet == nil else { return }
        activeChat().captureScreenshot()
    }
    @objc private func captureDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber, main != nil, !clearing else { return }
        activeChat().captureScreenshot(displayID: id.uint32Value)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for screen in NSScreen.screens {
            let item = menu.addItem(withTitle: screen.localizedName, action: #selector(captureDisplay(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        }
    }
    private func installMenu() {
        let bar = NSMenu(); let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        for (title, action, key) in [("Show ChatGPT", #selector(showAll), ""), ("Hide chat windows", #selector(hideAll), ""),
                                     ("Clear local login…", #selector(clearLogin), ""), ("Quit CaptureShield", #selector(quit), "q")] {
            app.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        app.addItem(withTitle: "Show / Hide (\(ChatKeyboard.visibilityLabel))", action: #selector(toggleVisibility), keyEquivalent: "").target = self
        if preview { app.addItem(withTitle: "Load sample image (offline)", action: #selector(loadSampleImage), keyEquivalent: "").target = self }
        if ProcessInfo.processInfo.environment["CAPTURESHIELD_ATTACHMENT_DIAGNOSTICS"] == "1" {
            app.addItem(withTitle: "Inspect attachment controls", action: #selector(inspectAttachmentControls), keyEquivalent: "").target = self
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Screenshot (\(ChatKeyboard.screenshotLabel))", action: #selector(takeScreenshot), keyEquivalent: "").target = self
        let displays = NSMenuItem(title: "Capture Display", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: "Capture Display"); displayMenu.delegate = self
        displays.submenu = displayMenu; app.addItem(displays)
        app.addItem(withTitle: "Private Cursor (\(ChatKeyboard.cursorLabel))", action: #selector(toggleCursor), keyEquivalent: "").target = self
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let menu = NSMenu(title: "Edit")
        edit.submenu = menu; bar.addItem(edit)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                     ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                     ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            if key == "v" { item.action = #selector(pasteText); item.target = self }
        }
        NSApp.mainMenu = bar
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func pasteText() { PlainTextPaste.insert(into: NSApp.keyWindow) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !clearing { showAll() }; return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        windowDiagnostics.stop()
        cursor.shutdown()
        if main != nil { ([main!] + popups).forEach { $0.cancelScreenshot(); $0.images.close() } }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let screenshotHotKey { UnregisterEventHotKey(screenshotHotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}
