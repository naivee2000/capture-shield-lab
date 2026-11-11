import AppKit
import CaptureCore

@MainActor final class CheckerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let tile: CGFloat = 32
        for row in 0...Int(bounds.height / tile) {
            for col in 0...Int(bounds.width / tile) {
                let value: CGFloat = (row + col) % 2 == 0 ? 0.23 : 0.74
                NSColor(srgbRed: value, green: value, blue: value, alpha: 1).setFill()
                NSRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
    }
}

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var background: NSWindow?
    private var screens: NSPopUpButton!
    private var order: NSPopUpButton!
    private var surface: NSPopUpButton!
    private var candidate: NSPopUpButton!
    private var status: NSTextField!
    private var runningStatus: NSTextField?
    private var summary: NSTextView!
    private var start: NSButton!
    private var cursorRecordButton: NSButton!
    private var cursorRecorder: CursorRecorder?
    private var cursorStarting = false
    private var confirmYes: NSButton!
    private var confirmNo: NSButton!
    private var folder: NSButton!
    private var runner: ProbeRunner?
    private var task: Task<Void, Never>?
    private var tick: Timer?
    private var counter = 0
    private var output: URL!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--output"), args.indices.contains(i + 1) {
            output = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        } else {
            output = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CaptureShieldLab/Reports", isDirectory: true)
        }
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 790, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "CaptureProbe — independent verification"
        window.isReleasedWhenClosed = false
        let root = NSView(); window.contentView = root
        let title = label("Measure what gets captured.", size: 26, weight: .semibold)
        let detail = label("An independent full-display recorder. No application exclusions.\nUse synthetic text only. Close private windows on the selected display.\nLocal captures do not establish Zoom, Meet or Teams compatibility.", size: 13)
        detail.maximumNumberOfLines = 3
        screens = NSPopUpButton(); screens.setAccessibilityLabel("Test display")
        for (i, screen) in NSScreen.screens.enumerated() {
            screens.addItem(withTitle: "\(i + 1). \(screen.localizedName) — \(Int(screen.frame.width)) × \(Int(screen.frame.height))")
            screens.lastItem?.representedObject = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        }
        order = NSPopUpButton(); order.setAccessibilityLabel("Capture order")
        order.addItems(withTitles: ["Capture starts before the window appears", "Window appears before capture starts"])
        surface = NSPopUpButton(); surface.setAccessibilityLabel("Test content")
        surface.addItems(withTitles: ["Synthetic WebView", "Native text editor"])
        candidate = NSPopUpButton(); candidate.setAccessibilityLabel("Local confirmation mode")
        candidate.addItems(withTitles: ["Legacy sharing", "Protected mask"])
        candidate.target = self; candidate.action = #selector(selectCandidate); candidate.isEnabled = false
        cursorRecordButton = NSButton(title: "Record full display + cursor", target: self, action: #selector(toggleCursorRecording))
        cursorRecordButton.toolTip = "Manual synthetic test only. Includes everything on this display, system cursor on, audio off. Stops after 2 minutes."
        start = NSButton(title: "Start capture test", target: self, action: #selector(startRun))
        start.bezelStyle = .rounded; start.keyEquivalent = "\r"
        status = label("Ready. Screen Recording permission is requested only when you start.", size: 12)
        status.maximumNumberOfLines = 3
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        summary = NSTextView(); summary.isEditable = false
        summary.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        summary.textContainerInset = NSSize(width: 12, height: 12)
        summary.autoresizingMask = [.width]; summary.textContainer?.widthTracksTextView = true
        summary.string = "Results appear here.\n\nPASS requires captured background to match AND a person to confirm that the protected window is locally visible and editable.\n\nA black rectangle is FAIL.\nMissing controls or permissions are NOT TESTED.\n\nReports and cropped evidence stay on this Mac."
        scroll.documentView = summary
        confirmYes = NSButton(title: "I can see AND type", target: self, action: #selector(confirmVisible))
        confirmNo = NSButton(title: "Cannot see / type", target: self, action: #selector(confirmInvisible))
        confirmYes.isEnabled = false; confirmNo.isEnabled = false
        folder = NSButton(title: "Open report folder", target: self, action: #selector(openFolder)); folder.isEnabled = false
        for view in [title, detail, screens!, order!, surface!, cursorRecordButton!, candidate!, start!, status!, scroll, confirmYes!, confirmNo!, folder!] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10), detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            screens.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 18), screens.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            screens.widthAnchor.constraint(equalToConstant: 320), order.leadingAnchor.constraint(equalTo: screens.trailingAnchor, constant: 12),
            order.centerYAnchor.constraint(equalTo: screens.centerYAnchor), order.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            surface.topAnchor.constraint(equalTo: screens.bottomAnchor, constant: 12), surface.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            cursorRecordButton.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            cursorRecordButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            start.topAnchor.constraint(equalTo: surface.bottomAnchor, constant: 12), start.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.leadingAnchor.constraint(equalTo: start.trailingAnchor, constant: 16), status.centerYAnchor.constraint(equalTo: start.centerYAnchor),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            scroll.topAnchor.constraint(equalTo: start.bottomAnchor, constant: 18), scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26), scroll.bottomAnchor.constraint(equalTo: confirmYes.topAnchor, constant: -14),
            candidate.leadingAnchor.constraint(equalTo: title.leadingAnchor), candidate.centerYAnchor.constraint(equalTo: confirmYes.centerYAnchor),
            confirmYes.leadingAnchor.constraint(equalTo: candidate.trailingAnchor, constant: 12), confirmYes.bottomAnchor.constraint(equalTo: folder.topAnchor, constant: -12),
            confirmNo.leadingAnchor.constraint(equalTo: confirmYes.trailingAnchor, constant: 12), confirmNo.centerYAnchor.constraint(equalTo: confirmYes.centerYAnchor),
            folder.leadingAnchor.constraint(equalTo: title.leadingAnchor), folder.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        if args.contains("--auto-run") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startRun() }
        }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }
    private func installMenu() {
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
        let sub = NSMenu(); item.submenu = sub
        sub.addItem(withTitle: "Show results", action: #selector(showResults), keyEquivalent: "r").target = self
        sub.addItem(withTitle: "Cancel test", action: #selector(cancelRun), keyEquivalent: ".").target = self
        sub.addItem(withTitle: "Stop cursor recording", action: #selector(stopCursorRecording), keyEquivalent: "").target = self
        sub.addItem(withTitle: "Quit CaptureProbe", action: #selector(quitApp), keyEquivalent: "q").target = self
        NSApp.mainMenu = menu
    }
    @objc private func toggleCursorRecording() {
        guard task == nil, !cursorStarting else { return }
        if cursorRecorder != nil { stopCursorRecording(); return }
        guard let id = (screens.selectedItem?.representedObject as? NSNumber)?.uint32Value else { return }
        let alert = NSAlert(); alert.messageText = "Record the entire display with its cursor?"
        alert.informativeText = "Use only synthetic content and close private windows. Everything on the selected display is recorded locally for up to 2 minutes. No audio or upload. This does not certify Teams."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Record")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn, self.task == nil, self.cursorRecorder == nil else { return }
            self.cursorStarting = true; self.start.isEnabled = false; self.cursorRecordButton.isEnabled = false
            Task { @MainActor in
                let recorder = CursorRecorder()
                recorder.stopped = { [weak self] message in
                    guard let self else { return }
                    self.cursorRecorder = nil; self.cursorStarting = false; self.start.isEnabled = true
                    self.cursorRecordButton.isEnabled = true; self.cursorRecordButton.title = "Record full display + cursor"
                    self.status.stringValue = message; self.folder.isEnabled = true
                }
                do {
                    self.cursorRecorder = recorder
                    try await recorder.start(displayID: id, output: self.output)
                    self.cursorStarting = false; self.cursorRecordButton.isEnabled = true
                    self.cursorRecordButton.title = "Stop cursor recording"
                    self.status.stringValue = "Recording entire display + system cursor. Use --chat-preview with synthetic content. Stop here or in the app menu."
                } catch {
                    self.cursorRecorder = nil; self.cursorStarting = false; self.start.isEnabled = true; self.cursorRecordButton.isEnabled = true
                    self.status.stringValue = "Could not start cursor recording. Check CaptureProbe's screen recording permission."
                }
            }
        }
    }
    @objc private func stopCursorRecording() {
        guard !cursorStarting, let recorder = cursorRecorder else { return }
        cursorRecordButton.isEnabled = false
        Task { await recorder.stop() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recorder = cursorRecorder else { return .terminateNow }
        Task { await recorder.stop(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    @objc private func startRun() {
        guard task == nil, cursorRecorder == nil, !cursorStarting else { return }
        let currentScreens = NSScreen.screens
        let currentIDs = currentScreens.map { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
        guard let selectedID = (screens.selectedItem?.representedObject as? NSNumber)?.uint32Value,
              let screenIndex = EvidenceGate.displayIndex(id: selectedID, currentIDs: currentIDs) else {
            status.stringValue = "Selected display was disconnected. Relaunch CaptureProbe and select the display again."; return
        }
        runner?.stopLab(); background?.close(); tick?.invalidate()
        confirmYes.isEnabled = false; confirmNo.isEnabled = false; candidate.isEnabled = false
        do {
            let screen = currentScreens[screenIndex]
            let next = try ProbeRunner(screen: screen, output: output, captureFirst: order.indexOfSelectedItem == 0,
                                       web: surface.indexOfSelectedItem == 0)
            runner = next
            next.progress = { [weak self] message in self?.status.stringValue = message; self?.runningStatus?.stringValue = message }
            showBackground(on: screen)
            start.isEnabled = false; cursorRecordButton.isEnabled = false; window.orderOut(nil)
            task = Task { [weak self] in
                await next.run()
                guard let self else { return }
                self.task = nil; self.start.isEnabled = true; self.cursorRecordButton.isEnabled = true; self.folder.isEnabled = true
                self.tick?.invalidate()
                self.confirmYes.isEnabled = next.report.error == nil
                self.confirmNo.isEnabled = next.report.error == nil
                self.candidate.selectItem(at: 0); self.candidate.isEnabled = next.report.error == nil
                self.refreshSummary()
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        } catch { status.stringValue = error.localizedDescription }
    }
    private func showBackground(on screen: NSScreen) {
        let board = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        board.isReleasedWhenClosed = false; board.hasShadow = false
        board.title = "CaptureProbe synthetic background"
        let view = CheckerView(frame: NSRect(origin: .zero, size: screen.frame.size)); board.contentView = view
        let banner = NSView(); banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor.black.cgColor
        let headline = label("CAPTUREPROBE / SYNTHETIC TEST DISPLAY", size: 18, weight: .bold); headline.textColor = .white
        let text = label("Starting…", size: 13); text.textColor = .white; text.maximumNumberOfLines = 2; runningStatus = text
        let cancel = NSButton(title: "Cancel / return to results", target: self, action: #selector(cancelRun))
        for child in [banner, headline, text, cancel] { child.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(banner); banner.addSubview(headline); banner.addSubview(text); banner.addSubview(cancel)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.topAnchor, constant: 28), banner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), banner.heightAnchor.constraint(equalToConstant: 100),
            headline.topAnchor.constraint(equalTo: banner.topAnchor, constant: 16), headline.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            text.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 8), text.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -14),
            cancel.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -20), cancel.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
        background = board; board.orderFrontRegardless()
        counter = 0
        tick = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak headline] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.counter += 1
                headline?.stringValue = "CAPTUREPROBE / SYNTHETIC TEST DISPLAY · \(self.counter)"
            }
        }
    }
    private func refreshSummary() {
        guard let runner, let text = try? String(contentsOf: runner.directory.appendingPathComponent("report.md"), encoding: .utf8) else { return }
        summary.string = text
    }
    @objc private func confirmVisible() { confirm(true) }
    @objc private func confirmInvisible() { confirm(false) }
    @objc private func selectCandidate() {
        guard task == nil, let runner else { return }
        let mode: ProtectionMode = candidate.indexOfSelectedItem == 0 ? .legacy : .protectedMask
        confirmYes.isEnabled = false; confirmNo.isEnabled = false; start.isEnabled = false; candidate.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.start.isEnabled = true; self.candidate.isEnabled = true }
            do {
                try await runner.previewCandidate(mode)
                self.status.stringValue = "Inspect \(mode.title) on the actual local screen, then confirm visibility and typing."
                self.confirmYes.isEnabled = true; self.confirmNo.isEnabled = true
            } catch { self.status.stringValue = error.localizedDescription }
        }
    }
    private func confirm(_ value: Bool) {
        do {
            try runner?.confirmLocal(value, mode: candidate.indexOfSelectedItem == 0 ? .legacy : .protectedMask); refreshSummary()
            status.stringValue = "Local observation recorded. Meeting compatibility remains untested."
            confirmYes.isEnabled = false; confirmNo.isEnabled = false
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func openFolder() {
        if let runner { NSWorkspace.shared.open(runner.directory) }
    }
    @objc private func showResults() { window.makeKeyAndOrderFront(nil) }
    @objc private func cancelRun() {
        task?.cancel(); runner?.stopLab(); background?.close(); tick?.invalidate(); showResults()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        task?.cancel(); runner?.stopLab(); tick?.invalidate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
