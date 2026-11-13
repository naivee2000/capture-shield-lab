# Packaged application UI validation

This suite launches the **actual `.app` built by `scripts/build.sh`** with Apple's `XCUIApplication(url:)`. The separate Xcode project compiles only the UI test runner, not a second application. XCTest drives native controls, keyboard input, crop drags and WebKit upload callbacks. A successful build alone is not a UI result.

## Run on another Mac

Use Apple Silicon and an actual macOS version from **15.8.2 through 27.x**. This is the review range; the application deployment minimum remains **15.6**. Install a full Xcode version compatible with that host and Swift 6.2 or newer. Command Line Tools remain sufficient for ordinary app builds but do not include the XCTest UI runner.

```bash
gh repo clone naivee2000/capture-shield-lab
cd capture-shield-lab
# Optional: select an installed full Xcode for this shell only.
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
bash scripts/test-ui.sh --preflight
bash scripts/test.sh --no-parallel
python3 -m unittest discover -s Tests/ScriptTests -v
bash scripts/test-ui.sh
```

Use an unlocked graphical test session with no other CaptureShield instance running. Preserve any personal draft before closing your app yourself. The preflight does not quit apps, change permissions or install Xcode. It reports missing prerequisites as `not-tested` (exit 2). UI authorization is established only when XCTest actually launches; a successful preflight cannot attest to it. Complete legitimate system authorization locally if requested. Never patch TCC, disable SIP or grant capture permission merely to make this offline suite pass.

The test command prints a run ID. It creates unique application identifiers under `dev.naivee2000.captureshield.uitest`, independent preview defaults, a nonpersistent WebKit store and synthetic image/voice fixtures. A per-test launch token seeds a fixed set of preview preferences inside that process, avoiding cross-process preferences-container differences; relaunch with the same token preserves changes made by the test. Seeding is unavailable to normal application identifiers or normal chat mode. It does not open the normal account store, capture the screen, use the microphone, record meeting audio, download speech models or contact ChatGPT. The application still uses the production attachment coordinator, public file-picker delegate, draft insertion and window settings. Only offline speech input/results are substituted.

On APFS, generated apps, Swift build files and DerivedData go under the run's ignored workspace. On exFAT, the runner creates a sparse APFS image in that workspace and mounts it under `/Volumes/CaptureShieldUI-<run-id>`. Its 80-GiB maximum is not preallocated. Nothing formats or repartitions the external disk. Signing failures stop the run. Paths are derived from the checkout/run ID and work when the checkout contains spaces; no SANDISK or developer-home path is required.

## Checks and verdicts

The default run performs **three sequential rounds**, without parallel UI execution or failure retries. Seven test cases cover:

- Packaged process launch, editable WebKit input, quit and restart.
- Normal/Legacy sharing attributes, whole-window/content alpha, background alpha, Dock activation policy, 70/90/140% zoom, popup inheritance, dialogs and draft preservation.
- Native title-bar dragging, resize to 640×480, multiline editing, selection/undo, scroll and frame restoration; the other cases start at 980×700.
- Real image preview/crop/reset/cancel, three consecutive synthetic file handoffs, visible image dimensions/counts, deletion/re-addition, unchanged draft and no automatic send.
- Compact-window movement, synthetic composition blocking, global hide/show with Finder foreground, minimize/restore.
- Synthetic transcription idle/recording/cancel/processing/completed states, append exactly once, existing draft and attachment preservation.
- Synthetic recognition error, retained editable transcript, folding/reopening and explicit add.

Read-only native metadata supplements visible UI assertions for window geometry, sharing settings and alpha. That output is enabled only for an isolated UI-test bundle launched with `--chat-preview`. It contains no page text and exposes no application-control commands. An actual image decoded by the offline webpage is required after file handoff; returning a file URL alone is insufficient.

The JSON summary records actual OS/build, architecture, source commit, toolchain, app version/build/hash, each round's counts and failure stage. Exit 0 means all expected UI cases passed in every requested round. Zero, skipped, partial or unknown counts fail. Exit 1 means failure; exit 2 means a missing environment or UI-authorization prerequisite. The first failed round is retained and subsequent rounds do not run. Separate `real_capture`, `real_speech`, `real_chatgpt` and `receiver` fields stay `not-tested`.

To check the harness itself:

```bash
bash scripts/test-ui.sh --negative --repeat 1
```

This deliberately requires an absent control in the launch test. **Expected: exit 1**, one failed assertion, and `negative_control_expected_failure: true`. An authorization failure, missing executable or zero tests cannot satisfy that control. CI verifies this separately after a successful full run. Script tests additionally reject a wrong app identity/path and unsafe cleanup requests.

An application defect needs a reproducible failed behavior, a scoped fix and a new run. A test selector or resource-preparation defect is a harness issue. Unavailable Xcode, locked sessions, authorization restrictions or absent OS images are environment limits. Do not erase the first failure or rerun unchanged failures until they happen to pass.

## Evidence that still needs devices

Hosted UI tests do not establish real ChatGPT login/upload success, actual screenshot pixels, audio filtering or speech quality. Unicode text and synthetic composition do not establish physical Pinyin candidate behavior. Alpha and sharing properties do not establish local physical appearance or receiver hiding. Use [the device/receiver matrix](testing.md), record sender/receiver OS and client versions, and repeat full-display trials three times. Existing user success reports remain scoped to their original environment.

Check real screenshot → crop → visible attachment, keep a preexisting draft, add/delete/re-add images, then manually send a harmless image to verify interpretation. For voice, use harmless English/Mandarin audio, verify app filtering and no microphone, stop/cancel, draft preservation and manual editing. For Teams, independently observe Normal/Legacy, candidates, popups, background continuity, other windows and mode transitions. Keep Private Cursor restricted to the offline experiment until receiver evidence supports enabling it.

## Clean only registered test resources

Copy the sanitized summary into the review ledger before deleting raw evidence. Raw logs, xcresult, screenshots and recordings stay ignored and must not be committed.

```bash
bash scripts/cleanup-tests.sh --dry-run
bash scripts/cleanup-tests.sh --run-id uiYOUR-PRINTED-RUN-ID
```

Cleanup accepts a registered run ID, not an arbitrary deletion path. It validates ownership, summary, canonical paths and use state, refuses uncertain inspection or nested mounts, does not follow build-product symlinks, unregisters only that run's test apps, detaches its verified image, and removes its build/raw evidence, attachment directory and preview preferences. Technical summary and ownership manifest remain. It reports allocated bytes, not the sparse image's maximum size. A still-running test or unfinished run is retained for inspection; cleanup does not kill it. Close only windows created for this test.

Old unregistered QA builds and shared caches require a separate inventory and proof that no process uses them. Never delete the normal app, active QA042, website/login storage, another project's cache or unknown files. CI's ephemeral runner is discarded after its job; the workflow retains only sanitized GitHub log/summary evidence and no uploaded raw xcresult artifact.

The repository-local [compatibility skill](../.agents/skills/capture-shield-compatibility/SKILL.md) routes future reviews to these same commands. No global skill installation is required.

Reference: [Apple XCUIApplication URL initializer](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(url:)-90e7z).
