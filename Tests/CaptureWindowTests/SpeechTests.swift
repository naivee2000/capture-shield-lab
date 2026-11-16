import AppKit
import AVFoundation
import WebKit
import Testing
import CaptureCore
@testable import CaptureShieldLab

@MainActor private final class TestAudio: AudioCaptureProviding {
    var failed: ((Int) -> Void)?
    var starts = 0
    var stops = 0
    var delay: Duration = .zero
    var startGate: SpeechTestGate?
    var stopGate: SpeechTestGate?
    var samples: [Float] = [Float](repeating: 0.2, count: 1600)
    var terminationConfirmed = true
    func sources() async throws -> [AudioSource] { [.init(bundleID: "test.synthetic", name: "Synthetic Audio", pid: 1)] }
    func start(source: AudioSource) async throws { starts += 1; await startGate?.wait(); try await Task.sleep(for: delay) }
    private var stopping: Task<AudioCaptureStop, Never>?
    func stop() async -> AudioCaptureStop {
        if let stopping { return await stopping.value }
        let task = Task { @MainActor in
            self.stops += 1; await self.stopGate?.wait()
            self.stopping = nil
            return AudioCaptureStop(samples: self.samples, terminationConfirmed: self.terminationConfirmed,
                failure: self.terminationConfirmed ? nil : .init(stage: .capture, code: 91, message: "Synthetic stop failure"))
        }
        stopping = task; return await task.value
    }
}
@MainActor private final class DeniedAudioPermission: ScreenCapturePermissionChecking {
    var requests = 0
    func preflight() -> Bool { false }
    func request() -> Bool { requests += 1; return false }
}
@MainActor private final class TestSpeech: SpeechTranscriptionBackend {
    let name = "Synthetic local recognizer"
    var modelMissing = false
    var recognitionFails = false
    var recognitionGate: SpeechTestGate?
    var cancellations = 0
    var text = "Synthetic question"
    var retainedPartial: (@MainActor (String) -> Void)?
    func prepare(_ language: TranscriptionLanguage, download: Bool, progress: @escaping @MainActor (Double) -> Void) async throws {
        if modelMissing { throw SpeechFailure(stage: .model, code: 2, message: "Synthetic missing model") }; progress(1)
    }
    func transcribe(_ samples: [Float], language: TranscriptionLanguage, partial: @escaping @MainActor (String) -> Void) async throws -> String {
        retainedPartial = partial; partial(text); await recognitionGate?.wait()
        if recognitionFails { throw SpeechFailure(stage: .recognition, code: 92, message: "Synthetic recognition failure") }
        return text
    }
    func cancel() async { cancellations += 1 }
}

@MainActor private protocol SpeechFixtures {}
@MainActor private extension SpeechFixtures {
    func fixture(textarea: Bool = false) async throws -> ChatWindow {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let owner = ChatWindow(configuration: config, isMain: true, preferences: .init(mode: .normal), preview: true)
        owner.window?.orderFront(nil)
        let editor = textarea ? "<textarea id='prompt-textarea'>Existing draft</textarea>" : "<div id='prompt-textarea' contenteditable='true'>Existing draft</div>"
        owner.webView.loadHTMLString("""
        <style>#prompt-textarea{width:400px;min-height:100px;white-space:pre-wrap}</style>
        <form>\(editor)<img id='attachment' alt='Synthetic attachment'><button type='submit'>Send</button></form>
        <script>window.sent=0;document.querySelector('form').onsubmit=e=>{e.preventDefault();window.sent++};window.ready=true;</script>
        """, baseURL: nil)
        try await wait { (try? await owner.webView.evaluateJavaScript("window.ready === true")) as? Bool == true }
        await owner.composition.synchronize(in: owner.webView)
        return owner
    }
    func wait(line: Int = #line, _ predicate: @MainActor () async -> Bool) async throws {
        for _ in 0..<150 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(30)) }
        throw SpeechFailure(stage: .recognition, code: 408, message: "Synthetic test timed out at line \(line)")
    }
    func text(_ owner: ChatWindow) async throws -> String {
        try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').value ?? document.querySelector('#prompt-textarea').innerText") as! String
    }
    func cleanup(_ owner: ChatWindow) {
        owner.speech.shutdown(); owner.webView.stopLoading()
        owner.webView.navigationDelegate = nil; owner.webView.uiDelegate = nil
        owner.closeTestFixture()
    }
}

@MainActor @Suite(.serialized) struct SpeechTests: SpeechFixtures {
    @Test(arguments: [false, true]) func appendPreservesDraftAndAttachmentsAndIsExactlyOnce(textarea: Bool) async throws {
        let owner = try await fixture(textarea: textarea); defer { cleanup(owner) }
        let context = try #require(await AttachmentPageBridge.context(in: owner.webView, preview: true))
        let token = UUID().uuidString
        let outcome = await DraftInsertionBridge.append("Test transcript", token: token, context: context, owner: owner)
        #expect(outcome == .inserted)
        #expect(await DraftInsertionBridge.append("Test transcript", token: token, context: context, owner: owner) == .inserted)
        let actual = try await text(owner)
        #expect(actual.trimmingCharacters(in: .newlines) == "Existing draft Test transcript")
        #expect(try await owner.webView.evaluateJavaScript("window.sent") as? Int == 0)
        #expect(try await owner.webView.evaluateJavaScript("!!document.querySelector('#attachment')") as? Bool == true)
        _ = try await owner.webView.evaluateJavaScript("document.execCommand('undo')")
        #expect(try await text(owner) == "Existing draft")
    }
    @Test func richTextParagraphLayoutDoesNotBecomeDraftContent() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        _ = try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').innerHTML='<p>Existing draft</p><p><br></p>'")
        let context = try #require(await AttachmentPageBridge.context(in: owner.webView, preview: true))
        let outcome = await DraftInsertionBridge.append("Synthetic question", token: "paragraph", context: context, owner: owner)
        #expect(outcome == .inserted)
        let result = try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').textContent.replace(/\\u00a0/g,' ')") as? String
        #expect(result == "Existing draft Synthetic question")
        #expect(try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').firstElementChild.textContent") as? String == "Existing draft")
    }
    @Test func multilineTranscriptPreservesVisibleParagraphsAndConfirmsInsertion() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let context = try #require(await AttachmentPageBridge.context(in: owner.webView, preview: true))
        let outcome = await DraftInsertionBridge.append("First line\n\nSecond line", token: "multiline", context: context, owner: owner)
        let rendered = try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').innerText") as? String
        #expect(outcome == .inserted)
        #expect(rendered?.trimmingCharacters(in: .newlines) == "Existing draft First line\n\nSecond line")
    }
    @Test func hiddenCompositionAndStalePageRefuseInsertion() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let context = try #require(await AttachmentPageBridge.context(in: owner.webView, preview: true))
        owner.window?.orderOut(nil)
        #expect(await DraftInsertionBridge.append("hidden", token: "a", context: context, owner: owner) == .blocked)
        owner.window?.orderFront(nil)
        _ = try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}))")
        #expect(await DraftInsertionBridge.append("marked", token: "b", context: context, owner: owner) == .blocked)
        _ = try await owner.webView.evaluateJavaScript("document.querySelector('#prompt-textarea').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}))")
        #expect(await DraftInsertionBridge.append("stale", token: "c", context: "old document", owner: owner) == .stale)
        #expect(try await text(owner) == "Existing draft")
    }
    @Test func recordingDeadlineStopsAndAppendsWithoutSending() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend, limit: .milliseconds(250))
        defer { coordinator.shutdown() }
        coordinator.refreshSources()
        try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0)
        coordinator.toggle(); coordinator.toggle() // preparing ignores repeated starts
        try await wait { audio.stops == 1 && coordinator.phase == .idle }
        #expect(audio.starts == 1)
        let actual = try await text(owner)
        #expect(actual.trimmingCharacters(in: .newlines) == "Existing draft Synthetic question")
        #expect(try await owner.webView.evaluateJavaScript("window.sent") as? Int == 0)
    }
    @Test func missingModelDoesNotStartAudioAndInterruptionDoesNotAutoInsert() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech(); backend.modelMissing = true
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        coordinator.refreshSources(); try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0); coordinator.toggle()
        try await wait { coordinator.phase == .idle && coordinator.lastFailure != nil }
        #expect(audio.starts == 0)
        backend.modelMissing = false; coordinator.toggle()
        try await wait { coordinator.phase == .recording }
        audio.failed?(99)
        try await wait { coordinator.phase == .ready }
        #expect(try await text(owner) == "Existing draft")
        #expect(owner.speechPane.result.string == "Synthetic question")
        #expect(coordinator.lastFailure?.code == 99)
    }
    @Test func audioAndScreenshotDenialShareOnePermissionAttempt() async throws {
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let defaults = preferences.defaults, permission = DeniedAudioPermission()
        let audio = AudioCaptureService(defaults: defaults, permission: permission)
        do { _ = try await audio.sources(); Issue.record("Permission denial must fail") }
        catch { #expect((error as? SpeechFailure)?.stage == .permission) }
        let screenshot = ScreenshotService(defaults: defaults, permission: permission)
        do { _ = try await screenshot.capture(displayID: 1); Issue.record("Permission denial must fail") }
        catch { #expect((error as? ScreenshotError)?.failure.stage == .permission) }
        #expect(permission.requests == 1)
    }
    @Test func retainedTranscriptDoesNotDisableNextRecording() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        coordinator.refreshSources()
        try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0); coordinator.toggle()
        try await wait { coordinator.phase == .recording }
        audio.failed?(99)
        try await wait { coordinator.phase == .ready }
        #expect(owner.speechPane.result.string == "Synthetic question")
        #expect(owner.speechPane.record.isEnabled, "Retained text must not disable another recording")
        coordinator.toggle()
        try await wait { coordinator.phase == .recording }
        #expect(audio.starts == 2)
    }
    @Test func cancellingPreparationDoesNotStartOrAppendLater() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech(); audio.delay = .seconds(1)
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        coordinator.refreshSources(); try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0); coordinator.toggle()
        try await wait { audio.starts == 1 }
        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.phase == .idle)
        #expect(try await text(owner) == "Existing draft")
        #expect(owner.speechPane.result.string.isEmpty)
    }
    @Test func duplicateApplicationNamesNeverShiftSourceIdentity() {
        let pane = SpeechPane()
        let sources: [AudioSource] = [.init(bundleID: "test.one", name: "Duplicate", pid: 11),
            .init(bundleID: "test.two", name: "Duplicate", pid: 12), .init(bundleID: "test.target", name: "Target", pid: 13)]
        pane.setSources(sources, savedBundle: "test.target")
        #expect(pane.source.numberOfItems == 3)
        #expect(pane.selectedAudioSource == sources[2])
        pane.source.selectItem(at: 1)
        #expect(pane.selectedAudioSource?.bundleID == "test.two")
    }
    @Test func editedRetainedTranscriptAppendsOnceWithoutLosingDraftOrImage() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        coordinator.refreshSources()
        try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0); coordinator.toggle()
        try await wait { coordinator.phase == .recording }
        audio.failed?(99) // interrupted results are retained instead of auto-appended
        try await wait { coordinator.phase == .ready }
        let pane = owner.speechPane
        pane.toggleTranscript()
        #expect(pane.result.isEditable)
        pane.result.string = ""
        pane.textDidChange(Notification(name: NSText.didChangeNotification))
        #expect(pane.transcriptExpanded && pane.result.isEditable)
        pane.result.string = "Reviewed synthetic text 中文"
        pane.textDidChange(Notification(name: NSText.didChangeNotification))
        backend.retainedPartial?("Late recognition must not replace the edited result")
        #expect(pane.result.string == "Reviewed synthetic text 中文")
        pane.toggleTranscript(); pane.toggleTranscript()
        pane.add.performClick(nil); pane.add.performClick(nil)
        try await wait { coordinator.phase == .idle }
        #expect(try await text(owner) == "Existing draft Reviewed synthetic text 中文")
        #expect(try await owner.webView.evaluateJavaScript("window.sent === 0 && !!document.querySelector('#attachment')") as? Bool == true)
        #expect(pane.result.string.isEmpty && pane.preferredHeight == 36)
    }
    @Test func modePolicyDoesNotRequireWindowLevelChanges() {
        #expect(ApplicationPresentation.policy(for: .legacy) == .accessory)
        #expect(ApplicationPresentation.policy(for: .normal) == .regular)
        let configuration = AudioCaptureService.configuration()
        #expect(configuration.capturesAudio && !configuration.captureMicrophone)
        #expect(configuration.excludesCurrentProcessAudio && !configuration.showsCursor)
    }
}

@MainActor @Suite(.serialized) struct SpeechRecoveryTests: SpeechFixtures {
    private func selectSource(_ coordinator: SpeechCoordinator, _ owner: ChatWindow) async throws {
        coordinator.refreshSources()
        try await wait { owner.speechPane.source.numberOfItems == 1 && owner.speechPane.source.isEnabled }
        owner.speechPane.source.selectItem(at: 0)
    }
    @Test func tenCompletedRecordingsAppendOnceEachWithoutSending() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        for index in 0..<10 {
            backend.text = "Segment[\(index)]"
            coordinator.toggle(); coordinator.toggle() // preparation cannot enqueue another start
            try await wait { coordinator.phase == .recording }
            coordinator.toggle(); coordinator.toggle() // stopping cannot queue another capture
            try await wait { coordinator.phase == .idle && coordinator.canRecord }
            #expect(try await text(owner).components(separatedBy: backend.text).count == 2)
        }
        #expect(audio.starts == 10)
        #expect(try await owner.webView.evaluateJavaScript("window.sent === 0 && !!document.querySelector('#attachment')") as? Bool == true)
    }
    @Test func pendingEditsMergeWithNextSegmentAndCancelPreservesThem() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        coordinator.toggle(); try await wait { coordinator.phase == .recording }; audio.failed?(99)
        try await wait { coordinator.phase == .ready }
        let oldPartial = backend.retainedPartial
        owner.speechPane.result.string = "Edited first"; owner.speechPane.textDidChange(.init(name: NSText.didChangeNotification))
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        coordinator.cancel(); try await wait { coordinator.phase == .ready }
        #expect(owner.speechPane.result.string == "Edited first")
        backend.text = "Second segment"
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        owner.speechPane.result.string = "Latest edit"; owner.speechPane.textDidChange(.init(name: NSText.didChangeNotification))
        coordinator.toggle(); try await wait { coordinator.phase == .ready }
        oldPartial?("Obsolete result")
        #expect(owner.speechPane.result.string == "Latest edit\n\nSecond segment")
        #expect(try await text(owner) == "Existing draft")
        owner.speechPane.toggleTranscript()
        owner.speechPane.add.performClick(nil); owner.speechPane.add.performClick(nil)
        try await wait { coordinator.phase == .idle }
        #expect(try await text(owner).contains("Latest edit"))
        #expect(try await text(owner).components(separatedBy: "Second segment").count == 2)
    }
    @Test func silenceEmptyResultAndRecognitionFailureCanRecordAgain() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        for scenario in 0..<3 {
            audio.samples = scenario == 0 ? [] : [0.2]; backend.text = ""; backend.recognitionFails = scenario == 2
            coordinator.toggle(); try await wait { coordinator.phase == .recording }; coordinator.toggle()
            try await wait { coordinator.phase == .idle && coordinator.lastFailure != nil }
            #expect(coordinator.canRecord && owner.speechPane.record.isEnabled)
        }
        backend.recognitionFails = false; backend.text = "Recovered question"
        coordinator.toggle(); try await wait { coordinator.phase == .recording }; coordinator.toggle()
        try await wait { coordinator.phase == .idle }
        #expect(try await text(owner) == "Existing draft Recovered question")
    }
    @Test func stopTimeoutDoesNotReopenUntilNativeCompletion() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech(), gate = SpeechTestGate(), clock = SpeechTestDeadlines()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend,
                                            waitForDeadline: clock.sleep)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        audio.stopGate = gate; coordinator.toggle()
        try await wait { gate.entered && clock.contains(.seconds(10)) }
        clock.fire(.seconds(10))
        try await wait { coordinator.phase == .recovering && clock.contains(.seconds(10)) }
        clock.fire(.seconds(10))
        try await wait { coordinator.phase == .blocked }
        coordinator.toggle(); #expect(audio.starts == 1 && !coordinator.canRecord)
        gate.release(); audio.stopGate = nil
        try await wait { coordinator.phase == .idle }
        #expect(try await text(owner) == "Existing draft")
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        #expect(audio.starts == 2)
    }
    @Test func failedStopNeedsConfirmedRecoveryBeforeRetry() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        audio.terminationConfirmed = false; coordinator.toggle()
        try await wait { coordinator.phase == .blocked }
        #expect(!owner.speechPane.record.isEnabled && owner.speechPane.discard.title == "Retry recovery")
        coordinator.toggle(); #expect(audio.starts == 1)
        audio.terminationConfirmed = true; owner.speechPane.discard.performClick(nil)
        try await wait { coordinator.phase == .idle }
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
        #expect(audio.starts == 2)
    }
    @Test func startupAndRecognitionTimeoutsWaitForRetiringWork() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech(), start = SpeechTestGate(), recognize = SpeechTestGate(), clock = SpeechTestDeadlines()
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend,
            waitForDeadline: clock.sleep)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        audio.startGate = start; coordinator.toggle()
        try await wait { start.entered && clock.contains(.seconds(30)) }
        clock.fire(.seconds(30))
        try await wait { coordinator.phase == .recovering && clock.contains(.seconds(10)) }
        clock.fire(.seconds(10))
        try await wait { coordinator.phase == .blocked }
        #expect(!coordinator.canRecord)
        start.release(); audio.startGate = nil
        try await wait { coordinator.phase == .idle }
        backend.recognitionGate = recognize
        coordinator.toggle(); try await wait { coordinator.phase == .recording }; coordinator.toggle()
        try await wait { recognize.entered && clock.contains(.seconds(180)) }
        clock.fire(.seconds(180))
        try await wait { coordinator.phase == .recovering && clock.contains(.seconds(10)) }
        clock.fire(.seconds(10))
        try await wait { coordinator.phase == .blocked }
        #expect(!coordinator.canRecord)
        recognize.release(); backend.recognitionGate = nil
        try await wait { coordinator.phase == .ready }
        #expect(owner.speechPane.result.string == "Synthetic question")
        #expect(try await text(owner) == "Existing draft")
        coordinator.toggle(); try await wait { coordinator.phase == .recording }
    }
    @Test func uncertainInsertionDoesNotBlockNewTextOrClearItOnLateAcknowledgement() async throws {
        let owner = try await fixture(); defer { cleanup(owner) }
        let preferences = FixturePreferences(); defer { preferences.clear() }
        let audio = TestAudio(), backend = TestSpeech(), gate = SpeechTestGate(), clock = SpeechTestDeadlines()
        var calls = 0
        let coordinator = SpeechCoordinator(owner: owner, defaults: preferences.defaults, capture: audio, backend: backend,
            insertion: { text, token, context, owner, valid in
                calls += 1
                if calls == 1 { await gate.wait(); return .inserted }
                return await DraftInsertionBridge.append(text, token: token, context: context, owner: owner, isCurrent: valid)
            }, waitForDeadline: clock.sleep)
        defer { coordinator.shutdown() }
        try await selectSource(coordinator, owner)
        coordinator.toggle(); try await wait { coordinator.phase == .recording }; coordinator.toggle()
        try await wait { gate.entered && clock.contains(.seconds(10)) }
        clock.fire(.seconds(10))
        try await wait { coordinator.phase == .ready }
        #expect(coordinator.canRecord && !owner.speechPane.add.isEnabled)
        backend.text = "New uninserted segment"
        coordinator.toggle(); try await wait { coordinator.phase == .recording }; coordinator.toggle()
        try await wait { coordinator.phase == .ready }
        gate.release()
        owner.speechPane.reviewSelectionAction?(nil)
        #expect(owner.speechPane.result.string == "New uninserted segment")
        #expect(owner.speechPane.reviewSelection.numberOfItems == 2)
        owner.speechPane.toggleTranscript()
        owner.speechPane.add.performClick(nil)
        try await wait { calls == 2 && coordinator.phase == .ready }
        #expect(try await text(owner) == "Existing draft New uninserted segment")
        #expect(coordinator.canRecord)
    }
}

/// Explicit opt-in: only generated English/Chinese fixture files, never a meeting.
@MainActor struct LocalSpeechFixtureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAPTURESHIELD_SYNTHETIC_SPEECH_DIR"] != nil))
    func installedModernModelsRecognizeSyntheticQuestions() async throws {
        guard #available(macOS 26, *), let path = ProcessInfo.processInfo.environment["CAPTURESHIELD_SYNTHETIC_SPEECH_DIR"] else { return }
        for (file, language) in [("english", TranscriptionLanguage.english), ("chinese", .chinese)] {
            let audio = try AVAudioFile(forReading: URL(fileURLWithPath: path).appendingPathComponent(file + ".aiff"))
            let source = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
            try audio.read(into: source)
            let converter = AVAudioConverter(from: source.format, to: AudioSampleSink.format)!
            let output = AVAudioPCMBuffer(pcmFormat: AudioSampleSink.format, frameCapacity: AVAudioFrameCount(ceil(Double(source.frameLength) * 16000 / source.format.sampleRate)) + 4096)!
            let input = PCMBufferInput(source); var error: NSError?
            _ = converter.convert(to: output, error: &error) { _, status in input.provide(status) }
            let samples = Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
            let backend = ModernSpeechBackend()
            for _ in 0..<5 {
                try await backend.prepare(language, download: false) { _ in }
                let result = try await backend.transcribe(samples, language: language) { _ in }
                #expect(!result.isEmpty)
                if language == .english {
                    #expect(result.lowercased().contains("seven") || result.contains("7"))
                    #expect(result.lowercased().contains("five") || result.contains("5"))
                } else {
                    #expect(result.contains("七") || result.contains("7"))
                    #expect(result.contains("五") || result.contains("5"))
                    #expect(result.contains("加"))
                }
                await backend.cancel() // an already finished analysis must not affect the next one
            }
        }
    }
}
