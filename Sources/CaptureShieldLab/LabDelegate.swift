import AppKit
import CaptureCore

@MainActor final class LabPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class DragBar: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
@MainActor final class ResizeGrip: NSView {
    private var startFrame: NSRect = .zero
    private var startMouse: NSPoint = .zero
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.setStroke()
        let path = NSBezierPath()
        for n in [6.0, 12.0, 18.0] {
            path.move(to: NSPoint(x: bounds.maxX - n, y: 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: n))
        }
        path.lineWidth = 1.5; path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        startFrame = window?.frame ?? .zero; startMouse = NSEvent.mouseLocation
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let width = max(480, startFrame.width + now.x - startMouse.x)
        let height = max(360, startFrame.height - now.y + startMouse.y)
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
}

@MainActor final class LabDelegate: NSObject, NSApplicationDelegate {
    private var panel: LabPanel!
    private var content: ShieldView!
    private var selector: NSSegmentedControl!
    private var status: NSTextField!
    private var timer: Timer?
    private var session: URL?
    private var revision = -1
    private var lastStateData: Data?
    private var mode: ProtectionMode = .ordinary
    private var validity = RunValidity()
    private var observers: [NSObjectProtocol] = []
    private var syntheticWeb: SyntheticWebContent?
    private var pasteMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--session"), args.indices.contains(index + 1) {
            session = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        }
        installMenu()
        pasteMonitor = PlainTextPaste.installMonitor()
        panel = LabPanel(contentRect: NSRect(x: 180, y: 200, width: 640, height: 440),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "CaptureShield Lab"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        content = ShieldView(frame: NSRect(origin: .zero, size: panel.frame.size))
        panel.contentView = content
        buildContent()
        apply(.ordinary)
        if session == nil { panel.center(); show() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.mode.usesMask else { return }
                    self.validity.interrupt("Display/session lifecycle changed. Quit and relaunch, then retest.")
                    self.content.failClosed(self.validity.failure!)
                    self.panel.orderOut(nil); self.writeState()
                }
            })
        }
    }

    private func buildContent() {
        let drag = DragBar()
        let brand = label("CAPTURE / SHIELD", size: 13, color: .systemTeal, weight: .bold)
        let usesWeb = CommandLine.arguments.contains("--web-test")
        let title = label(usesWeb ? "WebView protection lab" : "Window protection lab", size: 25, color: .white, weight: .semibold)
        let subtitle = label("Experimental · use synthetic text only", size: 12, color: .lightGray)
        selector = NSSegmentedControl(labels: ProtectionMode.allCases.map(\.title), trackingMode: .selectOne,
                                      target: self, action: #selector(changeMode(_:)))
        selector.selectedSegment = 0; selector.setAccessibilityLabel("Protection mode")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.scrollerStyle = .overlay
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false; editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 17, weight: .regular); editor.textColor = .white
        editor.backgroundColor = NSColor(srgbRed: 0.08, green: 0.12, blue: 0.21, alpha: 1)
        editor.textContainerInset = NSSize(width: 14, height: 14)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.string = "CAPTURE TEST — SYNTHETIC CONTENT\n\nType here to confirm local visibility and editing.\nThis window is experimental, not verified private.\n\nLook for the entire background in the receiver's view.\nA black rectangle is a failure."
        editor.setAccessibilityLabel("Synthetic test editor"); scroll.documentView = editor
        let testContent: NSView
        if usesWeb {
            let web = SyntheticWebContent(); syntheticWeb = web; testContent = web.view
        } else { testContent = scroll }
        status = label("Ordinary window · expected to appear in captures", size: 11, color: .lightGray)
        status.maximumNumberOfLines = 2
        let hide = NSButton(title: "Hide for 3 seconds", target: self, action: #selector(hideBriefly))
        let quit = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        let grip = ResizeGrip()
        for view in [drag, brand, title, subtitle, selector!, testContent, status!, hide, quit, grip] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: content.topAnchor), drag.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: content.trailingAnchor), drag.heightAnchor.constraint(equalToConstant: 100),
            brand.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), brand.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 7), title.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5), subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            selector.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 17),
            selector.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            selector.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            testContent.topAnchor.constraint(equalTo: selector.bottomAnchor, constant: 15), testContent.leadingAnchor.constraint(equalTo: selector.leadingAnchor),
            testContent.trailingAnchor.constraint(equalTo: selector.trailingAnchor), testContent.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: selector.leadingAnchor), status.trailingAnchor.constraint(equalTo: selector.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: hide.topAnchor, constant: -10),
            hide.leadingAnchor.constraint(equalTo: selector.leadingAnchor), hide.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -17),
            quit.leadingAnchor.constraint(equalTo: hide.trailingAnchor, constant: 12), quit.centerYAnchor.constraint(equalTo: hide.centerYAnchor),
            grip.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6), grip.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            grip.widthAnchor.constraint(equalToConstant: 26), grip.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
    private func label(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
        return field
    }
    private func installMenu() {
        let bar = NSMenu(); let item = NSMenuItem(); bar.addItem(item)
        let menu = NSMenu(); item.submenu = menu
        menu.addItem(withTitle: "Show Lab", action: #selector(show), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Hide Lab", action: #selector(hidePanel), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "Quit CaptureShield Lab", action: #selector(quitApp), keyEquivalent: "q").target = self
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit"); edit.submenu = editMenu; bar.addItem(edit)
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                       ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                       ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        NSApp.mainMenu = bar
    }
    @objc private func changeMode(_ sender: NSSegmentedControl) {
        apply(ProtectionMode.allCases[sender.selectedSegment]); show()
    }
    private func apply(_ next: ProtectionMode) {
        panel.orderOut(nil); mode = next
        guard validity.canConfigure(rendererHealthy: true) else {
            content.failClosed(validity.failure!); return
        }
        panel.sharingType = next == .legacy ? .none : .readOnly
        content.configure(next)
        selector.selectedSegment = ProtectionMode.allCases.firstIndex(of: next)!
        status.stringValue = "\(next.title) · renderer configured, capture protection UNVERIFIED"
    }
    @objc private func show() {
        guard content.healthError == nil else {
            let alert = NSAlert(); alert.messageText = "Lab content is hidden after a renderer failure."
            alert.informativeText = content.healthError ?? "Quit and relaunch to retry."
            alert.runModal(); return
        }
        panel.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    @objc private func hidePanel() { panel.orderOut(nil) }
    @objc private func hideBriefly() {
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.show() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    private func tick() {
        if !validity.mayContinue {
            content.failClosed(validity.failure!); panel.orderOut(nil); writeState(); return
        }
        if let session, let command = try? SessionIO.read(LabCommand.self, from: session.appendingPathComponent("command.json")),
           command.revision != revision {
            revision = command.revision
            if command.quit { NSApp.terminate(nil); return }
            panel.setFrame(command.frame, display: false); apply(command.mode)
            if command.visible && content.healthError == nil { panel.orderFrontRegardless() }
        }
        if let error = content.healthError ?? syntheticWeb?.error { content.failClosed(error); panel.orderOut(nil) }
        writeState()
    }
    private func writeState() {
        guard let session else { return }
        let state = LabState(revision: revision, mode: mode, visible: panel.isVisible,
                             ready: content.healthError == nil && (syntheticWeb?.ready ?? true),
                             windowNumber: panel.windowNumber, frame: panel.frame, error: content.healthError ?? syntheticWeb?.error)
        guard let data = try? JSONEncoder().encode(state), data != lastStateData else { return }
        do {
            try data.write(to: session.appendingPathComponent("state.json"), options: .atomic); lastStateData = data
        } catch {
            content.failClosed("Cannot publish test state: \(error.localizedDescription)"); panel.orderOut(nil)
        }
    }
}
