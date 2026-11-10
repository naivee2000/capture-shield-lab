# CaptureShield Lab

A small, editable macOS experiment: can a window remain visible locally while disappearing from a full-display capture?

**Experimental. No universal invisibility claim. No ChatGPT integration yet.**
The first release compares four window configurations and provides a separate, unfiltered ScreenCaptureKit recorder. Meeting compatibility must be tested on the receiving side; a local screenshot is not proof that Zoom, Meet, or Teams will behave the same way.

## Requirements

- Apple Silicon Mac, macOS 26 or later. A newer OS is not automatically a verified OS.
- Apple Command Line Tools with Swift 6.2 or later. Full Xcode is optional.
- Access to the private GitHub repository, naivee2000/capture-shield-lab.
- Screen Recording permission for **CaptureProbe** when running capture tests. The lab window itself does not request recording, microphone, camera, Accessibility, or Input Monitoring access.

## First setup

Install the Apple tools if necessary:

~~~bash
xcode-select --install
~~~

Clone using an authenticated GitHub CLI:

~~~bash
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

## Use the lab

The four modes are:

| Mode | Purpose |
| --- | --- |
| Ordinary | A visible capture control |
| Legacy sharing | Tests NSWindow.sharingType = .none; not trusted as protection |
| Mask control | Identical video-layer mask with protection disabled |
| Protected mask | AVSampleBufferDisplayLayer.preventsCapture enabled |

Drag the header to move the window. Drag the lower-right grip to resize. Type and scroll in the editor. The Hide button hides the panel for three seconds; the application menu also offers Show/Hide and Quit. Only use synthetic text.

The mask uses a generated opaque BGRA frame. Rendering errors and sleep/session interruptions hide the protected content instead of falling back to an unprotected window. Relaunch and retest after an interruption.

System menus, input-method candidate windows, the Dock, window listings, processes, the pointer, and unrelated application windows are outside the protection claim. No private APIs, injection into ChatGPT, or changes to system security settings are used.

## Run the independent capture test

~~~bash
bash scripts/verify.sh
~~~

1. Close private windows on the display you will test. The verifier receives the full display in memory and saves cropped test-region evidence locally.
2. Select the display and capture order, then click **Start capture test**.
3. Grant CaptureProbe permission in System Settings → Privacy & Security → Screen & System Audio Recording if prompted. Quit and reopen CaptureProbe if macOS requires it, then start again.
4. Keep the test panel still during the automatic run. A checkerboard fills the test display; a changing counter outside the test region keeps the stream producing fresh frames.
5. After capture stops, personally confirm that the protected panel is visible and that typing works. Use the confirmation buttons only after actually checking.
6. Repeat with the other capture order. Then follow the [manual test matrix](docs/testing.md) for movement, resizing, lifecycle changes, and meetings.

The recorder uses a full-display SCStream with an **empty exclusion list**. It does not exclude CaptureShield Lab or itself. Audio and the mouse pointer are omitted. The process crops the delivered full frame to the test rectangle plus a border, then compares it with the same area's window-hidden baseline.

Automatic trials sample 12 fresh frames at a requested 5 fps. They are evidence for those samples, not certification against sub-frame flashes. Receiver recordings and lifecycle tests are separately required.

### Interpret results

- **Control pass:** the ordinary or unprotected-mask control appeared in captured pixels.
- **Candidate pass:** all sampled pixels matched the background within recorded tolerances, both controls worked, and a person confirmed local visibility/input. This does not certify meeting applications.
- **Fail:** captured content, a black rectangle, border, shadow, or another artifact; or a person could not see/type locally.
- **Not tested:** denied permission, invalid/empty/unstable baseline, no fresh frames, missing control, changed window geometry, interrupted rendering, or missing human confirmation.

The legacy candidate remains unconfirmed unless separately checked manually. The final confirmation button applies to the protected-mask stage only.

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

The tests cover background matching, black rectangles, thin borders, malformed frames, Retina coordinates including negative display origins, stale capture timestamps, disconnected/reordered displays, latched lifecycle failures, and stale/dead lab-process evidence.

Source map:

- Sources/CaptureShieldLab — editable panel, video-layer protection, lifecycle handling.
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
