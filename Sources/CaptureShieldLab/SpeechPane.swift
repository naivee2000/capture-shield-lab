import AppKit
import CaptureCore

@MainActor final class SpeechPane: NSView {
    let source = NSPopUpButton()
    let language = NSPopUpButton()
    let status = NSTextField(wrappingLabelWithString: "Choose an audio source. Browser audio may include other tabs. Microphone is off.")
    let result = NSTextView()
    let record = NSButton(title: "Record", target: nil, action: nil)
    let prepare = NSButton(title: "Prepare language", target: nil, action: nil)
    let refresh = NSButton(title: "Refresh sources", target: nil, action: nil)
    let add = NSButton(title: "Add to Chat", target: nil, action: nil)
    let discard = NSButton(title: "Cancel / Discard", target: nil, action: nil)
    var recordAction: (() -> Void)?
    var prepareAction: (() -> Void)?
    var refreshAction: (() -> Void)?
    var addAction: (() -> Void)?
    var discardAction: (() -> Void)?
    var selectionAction: (() -> Void)?
    var closeAction: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        language.addItems(withTitles: TranscriptionLanguage.allCases.map(\.title))
        source.setAccessibilityLabel("Audio source application"); language.setAccessibilityLabel("Transcription language")
        source.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        for picker in [source, language] { picker.target = self; picker.action = #selector(selectionChanged) }
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close transcription panel")!, target: self, action: #selector(closePanel))
        let row = NSStackView(views: [source, language, refresh, prepare, close]); row.spacing = 6
        let buttons = NSStackView(views: [record, add, discard]); buttons.spacing = 8
        record.target = self; record.action = #selector(recordClicked)
        prepare.target = self; prepare.action = #selector(prepareClicked)
        refresh.target = self; refresh.action = #selector(refreshClicked)
        add.target = self; add.action = #selector(addClicked)
        discard.target = self; discard.action = #selector(discardClicked)
        status.font = .systemFont(ofSize: 11); status.maximumNumberOfLines = 2
        status.setAccessibilityLabel("Transcription status")
        result.isEditable = false; result.isSelectable = true; result.font = .systemFont(ofSize: 12)
        result.setAccessibilityLabel("Local transcript")
        result.isAutomaticSpellingCorrectionEnabled = false; result.isAutomaticTextReplacementEnabled = false
        let scroll = NSScrollView(); scroll.documentView = result; scroll.hasVerticalScroller = true
        result.isVerticallyResizable = true; result.autoresizingMask = [.width]; result.textContainer?.widthTracksTextView = true
        let stack = NSStackView(views: [row, status, scroll, buttons]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(equalToConstant: 60)])
        add.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var selectedAudioSource: AudioSource? { source.selectedItem?.representedObject as? AudioSource }
    func setSources(_ sources: [AudioSource], savedBundle: String?) {
        // NSPopUpButton.addItems(withTitles:) coalesces duplicate titles. Never
        // map its selected index back to SCShareableContent's uncoalesced list.
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
