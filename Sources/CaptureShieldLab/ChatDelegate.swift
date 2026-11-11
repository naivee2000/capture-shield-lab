import AppKit
import WebKit
import Carbon
import CaptureCore

@MainActor final class ChatDelegate: NSObject, NSApplicationDelegate {
    private var main: ChatWindow!
    private var popups: [ChatWindow] = []
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hiddenWindows: [ChatWindow] = []
    private var clearing = false
    private var pasteMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
        main = ChatWindow(configuration: config, isMain: true)
        wire(main)
        main.present(); main.goHome()
        registerShortcut()
        pasteMonitor = PlainTextPaste.installMonitor()
    }
    private func wire(_ controller: ChatWindow) {
        controller.hideAll = { [weak self] in self?.hideAll() }
        controller.askToClear = { [weak self] in self?.clearLogin() }
        controller.makePopup = { [weak self] config in
            guard let self, !self.clearing, self.popups.count < 8 else { return nil }
            let popup = ChatWindow(configuration: config, isMain: false)
            self.wire(popup); self.popups.append(popup); popup.present()
            return popup.webView
        }
        controller.closePopup = { [weak self, weak controller] in
            guard let self, let controller else { return }
            controller.webView.stopLoading(); controller.window?.orderOut(nil)
            self.popups.removeAll { $0 === controller }
            self.hiddenWindows.removeAll { $0 === controller }
        }
    }
    @objc private func hideAll() {
        guard !clearing, main != nil else { return }
        hiddenWindows = ChatInteraction.pendingRestore(previous: hiddenWindows,
            visible: ([main!] + popups).filter { $0.window?.isVisible == true })
        for controller in hiddenWindows {
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
    func toggleVisibility() {
        if ([main!] + popups).contains(where: { $0.window?.isVisible == true }) { hideAll() }
        else { showAll() }
    }
    @objc private func clearLogin() {
        guard !clearing, let window = main.window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Clear login data on this Mac?"
        alert.informativeText = "This closes chat popups and clears this app's cookies and website storage. Cloud conversations are not deleted. Unsaved input will be lost."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear local data")
        alert.window.sharingType = .none; alert.window.hasShadow = false
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.clearing = true
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
                self.main = ChatWindow(configuration: config, isMain: true)
                self.wire(self.main); self.clearing = false
                self.main.present(); self.main.goHome()
            }
        }
    }
    private func registerShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChatDelegate>.fromOpaque(context).takeUnretainedValue()
                if !owner.clearing { owner.toggleVisibility() }
            }
            return noErr
        }, 1, &spec, context, &hotKeyHandler)
        let registered = installed == noErr ? RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: 0x43534844, id: 1), GetApplicationEventTarget(), 0, &hotKey) : installed
        if registered != noErr {
            main.setStatus("⌘⇧Space is unavailable or already in use. Use the app menu to Show / Hide.")
            main.didFinish = { [weak self] in self?.main.setStatus("⌘⇧Space unavailable. Use the app menu to Show / Hide.") }
        }
    }
    private func installMenu() {
        let bar = NSMenu(); let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        for (title, action, key) in [("Show ChatGPT", #selector(showAll), "l"), ("Hide chat windows", #selector(hideAll), "h"),
                                     ("Clear local login…", #selector(clearLogin), ""), ("Quit CaptureShield", #selector(quit), "q")] {
            app.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
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
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}
