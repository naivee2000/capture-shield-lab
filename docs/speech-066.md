# 0.6.6 continuous recording and recovery

Version 0.6.6/build 15 separates pending text from the recording lifecycle. Deployment remains Apple Silicon macOS 15.6+ with Swift 6.2+/SDK 26+. The microphone, audio filter, language selection, 120-second limit, privacy indicators and receiver protection are unchanged.

## Behavior

- Record / Cmd-Shift-R becomes available after recognition and cleanup, even with an earlier transcript waiting for review. Preparation, stopping, recognition and insertion checks remain serial; pressing the shortcut while busy explains the phase and does not enqueue another recording.
- A successful segment with no earlier pending text follows the existing safe automatic draft append. With earlier pending or uncertain text, the new segment is retained for manual review. New text is separated by a blank line, preserving edits to the earlier segment.
- Cancel discards only the active segment. Earlier pending text survives. Discard explicitly removes the selected retained text. Collapsing or hiding the panel never discards it.
- A delivery that cannot be confirmed appears under **Check draft · segment N** in the review selector. It is read-only and cannot be automatically added again. Check/copy missing text manually or discard that snapshot. **Pending text** remains separately editable/addable, and another recording is allowed. Nothing sends a message.
- Empty audio, empty recognition and recognition failures return to a recordable state after cleanup. Partial text from a failed recognition remains for review.
- A failed or unconfirmed stop keeps Record disabled and exposes **Retry recovery**. Do not interpret a timeout as proof that capture stopped. If native work never settles, preserve pending text before restarting the app yourself.

## Ownership and deadlines

`AudioCaptureLifecycle` owns a single native transport lease. Duplicate starts fail explicitly; concurrent stop/cancel calls await the same stop. A transport is retained after a failed stop and released only after confirmed termination. Native stream callbacks are scoped to their lease; conversion failures are distinct from the stream delegate's terminal notification. The `AudioStreamTransport` seam exercises this production ownership with deterministic test continuations.

`SpeechCoordinator` owns each operation's generation, cancellation, timers and cleanup. Old operations cannot clear new resources, overwrite pending edits or acknowledge a different delivery. Both speech engines have awaited cancellation; a modern analysis owns its result reader and cancellation task. Finished transcripts and uncertain delivery snapshots live only in memory.

Normal preparation has a 30-second deadline, capture stop/cleanup and draft insertion 10 seconds each, and recognition 180 seconds. Explicit language downloads instead show progress and allow cancellation. A cleanup timeout changes the UI to blocked recovery; it does not abandon the native operation or permit overlapping capture. A late insertion response cannot clear newer pending text. The webpage bridge checks that its delivery is still current after asynchronous preconditions and before invoking the editing operation.

WebKit represents multiline insertions using paragraph/BR nodes. Verification checks the full text-node sequence and visible inserted paragraphs, allowing layout-only terminal newlines without erasing the draft or replacing the editor. A false uncertain result for merged transcripts was reproduced before this repair.

Compatibility diagnostics contain phase, availability, capture status, pending/uncertain booleans and numeric error stage/code. They exclude transcript/audio contents, account information, source process identities and webpage data.

## Repeat the checks

```bash
bash scripts/test.sh --no-parallel
python3 -m unittest discover -s Tests/ScriptTests -v
bash scripts/test-ui.sh --preflight
bash scripts/test-ui.sh
```

The native harness loads the actual SwiftPM-built test bundle(s) in a synchronous native host, using the same built-in Swift Testing entry point. SwiftPM ignores custom entry-point paths on Darwin, so the host never patches generated runners or SDK files. Native tests explicitly select SwiftPM's supported `native` build system, including Xcode 27; the initial Swift Build per-target bundle failed to load in this host. Packaged UI validation continues to build the real app through the unchanged application build path. The default async main exited before tests completed when the main run loop stopped, matching [Swift issue 91716](https://github.com/swiftlang/swift/issues/91716). A test deliberately stops the run loop and must finish afterward; an opt-in negative control must still fail. This runner is test-only and does not change the application. The script continues to reject incomplete output even with exit code 0, without retries or relaxed assertions. Deadline regressions inject a controllable wait and fire only after the intended operation is blocked, using the production 30/10/180-second values. The first macOS 15 run exposed a 300-ms fixture deadline racing WebView startup; no application deadline or assertion was relaxed. The native suite includes ten sequential completions, retained edits/merge/cancel, no-sound and failure retry, delayed and failed stop, startup/recognition deadlines, stale callbacks and uncertain insertion. The packaged UI suite contains eleven scenarios, including three consecutive successful recordings and recording again after retaining an error result. Preview audio is synthetic and cannot establish real source capture or speech recognition.

For an explicit local recognition check, generate harmless `english.aiff` and `chinese.aiff` fixtures saying seven plus five in a disposable directory, then set `CAPTURESHIELD_SYNTHETIC_SPEECH_DIR` for `scripts/test.sh --filter LocalSpeechFixtureTests`. The test performs five consecutive recognitions per language with installed models; it does not capture application audio or download models. Delete the generated audio afterward; never use meeting recordings as fixtures.

## Verified release results (2026-11-16)

Tested source: `34f7f7f82c007eaea15c1d48be66d96fea953685`, version **0.6.6/build 15**. [The complete matrix](https://github.com/naivee2000/capture-shield-lab/actions/runs/43949454329) passed without retries. Exact hashes, hosts, counts, first failures and cleanup evidence are in [the machine-readable ledger](validation-speech-066.json).

| Actual host | Native regression | Packaged application UI | Build/sign/register and negative controls |
| --- | --- | --- | --- |
| macOS 15.8.2 (24H232), Xcode 26.3 / Swift 6.2.4 / SDK 26.2 | 124 reported; 2 optional cases skipped | 11 scenarios × 3 rounds, all passed | Passed |
| macOS 26.7.2 (25G332), Xcode 26.6 / Swift 6.3.3 / SDK 26.5 | 124 reported; 2 optional cases skipped | 11 scenarios × 3 rounds, all passed | Passed |
| macOS 27.0.1 (26A434), Xcode 27.2 / Swift 6.4.2 / SDK 27.2 | 124 reported; 2 optional cases skipped | 11 scenarios × 3 rounds, all passed | Passed |

Each host also passed 20 script checks. The two optional native cases are actual installed-model recognition and visual export; neither is silently counted as device acceptance. UI previews substitute synthetic audio/results and never load a ChatGPT account.

On the development Mac, macOS 26.6.2 (25G83), the complete native suite and a clean clone in a space-containing path passed. Both cloned apps were signed, registered and checked against the 15.6 Info.plist/Mach-O floor. Installed SpeechAnalyzer models recognized five consecutive generated English questions and five Mandarin questions; the tested backend source blob is recorded separately. No meeting audio or model download was used. Actual selected-app capture, a live 120-second capture, real ChatGPT insertion and an independent receiver remain **not-tested for this release**.

The initial failures remain recorded: the original retained-text lock; multiline insertion falsely reported uncertain; the Swift async-main test-host exit; the Xcode 27 test-product loader mismatch; and the shortened startup fixture racing macOS 15 WebView preparation. Corrections preserve assertions and production deadlines. Superseded workflow attempts were cancelled by the existing concurrency policy after corrected commits were pushed; their failed stages are not relabeled as passes.

Local task-generated apps, clones, audio fixtures, build/module caches and raw logs were removed; the APFS image was detached/deleted, reclaiming **2,930,769,920 allocated bytes (about 2.73 GiB)**. Only technical summaries/manifests remain. QA042, user windows/login data and installed speech models were preserved. Each hosted job also completed its scoped UI cleanup.

## Device acceptance still required

On the actual sender Mac, record the installed app path/version/commit, OS/build, source app/version and language. With a harmless question and an existing draft/image:

1. Record/stop five times in English, then five times in Mandarin. Confirm Record and Cmd-Shift-R work again, each new segment appears once, the draft/image survive and nothing sends.
2. Hide the chat before stopping, then reopen it. Keep/edit the retained text, record again, review the merge and add once. Cancel a new segment and confirm earlier text remains.
3. Test silent playback, source exit/restart, a 120-second segment and headphones. Confirm stopping/cancelling actually ends capture; do not hide or bypass system indicators.
4. On an independent Teams receiver, check Normal/Legacy and the new recovery/review controls. Report local usability and receiver visibility separately.

The release evidence ledger records actual test hosts and commits. Older results and runner labels do not certify this build, every 15.x/27.x patch, or a future macOS version.
