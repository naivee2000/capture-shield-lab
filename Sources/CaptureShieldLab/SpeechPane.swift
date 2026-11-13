import AppKit
import CaptureCore

@MainActor final class SpeechPane: NSView, NSTextViewDelegate {
    static let compactHeight: CGFloat = 36
    let source = NSPopUpButton()
    let language = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "Choose an audio source. Browser audio may include other tabs. Microphone is off.")
    let result = NSTextView()
    let record = NSButton(title: "Record", target: nil, action: nil)
    let prepare = NSButton(title: "Prepare language", target: nil, action: nil)
    let refresh = NSButton(title: "", target: nil, action: nil)
    let add = NSButton(title: "Add to Chat", target: nil, action: nil)
    let discard = NSButton(title: "Cancel", target: nil, action: nil)
    let review = NSButton(title: "Review transcript", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "Ready")
    private let clock = NSTextField(labelWithString: "00:00 / 02:00")
    private let settings = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Audio settings")!, target: nil, action: nil)
    private let details = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Transcription details")!, target: nil, action: nil)
    private let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close transcription panel")!, target: nil, action: nil)
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var settingsRow: NSStackView!
    private var resultButtons: NSStackView!
    private var editorHeight: NSLayoutConstraint!
    private var phase: SpeechSessionState.Phase = .idle
    private var busy = false
    private var error = false
    private var sourceName = ""
    private(set) var settingsExpanded = false
    private(set) var transcriptExpanded = false
    private(set) var detailsExpanded = false
    private(set) var preferredHeight: CGFloat = compactHeight
    var recordAction: (() -> Void)?
    var prepareAction: (() -> Void)?
    var refreshAction: (() -> Void)?
    var addAction: (() -> Void)?
    var discardAction: (() -> Void)?
    var selectionAction: (() -> Void)?
    var closeAction: (() -> Void)?
    var editAction: ((String) -> Void)?
    var heightChanged: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        language.addItems(withTitles: TranscriptionLanguage.allCases.map(\.title))
        source.setAccessibilityLabel("Audio source application"); language.setAccessibilityLabel("Transcription language")
        source.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
        source.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for picker in [source, language] { picker.target = self; picker.action = #selector(selectionChanged) }
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh sources")
        refresh.setAccessibilityLabel("Refresh sources"); refresh.toolTip = "Refresh audio applications"
        let bindings: [(NSButton, Selector)] = [(record, #selector(recordClicked)), (prepare, #selector(prepareClicked)),
            (refresh, #selector(refreshClicked)), (add, #selector(addClicked)), (discard, #selector(discardClicked)),
            (review, #selector(toggleTranscript)), (settings, #selector(toggleSettings)), (details, #selector(toggleDetails)), (close, #selector(closePanel))]
        for (button, action) in bindings { button.target = self; button.action = action }
        for control in [source, language, refresh, prepare, close, record, add, discard, review, settings, details] as [NSControl] {
            control.controlSize = .small; control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        source.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [summary, clock] { label.font = .systemFont(ofSize: 12) }
        summary.lineBreakMode = .byTruncatingMiddle
        summary.setContentHuggingPriority(.defaultLow, for: .horizontal)
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        clock.setContentCompressionResistancePriority(.required, for: .horizontal)
        clock.setAccessibilityLabel("Recording elapsed time")
        let row = NSStackView(views: [record, summary, clock, review, discard, settings, details, close]); row.spacing = 6
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        settingsRow = NSStackView(views: [source, language, refresh, prepare]); settingsRow.spacing = 8
        status.font = .systemFont(ofSize: 12); status.maximumNumberOfLines = 3
        status.setAccessibilityLabel("Transcription details")
        result.isEditable = false; result.isSelectable = true; result.font = .systemFont(ofSize: 13)
        result.isRichText = false; result.importsGraphics = false; result.allowsUndo = true
        result.setAccessibilityLabel("Local transcript"); result.delegate = self
        result.drawsBackground = false
        result.isAutomaticSpellingCorrectionEnabled = false; result.isAutomaticTextReplacementEnabled = false
        scroll.documentView = result; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.borderType = .lineBorder
        result.isVerticallyResizable = true; result.autoresizingMask = [.width]; result.textContainer?.widthTracksTextView = true
        resultButtons = NSStackView(views: [add]); resultButtons.spacing = 8
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        [row, settingsRow!, status, scroll, resultButtons!].forEach { stack.addArrangedSubview($0) }
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            settingsRow.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        editorHeight = scroll.heightAnchor.constraint(equalToConstant: 96); editorHeight.isActive = true
        add.isEnabled = false; refreshLayout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(phase: SpeechSessionState.Phase, busy: Bool, inserting: Bool, uncertain: Bool, sourceName: String?) {
        self.phase = phase; self.busy = busy; self.sourceName = sourceName ?? selectedAudioSource?.name ?? "Choose source"
        let idle = phase == .idle && !busy
        let recording = phase == .recording
        record.title = recording ? "Stop" : "Record"; record.isEnabled = idle || recording
        source.isEnabled = idle; language.isEnabled = idle; refresh.isEnabled = idle; prepare.isEnabled = idle
        let editable = phase == .ready && !inserting
        if result.isEditable != editable { result.isEditable = editable }
        add.isEnabled = phase == .ready && !result.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !inserting && !uncertain
        discard.isEnabled = !inserting
        discard.title = phase == .ready ? "Discard" : "Cancel"
        if result.string.isEmpty { transcriptExpanded = false }
        if phase != .idle { settingsExpanded = false }
        switch phase {
        case .idle: summary.stringValue = busy ? "Preparing…" : (error ? "Needs attention" : "Ready · \(self.sourceName)")
        case .preparing: summary.stringValue = "Preparing · \(self.sourceName)"
        case .recording: summary.stringValue = "Recording · \(self.sourceName)"
        case .transcribing: summary.stringValue = "Transcribing on this Mac…"
        case .ready: summary.stringValue = inserting ? "Adding to draft…" : (error ? "Review required" : "Transcript retained")
        }
        summary.toolTip = self.sourceName + " · " + (language.titleOfSelectedItem ?? "")
        refreshLayout()
    }
    func showMessage(_ text: String, error: Bool = false) {
        self.error = error; status.stringValue = text; details.toolTip = text
        details.image = NSImage(systemSymbolName: error ? "exclamationmark.circle" : "info.circle", accessibilityDescription: "Transcription details")
        if phase == .idle { summary.stringValue = busy ? "Preparing…" : (error ? "Needs attention" : "Ready · \(sourceName)") }
        if error && phase == .ready { summary.stringValue = "Review required" }
        if phase == .preparing { summary.stringValue = String(text.split(separator: ".").first ?? Substring(text)) }
        refreshLayout()
    }
    func setElapsed(_ seconds: Int) {
        clock.stringValue = String(format: "%02d:%02d / 02:00", seconds / 60, seconds % 60)
    }
    func setTranscript(_ text: String) {
        // No assignment while editing unless the content actually changed.
        if result.string != text { result.string = text; result.undoManager?.removeAllActions() }
        if text.isEmpty { transcriptExpanded = false }
        refreshLayout()
    }
    func textDidChange(_ notification: Notification) {
        guard result.isEditable else { return }
        editAction?(result.string)
    }
    func resizeForContentHeight(_ height: CGFloat) {
        let next = min(120, max(48, height * 0.25))
        if editorHeight.constant != next { editorHeight.constant = next; refreshLayout() }
    }
    private func refreshLayout() {
        let pending = !result.string.isEmpty
        clock.isHidden = phase != .recording
        review.isHidden = !pending
        review.title = transcriptExpanded ? "Hide transcript" : "Review transcript"
        discard.isHidden = phase == .idle && !busy && !pending
        settings.isEnabled = phase == .idle && !busy
        settingsRow.isHidden = !settingsExpanded
        status.isHidden = !detailsExpanded
        scroll.isHidden = !transcriptExpanded
        resultButtons.isHidden = !transcriptExpanded
        settings.toolTip = settingsExpanded ? "Close audio settings" : "Audio source, language and preparation"
        let next = Self.compactHeight + (settingsExpanded ? 32 : 0) + (detailsExpanded ? 56 : 0)
            + (transcriptExpanded ? editorHeight.constant + 32 : 0)
        if preferredHeight != next { preferredHeight = next; heightChanged?() }
    }
    @objc func toggleSettings() {
        settingsExpanded.toggle(); transcriptExpanded = false; detailsExpanded = false; refreshLayout()
    }
    @objc func toggleTranscript() {
        guard !result.string.isEmpty else { return }
        transcriptExpanded.toggle(); settingsExpanded = false; detailsExpanded = false; refreshLayout()
    }
    @objc private func toggleDetails() {
        detailsExpanded.toggle(); settingsExpanded = false; transcriptExpanded = false; refreshLayout()
    }
    var selectedAudioSource: AudioSource? { source.selectedItem?.representedObject as? AudioSource }
    func setSources(_ sources: [AudioSource], savedBundle: String?) {
        let counts = Dictionary(grouping: sources, by: \.name).mapValues(\.count)
        let menu = NSMenu()
        for audio in sources {
            let title = audio.name + ((counts[audio.name] ?? 0) > 1 ? " (PID \(audio.pid))" : "")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = audio; menu.addItem(item)
        }
        source.menu = menu
        if let item = menu.items.first(where: { ($0.representedObject as? AudioSource)?.bundleID == savedBundle }) { source.select(item) }
        else { source.select(nil) }
    }
    @objc private func recordClicked() { recordAction?() }
    @objc private func prepareClicked() { prepareAction?() }
    @objc private func refreshClicked() { refreshAction?() }
    @objc private func addClicked() { addAction?() }
    @objc private func discardClicked() { discardAction?() }
    @objc private func selectionChanged() { selectionAction?() }
    @objc private func closePanel() { closeAction?() }
}
