import AppKit
import CaptureCore

/// Native owned sheet; no web content or account access is required for diagnostics.
@MainActor final class CompatibilityPanel: NSObject {
    let window: NSWindow
    private let summary = NSTextView(frame: NSRect(x: 0, y: 0, width: 530, height: 260))
    private let scroll = NSScrollView()
    private let checkPage: () async -> Void
    private let check = NSButton(title: "Check page compatibility", target: nil, action: nil)
    private let mode = NSPopUpButton()
    private let snapshot: () -> CompatibilitySummary
    private let selectMode: (ScreenshotMode) -> Void
    private let didClose: () -> Void
    init(snapshot: @escaping () -> CompatibilitySummary, selectMode: @escaping (ScreenshotMode) -> Void,
         checkPage: @escaping () async -> Void,
         didClose: @escaping () -> Void) {
        self.snapshot = snapshot; self.selectMode = selectMode; self.checkPage = checkPage; self.didClose = didClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Compatibility"; window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        super.init()
        summary.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        summary.isEditable = false; summary.isSelectable = true; summary.drawsBackground = false
        summary.isHorizontallyResizable = false; summary.isVerticallyResizable = true
        summary.autoresizingMask = [.width]
        summary.textContainer?.widthTracksTextView = true
        summary.textContainer?.containerSize = NSSize(width: 530, height: CGFloat.greatestFiniteMagnitude)
        summary.setAccessibilityLabel("Compatibility summary")
        summary.setAccessibilityIdentifier("compatibility-summary")
        scroll.documentView = summary; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        check.target = self; check.action = #selector(checkCurrentPage)
        check.setAccessibilityIdentifier("check-page-compatibility")
        mode.addItems(withTitles: ScreenshotMode.allCases.map(\.title)); mode.target = self; mode.action = #selector(change)
        mode.setAccessibilityLabel("Screenshot method")
        let picker = NSStackView(views: [NSTextField(labelWithString: "Screenshot method:"), mode]); picker.spacing = 12
        let note = NSTextField(wrappingLabelWithString: "Compatible uses the earlier screenshot API. Changing this setting does not capture, upload, reload the chat or change Legacy mode.")
        let copy = NSButton(title: "Copy diagnostic summary", target: self, action: #selector(copySummary))
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(reload))
        let close = NSButton(title: "Done", target: self, action: #selector(done)); close.keyEquivalent = "\r"
        let buttons = NSStackView(views: [copy, refresh, close]); buttons.spacing = 12
        let stack = NSStackView(views: [picker, check, scroll, note, buttons]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)])
        reload()
    }
    @objc func reload() {
        let value = snapshot(); summary.string = value.text
        mode.selectItem(at: ScreenshotMode.allCases.firstIndex(of: value.mode) ?? 0)
    }
    @objc private func checkCurrentPage() {
        guard check.isEnabled else { return }
        check.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            await self.checkPage(); self.reload(); self.check.isEnabled = true
        }
    }
    @objc private func change() {
        guard ScreenshotMode.allCases.indices.contains(mode.indexOfSelectedItem) else { return }
        selectMode(ScreenshotMode.allCases[mode.indexOfSelectedItem]); reload()
    }
    @objc private func copySummary() {
        let board = NSPasteboard.general; board.clearContents(); board.setString(snapshot().text, forType: .string)
    }
    @objc private func done() {
        window.sheetParent?.endSheet(window); window.orderOut(nil); didClose()
    }
}
