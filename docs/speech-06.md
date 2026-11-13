# 0.6 speech and Dock implementation

## Data flow and safety boundaries

`AudioCaptureService` uses a ScreenCaptureKit application filter and registers only an audio output. The microphone is disabled. A serial queue converts to mono 16 kHz float PCM and retains at most 120 seconds in memory. Stop/cancel detaches the stream and releases buffered samples. Audio, transcripts and page text are not logged, written as history, or uploaded to a transcription service.

`SpeechTranscriptionBackend` selects SpeechAnalyzer on macOS 26+ or explicitly local SFSpeechRecognizer on older supported systems. Language assets are reserved explicitly before installation/readiness checks; a completed download alone is not readiness. Each recognition session gets a fresh result sequence. The older engine uses <=50-second requests with one-second overlap and timestamp midpoint ownership at boundaries. It must advertise local support; no network-recognition fallback exists.

`SpeechCoordinator` owns recording/preparation/transcription/pending states, cancellation generations, the 120-second deadline, and interruption handling. A hidden window keeps recording until explicit stop/deadline; a hidden/minimized chat never receives automatic insertion. Lock/sleep/session-inactive/source-exit events stop the capture and retain completed text for explicit review. No interrupted session restarts automatically.

`DraftInsertionBridge` binds automatic insertion to a trusted main chat document/route. Only an insertion outcome crosses the web bridge: draft comparisons stay in the isolated page world. It performs an undoable insertText operation at the editor end, preserving existing content and attachments. Text-node content is compared rather than rendered innerText, because the live editor adds layout-only terminal newlines. A separating space is added when necessary. A per-document token makes retry idempotent; uncertain edits block further attempts. Navigation, composition, sheets and hidden windows retain the result for Add to Chat/Discard. Nothing submits a message.

Native source menu items carry the actual `AudioSource` identity. They are never mapped back by a display-name index: NSPopUpButton's bulk title API coalesces duplicates. Duplicate visible names receive a PID suffix in the local menu; these identities are excluded from diagnostic exports.

`ApplicationPresentation` maps Normal to regular and Legacy to accessory activation. LSUIElement prevents a cold Legacy launch from starting as a Dock app; the lab explicitly chooses regular activation. Windows remain ordinary normal-level windows. Global keys register exclusively, suppress held-key repeats and report conflicts. When the visibility key is unavailable, Legacy refuses Hide/close and keeps a Finder reopen recovery path. No Dock preferences or user-pinned tiles are edited.

## Validation ledger (2026-11-12)

Host: Apple Silicon, macOS 26.6.2 (25G83), Swift 6.2.4, SDK 26.2. Version 0.6.0/build 9; deployment minimum 15.6.

| Check | Evidence / result |
| --- | --- |
| Automated regression | 91 tests / 18 suites passed, including real local English/Chinese recognition from generated AIFF fixtures; no meeting audio |
| Modern language readiness | Found and fixed a missing explicit language reservation. English/Chinese installed models now pass readiness and consecutive recognition |
| Application selection | Found and fixed native duplicate-title coalescing before accepting a capture verdict. Regression verifies exact represented application identity |
| Live English | Selected synthetic playback app captured and recognized; final real ChatGPT composer reports appended, original synthetic draft retained, no message sent |
| Structured editor | Live trial exposed layout-only newlines in innerText. Text-node verification and rich-text paragraph regression fixed false success/failure and missing separator |
| Live Mandarin / deadline | Selected-app Mandarin recognized and appended after the actual 120-second deadline; earlier English and original synthetic draft retained, no send |
| Live existing attachment / undo | A restored synthetic PNG stayed in the real composer while Mandarin was appended. Actual Cmd-Z removed the appended transcript and restored the original draft while retaining the image; nothing sent |
| Source exclusion | While the synthetic audio app played, a different silent application was selected. No audible samples arrived; the composer stayed unchanged |
| Native application policy | Final real QA app read back Normal as regular (0), Legacy as accessory (1), then Normal as regular again; the same window and draft remained. Legacy Cmd-Q exercised in the separate preview |
| Signing and registration | Both QA apps strictly signed and registered; doctor reports 0.6.0/build 9 and minimum 15.6 |
| Clean clone | Implementation commit `3413f78fe833` built from a fresh clone in a source path containing spaces. Both apps signed/registered, doctor and script checks passed, 91 tests / 18 suites passed (including generated local speech), clone clean. Both Info.plist and Mach-O minimums are 15.6. Same development Mac, not a second physical device |
| Task cleanup | Task audio player and Finder recovery window closed; independent preview exited during its Cmd-Q test. Window metadata confirmed no remaining fixture/preview windows. Existing signed-in chat and System Settings retained; original synthetic draft and PNG restored, test source selection cleared |
| Receiver / physical keyboard / headphones | Not tested. CUA-sent Cmd-Shift-R did not stop a capture, so it is not counted as physical global-hotkey evidence; toolbar stop and actual timeout passed. Retest real keys, headphones and receiver separately |
| macOS 15.6 / 27 | Adapted, runtime not tested; local-language capability is checked on each device |

## Reproduce and finish physical-device checks

1. Clone/update, build with `bash scripts/dev.sh`, or launch an existing build with `bash scripts/launch.sh`. Grant the main app's screen/system-audio permission and prepare the desired language before sharing.
2. Choose the actual meeting app. In another app, press Cmd-Shift-R, play a non-sensitive English or Mandarin question, then press the shortcut again. Verify capture stops, the original draft/attachments remain, appended text is correct, and no message was sent. Repeat with headphones and with a second recording.
3. Keep another app playing different audio while recording the selected app. Verify unrelated speech is absent. Browser selection includes other tabs and does not separate participants.
4. Let a clip reach 120 seconds. Test Cancel, hidden/minimized windows, Chinese composition, chat navigation, source exit, lock and sleep. Check that interrupted recordings require manual review and never restart themselves.
5. Toggle Normal/Legacy, inspect the Dock, use Cmd-Shift-M from another app, restore after close/minimize, and try a deliberate shortcut conflict. User-pinned Dock tiles need manual unpinning. No menu-bar icon is added.
6. In Teams desktop entire-screen sharing, use an independent Chrome receiver for three repetitions. Check the main window, transcript area, menus/prompts, mode changes and other windows updating. System recording indicators, IME panels and unrelated system UI are separate observations.

Optional developer recognition fixture check: point `CAPTURESHIELD_SYNTHETIC_SPEECH_DIR` at a directory containing task-generated `english.aiff` and `chinese.aiff` saying seven plus five, then run `bash scripts/test.sh --filter LocalSpeechFixtureTests`. The normal test run skips this opt-in test. Never use real meeting audio as a repository fixture.
