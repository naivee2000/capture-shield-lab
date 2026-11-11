# CaptureShield Lab

A native ChatGPT web window and a separate macOS capture-protection lab. Can the window remain visible locally while disappearing from a full-display capture?

**Experimental. No universal invisibility claim.**
Version 0.4 embeds the official ChatGPT website in a persistent WKWebView with Normal/Legacy modes, screenshot cropping, confirmed image attachments and keyboard window movement. Account login and sharing compatibility must be verified on your own Mac. The lab compares four configurations and provides a separate, unfiltered ScreenCaptureKit recorder; a local screenshot does not prove Zoom, Meet or Teams behavior.

**Latest operator feedback (2026-11-11):** Legacy hid the current chat window from the other participant in the user's sharing setup. Client/OS details and repeat counts were not supplied; this does not certify the newer window, image-preview or cursor behavior.

**Earlier operator observation (native text lab):** on the user's personal laptop, Teams whole-screen sharing with **Legacy sharing** kept the lab window visible locally while omitting it at the receiver; other windows continued updating. **Protected mask** disappeared locally as well. WebView content requires a new test; see [observed compatibility](docs/compatibility.md).

## Requirements

- Apple Silicon Mac, macOS 26 or later. A newer OS is not automatically a verified OS.
- Apple Command Line Tools with Swift 6.2 or later. Full Xcode is optional.
- Access to the private GitHub repository, naivee2000/capture-shield-lab.
- Screen Recording permission for **CaptureShieldLab** when you explicitly take a screenshot, and separately for **CaptureProbe** when running capture tests. The original lab does not request recording. No microphone, camera, Accessibility or Input Monitoring permission is requested.

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

Bundles are built on the Mac's local filesystem because exFAT/SMB AppleDouble metadata can invalidate code-signature resource seals. You can keep this source repository on an external disk. A paid Apple Developer account is not required. These are local development builds, not notarized distribution binaries.

## Use ChatGPT

`bash scripts/dev.sh` opens the chat window by default. Quit both development apps with **Cmd-Q** before rebuilding. You can also open the built CaptureShieldLab.app directly without Terminal.

- Sign in personally on the official ChatGPT page. Your account and web history remain on ChatGPT; the app does not provide its own API account or synchronize browser profiles.
- For Google-created accounts, embedded Google sign-in may be rejected. If your existing account offers it, add an OpenAI password in the official account/security settings and sign in with the same email. Never enter your Google password into an OpenAI-password field. See [OpenAI's password instructions](https://help.openai.com/en/articles/4936828-resetting-or-changing-your-chatgpt-password).
- If sign-in is blocked, stop and record the error without credentials or full authentication URLs. Opening Chrome or Safari does not automatically sign in this WebView. No cookie import, user-agent spoofing or automatic API fallback is provided.
- Chat windows use normal macOS stacking: another app can cover them. Drag the native titlebar/title text or toolbar blank space; webpage text remains selectable. Native close/minimize/zoom controls and edge resizing are available. The app remembers the outer window frame and recovers after a monitor is disconnected.
- **Normal** is an opaque dark window with regular screen sharing enabled. **Legacy** uses the existing exclusion flag and **80% whole-window opacity** (20% transparency). Opacity is a local visual effect, not the hiding mechanism. First use defaults to Legacy; subsequent launches remember your mode. Owned popups and sheets follow the same choice.
- **A− / A+** changes page zoom from **70% to 140%**, in 10% steps. Clicking the percentage resets to **90%**. Zoom is saved and affects website text/buttons together; native window controls keep their size.
- The sidebar initially collapses; use the sidebar toolbar button or the website control to reopen it. Your explicit choice is respected during that page session. The composer has reduced spacing and a 160 CSS-pixel scrolling limit. Unknown page structures stay unmodified.
- Use Back, Forward, ChatGPT (home), Reload and Hide. **Cmd-Shift-Space** toggles the chat windows globally. If the shortcut is already taken, use the app menu's Show/Hide commands. Closing the main window closes its surface and hides owned popups; Show ChatGPT reopens the retained page. Cmd-Q exits.
- Text entry, selection, history and streaming replies use the website's own interface. Text paste remains plain text. Images and copied PNG/JPEG files enter a native preview before attachment; PDF, other documents and file drops remain unsupported. Downloads and camera/microphone requests are rejected. The upload callback only supplies an explicitly confirmed image to the current ChatGPT main document; it does not open a general-purpose file picker. Native web context menus and file drops are disabled; use the Edit menu or keyboard shortcuts for copying. The website may still display features outside this build's supported scope.
- HTTPS links stay inside app-managed windows. Popups and JavaScript dialogs inherit the selected sharing mode and opacity before presentation. There is no automatic opening of an unprotected system browser. System UI, including IME candidates and the Dock, is outside this claim.
- **Clear login…** asks before clearing this app's local website data and closing web popups. It loses unsaved input and signs this app out; it does not delete cloud conversations or clear Chrome/Safari data.

Spelling correction, grammar checking and text replacement are disabled within this app, and known chat editors receive `spellcheck=false`, `autocorrect=off` and `writingsuggestions=false`. These settings do not disable the operating system's Chinese/other IME candidate windows. Test those separately at the receiver; no global keyboard settings are changed.

Legacy is a compatibility experiment, not a security guarantee. The main app does not detect whether your meeting receiver sees it. Use synthetic messages until you have tested the exact machine and sharing setup.

### Screenshots, images and movement

- Click the camera **Screenshot** button or press **Cmd-Shift-2** to capture the display under the pointer. The app menu's **Capture Display** submenu selects a different monitor. Capture excludes this app and its owned windows and omits the pointer; it does not run continuously. If the shortcut conflicts with another app, use the toolbar/menu.
- The screenshot opens inside the chat window. Drag to crop, **Reset crop**, **Retake**, **Cancel**, or **Add to Chat**. Normal/Legacy settings also apply to the preview. Preparing or cancelling does not upload anything. **Add to Chat may start a website upload immediately; you still send the message yourself.**
- Use **Paste Image** or **Cmd-V** with a copied raster image or one copied PNG/JPEG file. TIFF clipboard pixels are also accepted; no general file browser, PDF, video, camera, or drag-and-drop import is provided. The app decodes orientation, renders fresh pixels and strips source metadata. One prepared image is accepted at a time, up to **20 MiB after PNG encoding**; a larger result must be cropped. Decoding is limited to 64 megapixels/16,384 pixels per side and 100 MiB input to bound memory use. ChatGPT's own account limits still apply.
- If the current website attachment control cannot be identified, the preview collapses and the status explains how to use ChatGPT's existing **+ / attachment** control. **Image Preview** reopens the staged image to edit or cancel. Navigation invalidates its confirmation. The app never automatically retries an upload or sends a prompt, and a native handoff is not an upload-success claim: check the website's attachment/error state.
- Preview pixels stay in memory. Only confirmed images handed to WebKit become randomly named, mode-0600 files inside a mode-0700 application-specific temporary session directory. They stay available for that app session, are removed on exit, and abandoned sessions are cleaned at startup. Active sessions are protected by a file lock. No screenshot history, desktop export or automatic clipboard write is created.
- **Cmd-Option-Up/Down/Left/Right** moves the foreground chat window by **40 logical points**, with key repeat. The frame stays on its current monitor; drag to cross monitors. The position is remembered. Standard Cmd-arrow editing remains available, and IME composition/modal dialogs keep their keys.

Grant screenshot permission before a meeting if possible: System Settings → Privacy & Security → Screen & System Audio Recording → CaptureShieldLab. After a denial the app will explain how to enable it rather than repeatedly prompting. System permission panels, capture indicators, menus and IME candidate windows are outside the Legacy window claim.

### Private Cursor: offline experiment only

**The normal ChatGPT build keeps Private Cursor unavailable until receiver tests establish compatibility.** It is off at every launch. To test without account data, quit the running development build and run:

~~~bash
bash scripts/dev.sh --chat-preview
~~~

Select **Legacy**, then the cursor-arrow toolbar toggle or **Cmd-Option-C**. The experiment draws a local arrow in a mouse-transparent app-owned overlay before hiding the system cursor. It only activates over visible, unobstructed owned windows while this app is foreground. It restores the system cursor on leaving, loss of focus, hiding/minimizing, mode changes, menus, sleep or exit. **Esc** turns the experiment off and continues to the active UI's cancellation handling. A failure to establish the local pointer leaves the normal pointer in place. No system-wide cursor feature is provided.

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

Run `bash scripts/dev.sh --chat-preview` for the normal chat window with a disposable offline page, synthetic popup/dialog controls and separate preview preferences. It does not load your account. The original capture lab remains available separately.

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

The test script runs Swift Testing without external dependencies. It adds framework lookup flags on affected Command Line Tools installations and disables a missing optional Foundation overlay. A correctly configured full Xcode/toolchain also supports:

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

Rebuilding can change an ad-hoc signature; macOS may request permission again. Recheck CaptureProbe's permission if capture stops working. If toggling it does not refresh a stale registration, quit CaptureProbe, remove only its entry using System Settings, add the current app from the build-cache folder, enable it, then relaunch. macOS may require your administrator password. Do not disable Gatekeeper or reset the system permission database.

## Evidence and limitations

Read [observed compatibility](docs/compatibility.md), [research](docs/research.md), [testing](docs/testing.md), and [implementation notes](docs/implementation.md). Compatibility is always specific to the macOS build, capture application/version, and capture mode. Do not use this project as a claim of being undetectable by every application.
