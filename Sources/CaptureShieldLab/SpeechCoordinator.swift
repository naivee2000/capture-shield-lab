import AppKit
import CaptureCore

@MainActor final class SpeechCoordinator {
    private weak var owner: ChatWindow?
    private let defaults: UserDefaults
    private let capture: any AudioCaptureProviding
    private let backend: any SpeechTranscriptionBackend
    private var state = SpeechSessionState()
    private var sources: [AudioSource] = []
    private var activeSource: AudioSource?
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var recognitionTimeout: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var context: String?
    private var token = UUID().uuidString
    private var transcript = ""
    private var insertionUncertain = false
    private var inserting = false
    private var refreshing = false
    private let limit: Duration
    private var capability = "not checked"
    private(set) var lastFailure: SpeechFailure?
    private var pane: SpeechPane? { owner?.speechPane }
    private var language: TranscriptionLanguage {
        let index = pane?.language.indexOfSelectedItem ?? 0
        return TranscriptionLanguage.allCases.indices.contains(index) ? TranscriptionLanguage.allCases[index] : .english
    }
    var diagnostic: String {
        "Speech: \(backend.name)\nSpeech language: \(language.rawValue); capability: \(capability)\nLast speech error: \(lastFailure?.diagnostic ?? "none")"
    }
    var phase: SpeechSessionState.Phase { state.phase }
    init(owner: ChatWindow, defaults: UserDefaults, capture: (any AudioCaptureProviding)? = nil,
         backend: (any SpeechTranscriptionBackend)? = nil, limit: Duration = .seconds(SpeechAudioPolicy.maximumSeconds)) {
        self.owner = owner; self.defaults = defaults
        self.capture = capture ?? AudioCaptureService(defaults: defaults); self.backend = backend ?? SpeechBackends.make(); self.limit = limit
        let saved = defaults.string(forKey: "SpeechLanguage").flatMap(TranscriptionLanguage.init(rawValue:)) ?? .english
        pane?.language.selectItem(at: TranscriptionLanguage.allCases.firstIndex(of: saved) ?? 0)
        pane?.recordAction = { [weak self] in self?.toggle() }
        pane?.prepareAction = { [weak self] in self?.prepareLanguage() }
        pane?.refreshAction = { [weak self] in self?.refreshSources() }
        pane?.addAction = { [weak self] in self?.addManually() }
        pane?.discardAction = { [weak self] in self?.cancel() }
        pane?.selectionAction = { [weak self] in self?.selectionChanged() }
        pane?.closeAction = { [weak owner] in owner?.showSpeechPane(false) }
        self.capture.failed = { [weak self] code in self?.interrupt(SpeechFailure(stage: .capture, code: code, message: "Audio capture was interrupted. Review any recovered text before adding it.")) }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification)
        observe(DistributedNotificationCenter.default(), NSNotification.Name("com.apple.screenIsLocked"))
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                guard let self, pid == self.activeSource?.pid else { return }
                self.interrupt(SpeechFailure(stage: .source, code: 2, message: "The audio source exited. Review any recovered text before adding it."))
            }
        }
        observers.append((center, observer)); render()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupt(SpeechFailure(stage: .capture, code: 3, message: "Recording stopped because this session locked, became inactive or went to sleep. It will not restart automatically.")) }
        }
        observers.append((center, observer))
    }
    func show() {
        owner?.showSpeechPane(true)
        if sources.isEmpty && state.phase == .idle { refreshSources() }
    }
    func toggle() {
        if state.phase == .recording { stop(); return }
        guard state.phase == .idle, !refreshing else { return }
        show()
        guard !sources.isEmpty else { owner?.present(); return }
        start()
    }
    private func selectionChanged() {
        guard state.phase == .idle else { return }
        capability = "not checked"
        defaults.set(language.rawValue, forKey: "SpeechLanguage")
        if let source = selectedSource { defaults.set(source.bundleID, forKey: "SpeechSourceBundleID") }
    }
    private var selectedSource: AudioSource? {
        pane?.selectedAudioSource
    }
    func refreshSources() {
        guard state.phase == .idle, !refreshing else { return }
        refreshing = true; render(); message("Reading audio applications…")
        let generation = state.generation
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.state.generation == generation { self.refreshing = false; self.render() } }
            do {
                let sources = try await self.capture.sources()
                try Task.checkCancellation(); guard self.state.generation == generation else { return }
                self.sources = sources
                let saved = self.defaults.string(forKey: "SpeechSourceBundleID")
                self.pane?.setSources(sources, savedBundle: saved)
                self.message("Choose the meeting application. Browser audio includes other tabs. Microphone is off.")
            } catch is CancellationError {} catch { if self.state.generation == generation { self.report(error, stage: .source) } }
        }
    }
    func prepareLanguage() {
        guard !refreshing, let generation = state.begin() else { return }
        let language = language
        message("Preparing on-device language… No audio is being recorded."); render()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.prepare(language, download: true) { [weak self] value in
                    guard let self, self.state.generation == generation else { return }
                    self.message("Preparing language: \(Int(value * 100))%. No audio is being recorded.")
                }
                try Task.checkCancellation(); guard self.state.generation == generation else { return }
                self.capability = "ready"; self.lastFailure = nil; self.message("On-device language is ready. Click Record when ready.")
            } catch is CancellationError {} catch { if self.state.generation == generation { self.capability = "unavailable"; self.report(error, stage: .model) } }
            if self.state.transition(.idle, generation: generation) { self.render() }
        }
    }
    private func start() {
        guard let source = selectedSource else { message("Select the meeting application before recording."); return }
        guard let owner, owner.window?.attachedSheet == nil, NSApp.modalWindow == nil,
              let generation = state.begin() else { return }
        let language = language
        activeSource = source; defaults.set(source.bundleID, forKey: "SpeechSourceBundleID")
        token = UUID().uuidString; lastFailure = nil; transcript = ""; insertionUncertain = false
        message("Checking audio and local language…"); render()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                self.context = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview)
                guard self.context != nil else { throw SpeechFailure(stage: .insertion, code: 1, message: "Open a ChatGPT chat before recording. Nothing was recorded.") }
                try await self.backend.prepare(language, download: false) { _ in }
                self.capability = "ready"
                try Task.checkCancellation()
                try await self.capture.start(source: source)
                guard self.state.generation == generation, !Task.isCancelled else { return }
                _ = self.state.transition(.recording, generation: generation)
                self.render()
                let clock = ContinuousClock(), start = ContinuousClock.now
                self.timer = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self, self.state.phase == .recording else { return }
                        let seconds = Int(start.duration(to: clock.now).components.seconds)
                        self.message("Recording \(source.name) · \(language.title) · \(seconds)/120 s · \(ChatKeyboard.recordLabel) stops")
                        if clock.now >= start.advanced(by: self.limit) { self.stop(); return }
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    }
                }
            } catch is CancellationError {} catch {
                if self.state.generation == generation {
                    _ = await self.capture.stop()
                    self.report(error, stage: .capture); _ = self.state.transition(.idle, generation: generation); self.render()
                }
            }
        }
    }
    private func interrupt(_ error: SpeechFailure) {
        if state.phase == .recording { stop(interruption: error) }
        else if state.phase == .preparing { cancel(); report(error, stage: error.stage) }
    }
    private func stop(interruption: SpeechFailure? = nil) {
        guard state.phase == .recording else { return }
        let generation = state.generation, language = language
        _ = state.transition(.transcribing, generation: generation); timer?.cancel(); timer = nil
        message(interruption?.message ?? "Transcribing on this Mac…"); render()
        operation = Task { [weak self] in
            guard let self else { return }
            let samples = await self.capture.stop()
            guard self.state.generation == generation, !Task.isCancelled else { return }
            self.recognitionTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                guard let self, self.state.phase == .transcribing else { return }
                self.backend.cancel(); self.operation?.cancel()
                self.report(SpeechFailure(stage: .recognition, code: 408, message: "Transcription timed out. Review any completed text."), stage: .recognition)
                _ = self.state.transition(.ready, generation: generation); self.render()
            }
            defer { self.recognitionTimeout?.cancel(); self.recognitionTimeout = nil }
            do {
                guard !samples.isEmpty, samples.contains(where: { abs($0) > 0.0001 }) else { throw SpeechFailure(stage: .capture, code: 4, message: "No audible samples arrived from this application. Check playback and the selected source.") }
                let text = try await self.backend.transcribe(samples, language: language) { [weak self] text in
                    guard let self, self.state.generation == generation else { return }
                    self.transcript = text; self.pane?.result.string = text
                }
                try Task.checkCancellation(); guard self.state.generation == generation else { return }
                self.transcript = text; self.pane?.result.string = text
                guard !text.isEmpty else { throw SpeechFailure(stage: .recognition, code: 4, message: "No speech was recognized. The draft was not changed.") }
                _ = self.state.transition(.ready, generation: generation); self.render()
                if let interruption { self.report(interruption, stage: interruption.stage) }
                else { await self.insert(manual: false) }
            } catch is CancellationError {} catch {
                if self.state.generation == generation { self.report(error, stage: .recognition); _ = self.state.transition(.ready, generation: generation); self.render() }
            }
        }
    }
    private func addManually() { Task { [weak self] in await self?.insert(manual: true) } }
    private func insert(manual: Bool) async {
        guard state.phase == .ready, !transcript.isEmpty, !inserting, !insertionUncertain, let owner else { return }
        inserting = true; render(); defer { inserting = false; render() }
        let generation = state.generation
        let target = manual ? await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview) : context
        guard let target else { message("Transcript retained. Open the intended chat, then click Add to Chat."); return }
        let outcome = await DraftInsertionBridge.append(transcript, token: token, context: target, owner: owner)
        guard generation == state.generation else { return }
        switch outcome {
        case .inserted:
            transcript = ""; pane?.result.string = ""; context = nil; state.reset()
            message("Transcript appended to your draft. Review it and send manually.")
        case .uncertain:
            insertionUncertain = true
            report(SpeechFailure(stage: .insertion, code: 2, message: "Insertion could not be confirmed. Check the draft before copying any missing text; automatic retry is disabled."), stage: .insertion)
        default: message("Transcript retained. Show the chat, finish any Chinese composition, and click Add to Chat when ready.")
        }
    }
    func cancel() {
        state.reset(); operation?.cancel(); operation = nil; timer?.cancel(); timer = nil
        recognitionTimeout?.cancel(); recognitionTimeout = nil; backend.cancel()
        refreshing = false; transcript = ""; context = nil; activeSource = nil; pane?.result.string = ""
        insertionUncertain = false
        let capture = capture
        // Await cleanup before accepting another start; otherwise an old stop can
        // race with the next recording's stream.
        refreshing = true; render()
        let generation = state.generation
        operation = Task { [weak self] in
            _ = await capture.stop()
            guard let self, self.state.generation == generation else { return }; self.refreshing = false; self.render()
            self.message("Cancelled. Audio and pending transcript were discarded.")
        }
    }
    func shutdown() {
        operation?.cancel(); timer?.cancel(); recognitionTimeout?.cancel(); backend.cancel()
        for (center, observer) in observers { center.removeObserver(observer) }; observers.removeAll()
        state.reset(); transcript = ""; pane?.result.string = ""
        let capture = capture; Task { _ = await capture.stop() }
    }
    private func render() {
        let idle = state.phase == .idle && !refreshing
        let recording = state.phase == .recording
        pane?.record.title = recording ? "Stop" : "Record"
        pane?.record.isEnabled = idle || recording
        pane?.source.isEnabled = idle; pane?.language.isEnabled = idle
        pane?.refresh.isEnabled = idle; pane?.prepare.isEnabled = idle
        pane?.add.isEnabled = state.phase == .ready && !transcript.isEmpty && !inserting && !insertionUncertain
        pane?.discard.isEnabled = !inserting
        owner?.updateRecordButton(recording: recording, enabled: idle || recording)
    }
    private func message(_ text: String) { pane?.status.stringValue = text; pane?.status.toolTip = text; owner?.setStatus(text) }
    private func report(_ error: any Error, stage: SpeechFailure.Stage) {
        let failure = error as? SpeechFailure ?? SpeechFailure(stage: stage, code: (error as NSError).code, message: "\(stage.rawValue.capitalized) failed (code \((error as NSError).code)). Nothing was sent. Review settings and try again manually.")
        lastFailure = failure; message(failure.message)
    }
}
