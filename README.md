# CaptureShield Lab

A native ChatGPT web window and a separate macOS capture-protection lab. Can the window remain visible locally while disappearing from a full-display capture?

**Experimental. No universal invisibility claim.**
Version 0.6.4 adds packaged-application UI automation, a reusable compatibility Skill, working compact-toolbar overflow actions and a corrected 640×480 native resize minimum. It retains the macOS 15 loader repair, selected-application on-device speech transcription, compact transcription panel and mode-dependent Dock visibility. It embeds the official ChatGPT website in a persistent WKWebView with Normal/Legacy modes, screenshot cropping, confirmed image attachments and keyboard window movement. Account login and sharing compatibility must be verified on your own Mac. The lab compares four configurations and provides a separate, unfiltered ScreenCaptureKit recorder; a local screenshot does not prove Zoom, Meet or Teams behavior.

**Operator feedback:** Teams desktop entire-screen sharing from macOS 26.6.2 (25G83), viewed in Chrome: Normal visible, Legacy hidden, but Pinyin candidates visible. Receiver retesting of the candidate-panel repair is pending; this is not a blanket privacy guarantee.

**Earlier operator observation (native text lab):** on the user's personal laptop, Teams whole-screen sharing with **Legacy sharing** kept the lab window visible locally while omitting it at the receiver; other windows continued updating. **Protected mask** disappeared locally as well. WebView content requires a new test; see [observed compatibility](docs/compatibility.md).

## Requirements

- Apple Silicon Mac, **macOS 15.6 or later**, using **0.6.3 or newer** for the macOS 15 loader repair. Clean-build and synthetic native/WebKit tests passed on **15.8.2, 26.7.2 and 27.0.1**, plus local **26.6.2** regression; see [exact OS/toolchain results](docs/os-validation.md). The exact 15.6 release, real account/capture/speech behavior on older/newer systems and receiver compatibility still need device checks. A newer OS is not automatically verified.
- Build tools: **Swift 6.2+ and macOS SDK 26+**. On macOS 15.6–15.x use Xcode / Command Line Tools **26.0–26.3**; newer tool releases may require a newer OS. Full Xcode is optional.
- Access to the GitHub repository, naivee2000/capture-shield-lab (currently public).
- Screen Recording permission for **CaptureShieldLab** when you explicitly take a screenshot or record selected-application audio, and separately for **CaptureProbe** when running capture tests. The original lab does not request recording. The compatible speech engine additionally requests Speech Recognition permission when you choose Prepare language. No microphone, camera, Accessibility or Input Monitoring permission is requested.

## First setup

Install the Apple tools if necessary:

~~~bash
xcode-select --install
~~~

Install GitHub CLI using its [official macOS instructions](https://cli.github.com/), then authenticate and clone:

~~~bash
gh auth login
gh repo clone naivee2000/capture-shield-lab
cd capture-shield-lab
bash scripts/dev.sh
~~~

Or use Git with a configured GitHub SSH key:

~~~bash
git clone git@github.com:naivee2000/capture-shield-lab.git
cd capture-shield-lab
bash scripts/dev.sh
~~~

GitHub CLI is only a convenience for cloning, not an application dependency. If using it, authenticate through its normal interactive login flow. Never paste a token into source code or a command shared with others.

The build uses only Apple frameworks. It produces two locally ad-hoc signed applications in:

    ~/Library/Caches/CaptureShieldLab/Apps/
      CaptureShieldLab.app
      CaptureProbe.app

The build registers each signed app with LaunchServices and verifies its bundle identifier resolves to the current path. Registration does not grant screen-recording permission. Use a persistent local app destination, including for QA builds; `/tmp` app bundles may not resolve reliably in System Settings.

Bundles are built on the Mac's local filesystem because exFAT/SMB AppleDouble metadata can invalidate code-signature resource seals. You can keep this source repository on an external disk. A paid Apple Developer account is not required. These are local development builds, not notarized distribution binaries.

## Use ChatGPT

`bash scripts/dev.sh` builds and opens the chat window by default. For everyday use, `bash scripts/launch.sh` opens the existing app without rebuilding or changing its signature. Quit both development apps with **Cmd-Q** before rebuilding. You can also open the built CaptureShieldLab.app directly without Terminal.

- Sign in personally on the official ChatGPT page. Your account and web history remain on ChatGPT; the app does not provide its own API account or synchronize browser profiles.
- For Google-created accounts, embedded Google sign-in may be rejected. If your existing account offers it, add an OpenAI password in the official account/security settings and sign in with the same email. Never enter your Google password into an OpenAI-password field. See [OpenAI's password instructions](https://help.openai.com/en/articles/4936828-resetting-or-changing-your-chatgpt-password).
- If sign-in is blocked, stop and record the error without credentials or full authentication URLs. Opening Chrome or Safari does not automatically sign in this WebView. No cookie import, user-agent spoofing or automatic API fallback is provided.
- Chat windows use normal macOS stacking: another app can cover them. Drag the native titlebar/title text or toolbar blank space; webpage text remains selectable. Native close/minimize/zoom controls and edge resizing are available. The app remembers the outer window frame and recovers after a monitor is disconnected.
- **Normal** is an opaque dark window with regular screen sharing enabled. **Legacy** uses the existing exclusion flag and **80% background opacity** (20% transparency). Text, replies, images and native controls are no longer faded by whole-window alpha. Transparency is a local visual effect, not the hiding mechanism. WebKit background transparency uses an isolated, runtime-checked non-public appearance property; unsupported WebKit versions keep an opaque web backdrop and report the limitation. See [UI validation and limitations](docs/ui-062.md). First use defaults to Legacy; subsequent launches remember your mode. Owned popups and sheets follow the same choice.
- **A− / A+** changes page zoom from **70% to 140%**, in 10% steps. Clicking the percentage resets to **90%**. Zoom is saved and affects website text/buttons together; native window controls keep their size.
- The sidebar initially collapses; use the sidebar toolbar button or the website control to reopen it. Your explicit choice is respected during that page session. The composer has reduced spacing and a viewport-dependent 56–160 CSS-pixel text limit. Recognized image thumbnails use 56–64 CSS pixels; opening/removing the attachment remains available. Unknown page structures stay unmodified.
- Use Back, Forward, ChatGPT (home), Reload and Hide. **Cmd-Shift-M** toggles the chat windows globally. If the shortcut is already taken, the app reports it; Legacy keeps the window visible when asked to hide. Reopening the app from Finder also restores its window. Closing the main window closes its surface and hides owned popups; Show ChatGPT reopens the retained page. Cmd-Q exits.
- Text entry, selection, history and streaming replies use the website's own interface. Text paste remains plain text. Images and copied PNG/JPEG files enter a native preview before attachment; PDF, other documents and file drops remain unsupported. Downloads and camera/microphone requests are rejected. The upload callback only supplies an explicitly confirmed image to the current ChatGPT main document; it does not open a general-purpose file picker. Native web context menus and file drops are disabled; use standard keyboard shortcuts for copying (the Edit menu is also available in Normal). The website may still display features outside this build's supported scope.
- HTTPS links stay inside app-managed windows. Popups and JavaScript dialogs inherit the selected sharing mode before presentation; their window alpha stays at 1 so text remains clear. There is no automatic opening of an unprotected system browser. System UI, including IME candidates and the Dock, is outside this claim.
- **Clear login…** asks before clearing this app's local website data and closing web popups. It loses unsaved input and signs this app out; it does not delete cloud conversations or clear Chrome/Safari data.

Spelling correction, grammar checking and text replacement are disabled within this app, and known chat editors receive `spellcheck=false`, `autocorrect=off` and `writingsuggestions=false`. These settings do not disable the operating system's Chinese/other IME candidate windows. Test those separately at the receiver; no global keyboard settings are changed.

Legacy is a compatibility experiment, not a security guarantee. The main app does not detect whether your meeting receiver sees it. Use synthetic messages until you have tested the exact machine and sharing setup.

### Compatibility and updates

Open **Compatibility…** from the app menu or the button at the bottom of the window. **Auto** selects the newer screenshot API on macOS 26+ and the compatible API on 15.6–15.x. **Compatible** always selects the earlier API, useful when diagnosing an OS upgrade. The setting is saved on this Mac. On the development host's remote-control session, Compatible returned the system privacy curtain; normal desktop capture on 15.6/15.x still needs a physical-device test. Switching does not capture, upload, reset Legacy or reload the webpage; take another screenshot yourself when ready.

The panel shows the system/build, app/commit, selected implementation, recording-permission preflight and sanitized screenshot error stage/code. **Copy diagnostic summary** copies only those technical fields. A changed OS build triggers an in-window reminder to retest sharing, without changing modes. Neither the panel nor the script below certifies receiver invisibility.

```bash
bash scripts/doctor.sh   # inspect tools, app identity, signature and registration; change no settings
bash scripts/launch.sh   # open the existing build
```

See [maintenance and repair instructions](docs/maintenance.md), including compatible toolchains and the separate old-OS/receiver test checklist.

### Meeting audio to draft

Use **Record / Stop** or global **Cmd-Shift-R**. Open the waveform **Transcription** panel, then its sliders **Audio settings** button, to choose the meeting application and **English / 中文（普通话）**. Select **Prepare language** to install missing Apple language assets or authorize the older recognizer. Model preparation never records audio. Source selection and language are remembered locally; recording is always off at launch.

The panel collapses to a 36-point control strip when idle or without pending text. Recording keeps the source, elapsed time and Stop visible. Use the sliders button for source/language/preparation, the information button for details, and **Review transcript** to expand retained text. Finished retained text is editable; editing does not overwrite the chat draft. Expanded text is capped at 120 points or one quarter of the content height and scrolls internally. Closing or collapsing the panel does not discard text or stop recording. Compatibility is a shield icon in the toolbar (or its overflow); routine page status no longer reserves a footer row.

- Only the selected application's playback is captured, not the microphone. A browser source includes audio from its other tabs; application notifications and media can also be included. This does not identify or separate individual meeting participants. Use with participants' permission.
- A second press stops; the maximum is **120 seconds**. The panel shows the source, elapsed time and stop/cancel controls. App switching, closing/hiding the main window and closing the panel do not stop recording; use **Cmd-Shift-R**, reopen the panel, or Quit. Session-lock/sleep/source-exit signals stop capture without automatic restart.
- Audio is held in a bounded memory buffer and released after processing/cancellation; it is not written to audio files or sent to a speech API. macOS 26+ uses **SpeechAnalyzer / SpeechTranscriber**. macOS 15.6 uses **SFSpeechRecognizer** only if local recognition is supported, with at most 50-second requests and overlapping timestamp-based boundaries. Unsupported local languages remain unavailable: no cloud fallback. Language-model downloads require network access; prepared models should work offline.
- The final transcript is appended to the current draft, with a separating space when needed, only in the same trusted main chat. Existing text/images remain and no message is sent. Hidden/minimized windows, active Chinese composition, navigation or uncertain editor state retain a local transcript instead. Review it and choose **Add to Chat** to explicitly target the currently open chat, or **Discard**. During capture/processing, **Cancel** retains its existing cancellation behavior. Uncertain insertion disables retry to avoid duplication; inspect the draft and copy only missing text if needed.
- Interrupted/failed recordings keep completed text for manual review, not automatic insertion. No automatic recording retries or persistent transcript history. Compatibility diagnostics contain engine, selected locale, capability and error stage/code only.
- Screen/system-audio recording permission is shared with this app's Screenshot feature, but not with CaptureProbe. New signatures can invalidate an existing macOS grant. System capture indicators and permission prompts are not hidden by Legacy.

### Legacy Dock visibility

**Normal** shows the Dock icon and app menu. **Legacy** uses accessory activation: its window stays locally visible with an 80% background and undimmed contents, while the running app is removed from the Dock/app switcher and has no app menu bar. **Cmd-Shift-M** hides/shows the window; **Cmd-Q** still quits. No menu-bar icon is added. Mode changes keep the same WebView/session/draft. A user-pinned Dock tile may need to be unpinned manually; the app never edits Dock preferences.

Global hotkeys use exclusive registration and report individual conflicts. Do not run several CaptureShield builds simultaneously when checking shortcuts. If the visibility hotkey fails, Legacy refuses a Hide/close request instead of stranding the window; Finder reopen is a recovery route. The lab stays a regular app. Dock behavior does not certify receiver hiding.

### Screenshots, images and movement

- Click the camera **Screenshot** button or press **Cmd-Shift-2** to capture the display under the pointer. The app menu's **Capture Display** submenu selects a different monitor. Capture excludes this app and its owned windows and omits the pointer; it does not run continuously. If the shortcut conflicts with another app, use the toolbar/menu.
- The screenshot opens inside the chat window. Drag to crop, **Reset crop**, **Retake**, **Cancel**, or **Add to Chat**. Normal/Legacy settings also apply to the preview. Preparing or cancelling does not upload anything. **Add to Chat may start a website upload immediately; you still send the message yourself.**
- Use **Images → Paste Image** or **Cmd-V** with a copied raster image or one copied PNG/JPEG file. TIFF clipboard pixels are also accepted; no general file browser, PDF, video, camera, or drag-and-drop import is provided. The app decodes orientation, renders fresh pixels and strips source metadata. One prepared image is accepted at a time, up to **20 MiB after PNG encoding**; a larger result must be cropped. Decoding is limited to 64 megapixels/16,384 pixels per side and 100 MiB input to bound memory use. ChatGPT's own account limits still apply.
- If the current website attachment control cannot be identified, the preview collapses and the status explains how to use ChatGPT's existing **+ / attachment** control. **Images → Review prepared image** reopens the staged image to edit or cancel. Navigation invalidates its confirmation. The app never automatically retries an upload or sends a prompt, and a native handoff is not an upload-success claim. The app now distinguishes preparation, file handoff, a new composer attachment preview, upload errors and a 30-second timeout. It handles lazy file controls opened from the recognized attachment button/menu. A missing callback or preview retains your crop for recovery, with no automatic retry. Check/remove any existing attachment before confirming again; canceling the app preview cannot undo an upload that the webpage already started.
- Add multiple images by repeating **Screenshot → crop → Add to Chat**, one image per confirmation. Existing attachments and text stay in the composer. You can remove an attachment using the website and add another without reloading. Version 0.4.3 fixes a repeated-script declaration that blocked the second attachment in the same document. Website account/file limits still apply.
- Preview pixels stay in memory. Only confirmed images handed to WebKit become randomly named, mode-0600 files inside a mode-0700 application-specific temporary session directory. They stay available for that app session, are removed on exit, and abandoned sessions are cleaned at startup. Active sessions are protected by a file lock. No screenshot history, desktop export or automatic clipboard write is created.
- **Cmd-Shift-Up/Down/Left/Right** moves the foreground chat window by **40 logical points**, with key repeat. The frame stays on its current monitor; drag to cross monitors. The position is remembered. Standard Cmd-arrow editing remains available. Cmd-Shift-arrow selection is deliberately replaced by window movement outside composition. Active or unknown native/web composition and modal dialogs keep their keys.

If Screenshot reports denied access, grant permission to **CaptureShieldLab**, not CaptureProbe. In the System Settings app picker, press **Cmd-Shift-G**, enter `~/Library/Caches/CaptureShieldLab/Apps/`, and select **CaptureShieldLab.app**. Enable its switch and quit/reopen that exact built app if macOS requests it; opening the `.app` directly avoids another rebuild/signature change. If an old entry still fails, remove only that app's stale entry and add the current bundle again. Administrator authentication may be required; never disable system protections. The two apps have distinct purposes and permissions cannot be combined.

Grant screenshot permission before a meeting if possible: System Settings → Privacy & Security → Screen & System Audio Recording → CaptureShieldLab. After a denial the app will explain how to enable it rather than repeatedly prompting. System permission panels, capture indicators, menus and IME candidate windows are outside the Legacy window claim.

### Private Cursor: offline experiment only

**The normal ChatGPT build keeps Private Cursor unavailable until receiver tests establish compatibility.** It is off at every launch. To test without account data, quit the running development build and run:

~~~bash
bash scripts/dev.sh --chat-preview
~~~

Select **Legacy**, then the cursor-arrow toolbar toggle or **Cmd-Shift-C**. The experiment draws a local arrow in a mouse-transparent app-owned overlay before hiding the system cursor. It only activates over visible, unobstructed owned windows while this app is foreground. It restores the system cursor on leaving, loss of focus, hiding/minimizing, mode changes, menus, sleep or exit. **Esc** turns the experiment off and continues to the active UI's cancellation handling. A failure to establish the local pointer leaves the normal pointer in place. No system-wide cursor feature is provided.

This tests a hypothesis, not a verified privacy feature: meeting clients may collect cursor shape/position separately. Both physical local visibility and an independent receiver recording are needed. A hidden pointer in a local screenshot is insufficient. The app menu's **Load sample image (offline)** supplies an innocuous image for crop/attachment checks without changing the clipboard.

### Another computer

On each supported Mac, clone the same repository and run `bash scripts/dev.sh`. Sign in to ChatGPT on that Mac yourself. Grant CaptureShieldLab screen-recording permission if you take screenshots, and CaptureProbe permission separately if you run capture tests. Git does not transfer login data, cookies, permissions, window preferences or recordings.

To update, quit both apps, preserve any local source edits, then run:

~~~bash
git pull --ff-only
bash scripts/dev.sh
~~~

Do not use a hard reset to resolve divergence. New source builds and OS/meeting-app updates require retesting. For isolated build verification, `CAPTURESHIELD_APP_ROOT=/an/absolute/local/path bash scripts/build.sh` changes the generated bundle destination. Adding `CAPTURESHIELD_BUNDLE_PREFIX=dev.example.captureshield.qa` also isolates the app identifiers and website storage; retain the normal prefix for everyday builds and permission continuity.

## Offline UI preview and icon

For repeatable testing of the **packaged app** on macOS 15.8.2–27.x, see [UI automation and cleanup](docs/ui-validation.md). Run `bash scripts/test-ui.sh --preflight` with full Xcode, then `bash scripts/test-ui.sh` for three sequential offline rounds. This is separate from the ordinary CLT build and from real meeting/ChatGPT acceptance. The project [compatibility Skill](.agents/skills/capture-shield-compatibility/SKILL.md) is included in every clone.

Run `bash scripts/dev.sh --chat-preview` for the normal chat window with a disposable offline page, synthetic popup/dialog controls and separate preview preferences. It does not load your account. Record in this preview uses a clearly labelled synthetic source and transcript, without audio capture or speech-model preparation. Use the normal app for real audio acceptance. The original capture lab remains available separately.

The original shield/window icon is bundled into both apps. `Assets/` contains the editable SVG, a PNG preview and the `.icns` used by the build. `scripts/render-icon.swift` is the editable vector generator; regenerate all formats with:

~~~bash
xcrun swift scripts/render-icon.swift Assets
~~~

The generator uses only Apple frameworks and `iconutil`. Normal builds copy the committed icon and need no graphics packages.

## Use the lab

~~~bash
bash scripts/dev.sh --lab
# Or an offline, disposable WebView with no account data:
bash scripts/dev.sh --web-test
~~~

The four modes are:

| Mode | Purpose |
| --- | --- |
| Ordinary | A visible capture control |
| Legacy sharing | Tests NSWindow.sharingType = .none; desired visibility behavior reported in one Teams whole-screen setup, without a general platform guarantee |
| Mask control | Identical video-layer mask with protection disabled |
| Protected mask | AVSampleBufferDisplayLayer.preventsCapture enabled |

Drag the header to move the window. Drag the lower-right grip to resize. Type and scroll in the editor. The Hide button hides the panel for three seconds; the application menu also offers Show/Hide and Quit. Only use synthetic text.

The mask uses a generated opaque BGRA frame. Rendering errors and sleep/session interruptions hide the protected content instead of falling back to an unprotected window. Relaunch and retest after an interruption.

System menus, input-method candidate windows, the Dock, window listings, processes, the pointer, and unrelated application windows are outside the protection claim. No private WindowServer APIs, injection into another process, or changes to system security settings are used. The chat window uses a small, scoped presentation script inside its own WebView.

## Run the independent capture test

~~~bash
bash scripts/verify.sh
~~~

1. Close private windows on the display you will test. The verifier receives the full display in memory and saves cropped test-region evidence locally.
2. Select the display, capture order and **Synthetic WebView** or **Native text editor**, then click **Start capture test**. The WebView uses an ephemeral store and offline HTML; it never loads your real ChatGPT session.
3. Grant CaptureProbe permission in System Settings → Privacy & Security → Screen & System Audio Recording if prompted. Quit and reopen CaptureProbe if macOS requires it, then start again.
4. Keep the test panel still during the automatic run. A checkerboard fills the test display; a changing counter outside the test region keeps the stream producing fresh frames.
5. After capture stops, the Legacy panel is shown. Personally confirm that it is visible and accepts typing; use the confirmation buttons only after checking the actual screen. Select **Protected mask** to show and confirm that candidate separately.
6. Repeat with the other capture order. Then follow the [manual test matrix](docs/testing.md) for movement, resizing, lifecycle changes, and meetings.

The recorder uses a full-display SCStream with an **empty exclusion list**. It does not exclude CaptureShield Lab or itself. Audio and the mouse pointer are omitted. The process crops the delivered full frame to the test rectangle plus a border, then compares it with the same area's window-hidden baseline.

Automatic trials sample 12 fresh frames at a requested 5 fps. They are evidence for those samples, not certification against sub-frame flashes. Receiver recordings and lifecycle tests are separately required.


### Chinese input and candidate panels

The macOS 26.6.2 reproduction identified the Pinyin candidate strip as an app-hosted `NSPanel` with a separate WindowServer ID and a default shareable setting. The repair applies Legacy sharing to app-owned `NSPanel` instances before their public `order(_:relativeTo:)` call is forwarded, and updates existing panels on mode changes. This uses process-local Objective-C method interposition on a public AppKit method; it does not call private selectors, manipulate another process, force candidate selection or replace the input method. Framework behavior can change: actual first-appearance and mode-switch frames still require receiver testing. Panel geometry, level and input behavior are preserved. Other-process/system UI, keyboard predictors and recording indicators are not certified hidden.

Until your receiver confirms the result, use either (1) Chinese composition on an **unshared display / another device**, followed by pasting committed text, or (2) **Teams sharing only the business window**. Check the receiver in each setup. These are alternative workflows, not proof that whole-screen candidate leakage is fixed.

For metadata-only diagnosis, run `xcrun swift scripts/window-metadata.swift` before/during/after a synthetic candidate popup. It prints window IDs, PIDs, bundle IDs, levels and bounds, never titles or input. Launching the app executable with `CAPTURESHIELD_WINDOW_DIAGNOSTICS=1` additionally prints its public NSWindow metadata to stderr. Keep output outside Git. Build identity is in the bundle Info.plist (`CFBundleShortVersionString`, `CFBundleVersion`, `CaptureShieldBuildCommit`). See [repair evidence](docs/repair-041.md).

### Record a manual cursor trial

In CaptureProbe, choose the test display and click **Record full display + cursor**. Confirm only after placing synthetic content on that display and closing private material. This separate path records an **unfiltered entire display with `showsCursor = true`**, no audio and no click indicator, at a requested 30 fps. Output width is capped at 4096 pixels with proportional even height. It does not exclude this app or infer a pass from absent pixels.

Use the offline preview to compare cursor off/on, movement, clicks, cropping and restoration. Stop with **Stop cursor recording** or the app menu; it also stops after two minutes. Stop, auto-stop and Quit share the same finalization task. The MP4 and a configuration/status JSON stay in a `cursor-<id>` report subfolder. The verdict remains **not-tested** pending human review and the separate meeting receiver trials. System menus/indicators and other visible windows are included; do not record private conversations.

### Interpret results

- **Control pass:** the ordinary or unprotected-mask control appeared in captured pixels.
- **Candidate pass:** all sampled pixels matched the background within recorded tolerances, both controls worked, and a person confirmed local visibility/input. This does not certify meeting applications.
- **Fail:** captured content, a black rectangle, border, shadow, or another artifact; or a person could not see/type locally.
- **Not tested:** denied permission, invalid/empty/unstable baseline, no fresh frames, missing control, changed window geometry, interrupted rendering, or missing human confirmation.

Confirmation applies only to the selected candidate and requires its current mode/geometry/heartbeat to match. Remote-desktop viewing is another capture path and cannot substitute for a physical local check.

Reports (JSON and Markdown) and cropped PNGs go into the repository's ignored artifacts/ directory. If macOS relaunches the app without its command-line arguments, reports fall back to:

    ~/Library/Application Support/CaptureShieldLab/Reports/

Use **Open report folder** to find the current run. Nothing is uploaded automatically. Review every artifact before sharing; private windows accidentally moved over the test area can appear in evidence.

## Edit, test, and sync

Quit the running development apps before rebuilding:

~~~bash
bash scripts/dev.sh
bash scripts/test.sh
~~~

The test script runs Swift Testing without external dependencies. [Cross-version CI and its evidence boundaries](docs/os-validation.md) cover clean Apple Silicon builds and synthetic AppKit/WebKit tests on macOS 15, 26 and 27. This is separate from device and receiver validation. The script adds framework lookup flags on affected Command Line Tools installations and disables a missing optional Foundation overlay. A correctly configured full Xcode/toolchain also supports:

~~~bash
swift test
~~~

The tests cover background matching, black rectangles, thin borders, malformed frames, Retina coordinates including negative display origins, stale capture timestamps, disconnected/reordered displays, latched lifecycle failures, stale/dead lab evidence, synthetic launch routing, navigation boundaries, persistent appearance preferences and window restoration. AppKit/WebKit integration tests also exercise normal-window chrome, sheet configuration, delayed sidebar initialization, replacement editors and authentication/unknown-page isolation. Image tests additionally exercise native WebKit upload, unchanged drafts/no automatic send, stale-document rejection, crop coordinates, orientation/metadata handling, oversized images, locked temporary sessions and preview recovery. Cursor/keyboard tests cover eligibility, balanced hide/show calls, IME/modal guards, cursor-included recorder configuration and cancellation-independent recording finalization. These tests use disposable synthetic pages and close their own windows.

Source map:

- Sources/CaptureShieldLab — ChatGPT window, protected popups, synthetic native/WebView lab, video-layer protection.
- Sources/CaptureProbe — independent full-display stream, experiment runner, local reports.
- Sources/CaptureCore — shared messages, pixel analysis, result gates.
- Tests/CaptureCoreTests — deterministic behavioral tests.
- scripts — build, run, verification, and test entry points.

Before pulling updates, inspect and preserve your own edits:

~~~bash
git status
git pull --ff-only
bash scripts/dev.sh
~~~

Use a separate branch for changes you want to keep. If Git reports local changes or divergence, resolve them explicitly; do not use a hard reset to update. Application data and recordings are not synchronized by Git.

Rebuilding can change an ad-hoc signature; macOS may request permission again. Recheck the permission for the app performing capture: CaptureShieldLab for Screenshot, CaptureProbe for verification. If toggling it does not refresh a stale registration, quit CaptureProbe, remove only its entry using System Settings, add the current app from the build-cache folder, enable it, then relaunch. macOS may require your administrator password. Do not disable Gatekeeper or reset the system permission database.

## Evidence and limitations

The real screenshot → crop → ChatGPT attachment path was exercised with a synthetic question and an unchanged draft. Manual sending/image understanding and meeting receiver checks remain separate; see [0.4.2 evidence](docs/attachment-042.md).

Read [observed compatibility](docs/compatibility.md), [research](docs/research.md), [testing](docs/testing.md), and [implementation notes](docs/implementation.md). Compatibility is always specific to the macOS build, capture application/version, and capture mode. Do not use this project as a claim of being undetectable by every application.
