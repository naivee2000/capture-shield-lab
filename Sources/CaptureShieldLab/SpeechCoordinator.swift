import AppKit
import CaptureCore

struct SpeechDeadlines {
    var preparation: Duration = .seconds(30)
    var cleanup: Duration = .seconds(10)
    var recognition: Duration = .seconds(180)
    var insertion: Duration = .seconds(10)
}

@MainActor final class SpeechCoordinator {
    private final class Session {
        let generation: Int
        let language: TranscriptionLanguage
        let hadPending: Bool
        var captureStatus = "not started"
        var source: AudioSource?
        var context: String?
        var partial = ""
        var failure: SpeechFailure?
        var retiring = false
        var retainPartial = false
        var operation: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        var cleanup: Task<Void, Never>?
        init(generation: Int, language: TranscriptionLanguage, hadPending: Bool) {
            self.generation = generation; self.language = language; self.hadPending = hadPending
        }
    }
    typealias Insertion = @MainActor (String, String, String, ChatWindow, @escaping @MainActor () -> Bool) async -> DraftInsertionBridge.Outcome
    private weak var owner: ChatWindow?
    private let defaults: UserDefaults
    private let capture: any AudioCaptureProviding
    private let backend: any SpeechTranscriptionBackend
    private let insertion: Insertion
    private let deadlines: SpeechDeadlines
    private let limit: Duration
    private var state = SpeechSessionState()
    private var session: Session?
    private var sources: [AudioSource] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var buffer = SpeechTranscriptBuffer()
    private var selectedReview: String?
    private var delivery: SpeechTranscriptBuffer.Delivery?
    private var deliveryTask: Task<Void, Never>?
    private var deliveryDeadline: Task<Void, Never>?
    private var stopped = false
    private var capability = "not checked"
    private(set) var lastFailure: SpeechFailure?
    private var pane: SpeechPane? { owner?.speechPane }
    private var language: TranscriptionLanguage {
        let index = pane?.language.indexOfSelectedItem ?? 0
        return TranscriptionLanguage.allCases.indices.contains(index) ? TranscriptionLanguage.allCases[index] : .english
    }
    private var idle: Bool { state.phase == .idle && !stopped }
    var canRecord: Bool { idle || state.phase == .recording }
    var phase: SpeechSessionState.Phase {
        idle && (buffer.hasText || !buffer.uncertain.isEmpty) ? .ready : state.phase
    }
    var diagnostic: String {
        "Speech: \(backend.name)\nSpeech language: \(language.rawValue); capability: \(capability)\nSpeech phase: \(state.phase.rawValue); available: \(canRecord); capture: \(session?.captureStatus ?? "ended")\nPending text: \(buffer.hasText); uncertain delivery: \(!buffer.uncertain.isEmpty)\nLast speech error: \(lastFailure?.diagnostic ?? "none")"
    }
    init(owner: ChatWindow, defaults: UserDefaults, capture: (any AudioCaptureProviding)? = nil,
         backend: (any SpeechTranscriptionBackend)? = nil, limit: Duration = .seconds(SpeechAudioPolicy.maximumSeconds),
         deadlines: SpeechDeadlines = .init(), insertion: Insertion? = nil) {
        self.owner = owner; self.defaults = defaults
        self.capture = capture ?? AudioCaptureService(defaults: defaults); self.backend = backend ?? SpeechBackends.make()
        self.limit = limit; self.deadlines = deadlines
        self.insertion = insertion ?? { text, token, context, owner, valid in
            await DraftInsertionBridge.append(text, token: token, context: context, owner: owner, isCurrent: valid)
        }
        let saved = defaults.string(forKey: "SpeechLanguage").flatMap(TranscriptionLanguage.init(rawValue:)) ?? .english
        pane?.language.selectItem(at: TranscriptionLanguage.allCases.firstIndex(of: saved) ?? 0)
        pane?.recordAction = { [weak self] in self?.toggle() }
        pane?.prepareAction = { [weak self] in self?.prepareLanguage() }
        pane?.refreshAction = { [weak self] in self?.refreshSources() }
        pane?.addAction = { [weak self] in self?.insert(manual: true, context: nil) }
        pane?.discardAction = { [weak self] in
            guard let self else { return }
            if self.state.phase == .blocked { self.retryRecovery() }
            else if !self.idle { self.cancel() }
            else { self.discardSelected() }
        }
        pane?.reviewSelectionAction = { [weak self] id in self?.selectedReview = id; self?.render() }
        pane?.selectionAction = { [weak self] in self?.selectionChanged() }
        pane?.editAction = { [weak self] text in
            guard let self, self.selectedReview == nil, self.delivery == nil, self.pane?.result.isEditable == true else { return }
            self.buffer.edit(text); self.render()
        }
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
                guard let self, pid == self.session?.source?.pid else { return }
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
        if sources.isEmpty && idle { refreshSources() }
    }
    func toggle() {
        if state.phase == .recording { stop(); return }
        guard idle else { owner?.showSpeechPane(true); message(busyReason); return }
        show()
        guard idle, !sources.isEmpty else { return }
        start()
    }
    private var busyReason: String {
        switch state.phase {
        case .stopping, .recovering, .blocked: "Waiting for the previous capture to end. Use Retry recovery if available; recording is blocked until cleanup is confirmed."
        case .transcribing: "Finishing the previous transcription. Wait, or Cancel this segment. Earlier text is retained."
        case .inserting: "Checking the draft insertion. Another recording is available when this check finishes."
        default: "Preparing the current operation. Wait or Cancel; another recording is not queued."
        }
    }
    private func selectionChanged() {
        guard idle else { return }
        capability = "not checked"
        defaults.set(language.rawValue, forKey: "SpeechLanguage")
        if let source = pane?.selectedAudioSource { defaults.set(source.bundleID, forKey: "SpeechSourceBundleID") }
        render()
    }
    private func begin() -> Session? {
        guard idle, let generation = state.begin() else { return nil }
        let value = Session(generation: generation, language: language, hadPending: buffer.hasText || !buffer.uncertain.isEmpty)
        session = value; lastFailure = nil; return value
    }
    private func current(_ value: Session) -> Bool { session === value && !value.retiring && !stopped }
    private func transition(_ phase: SpeechSessionState.Phase, _ value: Session) {
        guard session === value else { return }
        _ = state.transition(phase, generation: value.generation); render()
    }
    private func deadline(_ value: Session, after delay: Duration, stage: SpeechFailure.Stage) {
        value.deadline?.cancel()
        value.deadline = Task { [weak self, weak value] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, let value, self.session === value else { return }
            let failure = SpeechFailure(stage: stage, code: 408, message: value.retiring
                ? "Cleanup has not finished. Recording stays blocked. Retry recovery; if it still cannot finish, preserve pending text before restarting the app."
                : "\(stage.rawValue.capitalized) timed out. Recovering resources; completed text is retained for review.")
            if value.retiring { self.transition(.blocked, value); self.report(failure) }
            else { self.recover(value, failure: failure, retainPartial: true) }
        }
    }
    func refreshSources() {
        guard let value = begin() else { return }
        message("Reading audio applications…"); render()
        deadline(value, after: deadlines.preparation, stage: .source)
        value.operation = Task { [weak self] in
            guard let self else { return }
            do {
                let sources = try await self.capture.sources()
                try Task.checkCancellation(); guard self.current(value) else { return }
                self.sources = sources
                self.pane?.setSources(sources, savedBundle: self.defaults.string(forKey: "SpeechSourceBundleID"))
                self.finish(value, text: "", autoInsert: false)
                self.message("Choose the meeting application. Browser audio includes other tabs. Microphone is off.")
            } catch { if self.current(value) { self.recover(value, failure: self.failure(error, stage: .source)) } }
        }
    }
    func prepareLanguage() {
        guard let value = begin() else { return }
        message("Preparing on-device language… No audio is being recorded."); render()
        // Explicit asset downloads report progress and are cancellable, without
        // the normal startup deadline. Cancellation still waits for settlement.
        value.operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.prepare(value.language, download: true) { [weak self] progress in
                    guard let self, self.current(value) else { return }
                    self.message("Preparing language: \(Int(progress * 100))%. No audio is being recorded.")
                }
                try Task.checkCancellation(); guard self.current(value) else { return }
                self.capability = "ready"; self.finish(value, text: "", autoInsert: false)
                self.message("On-device language is ready. Click Record when ready.")
            } catch { if self.current(value) { self.capability = "unavailable"; self.recover(value, failure: self.failure(error, stage: .model)) } }
        }
    }
    private func start() {
        guard let source = pane?.selectedAudioSource else { message("Select the meeting application before recording."); return }
        guard let owner, owner.window?.attachedSheet == nil, NSApp.modalWindow == nil, let value = begin() else { return }
        value.source = source; defaults.set(source.bundleID, forKey: "SpeechSourceBundleID")
        message("Checking audio and local language…"); render()
        deadline(value, after: deadlines.preparation, stage: .capture)
        value.operation = Task { [weak self] in
            guard let self else { return }
            do {
                value.context = await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview)
                try Task.checkCancellation()
                guard value.context != nil else { throw SpeechFailure(stage: .insertion, code: 1, message: "Open a ChatGPT chat before recording. Nothing was recorded.") }
                try await self.backend.prepare(value.language, download: false) { _ in }
                try Task.checkCancellation(); guard self.current(value) else { return }
                self.capability = "ready"
                value.captureStatus = "starting"
                try await self.capture.start(source: source)
                try Task.checkCancellation(); guard self.current(value) else { return }
                value.deadline?.cancel(); value.deadline = nil
                value.captureStatus = "recording"
                self.transition(.recording, value)
                let start = ContinuousClock.now
                value.timer = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self, self.current(value), self.state.phase == .recording else { return }
                        let elapsed = start.duration(to: .now)
                        let seconds = Int(elapsed.components.seconds)
                        self.pane?.setElapsed(seconds)
                        self.message("Recording \(source.name) · \(value.language.title) · \(seconds)/120 s · \(ChatKeyboard.recordLabel) stops")
                        if elapsed >= self.limit { self.stop(); return }
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    }
                }
            } catch { if self.current(value) { self.recover(value, failure: self.failure(error, stage: .capture)) } }
        }
    }
    private func interrupt(_ error: SpeechFailure) {
        guard let value = session else { return }
        if state.phase == .recording { stop(interruption: error) }
        else if current(value), state.phase == .preparing { recover(value, failure: error) }
    }
    private func stop(interruption: SpeechFailure? = nil) {
        guard state.phase == .recording, let value = session else { return }
        value.failure = interruption; value.timer?.cancel(); value.timer = nil
        value.captureStatus = "stopping"
        transition(.stopping, value); message("Stopping audio capture…")
        deadline(value, after: deadlines.cleanup, stage: .capture)
        value.operation = Task { [weak self] in
            guard let self else { return }
            let result = await self.capture.stop()
            guard self.current(value), !Task.isCancelled else { return }
            value.captureStatus = result.terminationConfirmed ? "ended" : "unconfirmed"
            guard result.terminationConfirmed else {
                self.recover(value, failure: result.failure ?? SpeechFailure(stage: .capture, code: 409, message: "Capture has not ended. Retry recovery before recording again.")); return
            }
            value.failure = value.failure ?? result.failure
            self.transition(.transcribing, value); self.message("Transcribing on this Mac…")
            self.deadline(value, after: self.deadlines.recognition, stage: .recognition)
            do {
                guard !result.samples.isEmpty, result.samples.contains(where: { abs($0) > 0.0001 }) else {
                    throw SpeechFailure(stage: .capture, code: 4, message: "No audible samples arrived. Check playback and the selected source, then record again.")
                }
                let text = try await self.backend.transcribe(result.samples, language: value.language) { [weak self] text in
                    guard let self, self.current(value), self.state.phase == .transcribing else { return }
                    value.partial = text; self.render()
                }
                try Task.checkCancellation(); guard self.current(value) else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SpeechFailure(stage: .recognition, code: 4, message: "No speech was recognized. The draft was not changed; you can record again.")
                }
                self.finish(value, text: text, autoInsert: value.failure == nil && !value.hadPending)
            } catch { if self.current(value) { self.recover(value, failure: self.failure(error, stage: .recognition), retainPartial: true) } }
        }
    }
    private func finish(_ value: Session, text: String, autoInsert: Bool) {
        guard session === value else { return }
        value.timer?.cancel(); value.deadline?.cancel()
        buffer.append(text)
        session = nil; state.reset(); render()
        if let failure = value.failure { report(failure) }
        else { message(buffer.hasText ? "Transcript retained. You can record again, review, or add it to your draft." : "Ready to record again.") }
        if autoInsert && buffer.hasText && !stopped { insert(manual: false, context: value.context) }
    }
    /// Cleanup owns both tasks until they actually settle. A deadline changes
    /// presentation only; it never drops a live native capture or opens a new one.
    private func recover(_ value: Session, failure: SpeechFailure? = nil, retainPartial: Bool = false) {
        guard session === value else { return }
        if !value.retiring {
            value.retiring = true; value.retainPartial = retainPartial; value.failure = failure
            value.operation?.cancel(); value.timer?.cancel(); value.deadline?.cancel()
        }
        guard value.cleanup == nil else { message(busyReason); return }
        transition(.recovering, value)
        if let failure = value.failure { report(failure) } else { message("Cancelling this segment. Earlier text is retained.") }
        deadline(value, after: deadlines.cleanup, stage: .capture)
        let operation = value.operation, capture = capture, backend = backend
        value.cleanup = Task { [weak self] in
            let cancel = Task { await backend.cancel() }
            let stop = Task { await capture.stop() }
            await operation?.value
            await cancel.value
            let result = await stop.value
            guard let self, self.session === value else { return }
            value.cleanup = nil; value.deadline?.cancel()
            value.captureStatus = result.terminationConfirmed ? "ended" : "unconfirmed"
            if result.terminationConfirmed {
                self.finish(value, text: value.retainPartial ? value.partial : "", autoInsert: false)
            } else {
                self.transition(.blocked, value)
                self.report(result.failure ?? SpeechFailure(stage: .capture, code: 409, message: "Capture has not ended. Retry recovery before recording again."))
            }
        }
    }
    private func retryRecovery() { if let session { recover(session) } }
    func cancel() {
        guard let session else { return }
        recover(session)
    }
    private func discardSelected() {
        guard idle else { return }
        if let selectedReview { buffer.discardUncertain(selectedReview); self.selectedReview = nil }
        else { buffer.edit("") }
        render(); message("Selected transcript discarded. Ready to record.")
    }
    private func insert(manual: Bool, context: String?) {
        guard idle, buffer.hasText, selectedReview == nil, let owner else { return }
        let snapshot = buffer.delivery(); delivery = snapshot
        let generation = state.begin()!
        _ = state.transition(.inserting, generation: generation); render()
        deliveryDeadline = Task { [weak self] in
            do { try await Task.sleep(for: self?.deadlines.insertion ?? .seconds(10)) } catch { return }
            guard let self, self.delivery?.id == snapshot.id else { return }
            self.completeInsertion(.uncertain, snapshot: snapshot)
        }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            let target = manual ? await AttachmentPageBridge.context(in: owner.webView, preview: owner.preview) : context
            guard self.delivery?.id == snapshot.id, !self.stopped else { return }
            guard let target else { self.completeInsertion(.unavailable, snapshot: snapshot); return }
            let outcome = await self.insertion(snapshot.text, snapshot.id, target, owner) { [weak self] in
                self?.delivery?.id == snapshot.id && self?.stopped == false
            }
            guard self.delivery?.id == snapshot.id else { return }
            self.completeInsertion(outcome, snapshot: snapshot)
        }
    }
    private func completeInsertion(_ outcome: DraftInsertionBridge.Outcome, snapshot: SpeechTranscriptBuffer.Delivery) {
        guard delivery?.id == snapshot.id else { return }
        deliveryDeadline?.cancel(); deliveryDeadline = nil; delivery = nil
        deliveryTask = nil; state.reset()
        switch outcome {
        case .inserted:
            buffer.acknowledge(snapshot, uncertain: false)
            message("Transcript appended to your draft. Review it and send manually.")
        case .uncertain:
            buffer.acknowledge(snapshot, uncertain: true); selectedReview = snapshot.id
            report(SpeechFailure(stage: .insertion, code: 2, message: "Insertion could not be confirmed. Check the draft before copying missing text. This segment cannot be automatically retried; new recordings remain available."))
        default: message("Transcript retained. Show the chat, finish any Chinese composition, and click Add to Chat when ready. You can also record again.")
        }
        render()
    }
    func shutdown() {
        guard !stopped else { return }
        stopped = true
        for (center, observer) in observers { center.removeObserver(observer) }; observers.removeAll()
        deliveryDeadline?.cancel(); deliveryTask?.cancel(); delivery = nil
        if let session { recover(session) }
        owner = nil; buffer = .init()
    }
    private func render() {
        guard let pane else { return }
        if let selectedReview, !buffer.uncertain.contains(where: { $0.id == selectedReview }) { self.selectedReview = nil }
        let uncertain = selectedReview.flatMap { id in buffer.uncertain.first { $0.id == id } }
        let partial = !buffer.hasText && uncertain == nil && session?.hadPending == false ? session?.partial ?? "" : ""
        pane.setReviewItems(buffer.uncertain.map(\.id), selected: selectedReview)
        pane.setTranscript(uncertain?.text ?? (buffer.hasText ? buffer.text : partial))
        pane.update(phase: phase, busy: false, inserting: delivery != nil, uncertain: uncertain != nil,
                    sourceName: session?.source?.name ?? pane.selectedAudioSource?.name, recordEnabled: canRecord,
                    pendingEditable: selectedReview == nil && delivery == nil && (buffer.hasText || idle || session?.hadPending == true))
        owner?.updateRecordButton(recording: state.phase == .recording, enabled: canRecord)
    }
    private func message(_ text: String) { pane?.showMessage(text) }
    private func failure(_ error: any Error, stage: SpeechFailure.Stage) -> SpeechFailure {
        error as? SpeechFailure ?? SpeechFailure(stage: stage, code: (error as NSError).code,
            message: "\(stage.rawValue.capitalized) failed (code \((error as NSError).code)). Nothing was sent. Review settings and try again manually.")
    }
    private func report(_ failure: SpeechFailure) { lastFailure = failure; pane?.showMessage(failure.message, error: true) }
}
