# Cross-version macOS validation

The supported deployment floor is **Apple Silicon macOS 15.6**. Compiling with a newer SDK does not raise that runtime floor. macOS 14 and 15.0–15.5, Intel Macs, Windows and Linux are outside the current target. A successful version-policy unit test is not a test executed on that operating system.

## Repeatable checks

The [macOS compatibility workflow](../.github/workflows/macos-compatibility.yml) uses independent, clean GitHub-hosted Apple Silicon machines:

| Runner label | OS family asserted at runtime | Selected Xcode |
| --- | --- | --- |
| `macos-15` | 15 | 26.3 |
| `macos-26` | 26 | 26.6 |
| `xcode-27` | 27 | 27.2 |

These are standard runners, [free for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories). The workflow does not use paid large/xlarge runners, secrets, saved accounts or screen/audio captures. It runs on relevant source changes and can be started manually from **Actions → macOS compatibility → Run workflow**. No scheduled job is installed. If a pinned Xcode is removed from a runner image, select a documented replacement; do not silently use an incompatible default. Xcode 26.3 is specifically selected on macOS 15 because its default Xcode 16 is too old for this project.

Each job records the actual OS version/build, architecture, Xcode, Swift, SDK and source commit, builds both apps, signs and registers them, runs the existing behavioral/AppKit/WebKit test suite, and checks both Info.plist and Mach-O minimum versions. Bundle output uses a path containing spaces, separate from the checkout. There is no build cache or dependency on this developer's app data. Optional real-speech/model fixtures and UI image export are not enabled. Tests close their own synthetic windows; no capture permissions are granted.

The local equivalent, using a separate output location, is:

```bash
export CAPTURESHIELD_APP_ROOT="$HOME/Library/Caches/CaptureShield Compatibility/Apps"
export CAPTURESHIELD_BUNDLE_PREFIX=dev.naivee2000.captureshield.compatibility
bash scripts/build.sh
bash scripts/test.sh --no-parallel
bash scripts/doctor.sh
```

## Evidence boundary

CI can detect unavailable APIs, dynamic-linking failures, compiler changes and failures in synthetic native/WebKit behavior, including background alpha, attachment handoff, draft preservation and layout. A hosted macOS 15.x job does not test the exact 15.6 release unless its recorded host version says 15.6. A later patch release is likewise not evidence for every earlier or future patch.

Real ChatGPT login and attachment upload, screen/audio permissions, screenshot pixels, language models/recognition and Chinese input must also be checked on the actual device. Normal/Legacy visibility requires a separately observed meeting receiver. In particular, the non-public WebKit background hook and app-hosted candidate-panel handling remain OS-dependent. A pass does not promise that every future macOS or meeting-app version will work.

Before sharing after an OS upgrade: run the tests, use a harmless image to check screenshot/crop/attachment, confirm English/Mandarin transcription if needed, then compare Normal/Legacy at the receiver (including candidates, popups and other windows). Record exact sender OS/build and sender/receiver application versions. Preserve failed or untested outcomes.

## macOS 15 loader repair (0.6.3)

The [first cross-version run](https://github.com/naivee2000/capture-shield-lab/actions/runs/43489492935), at `bb8688a`, exposed a real pre-main failure on macOS **15.8.2 (24H232)**. Both apps built and signed, but loading the native test bundle failed with `Symbol not found: _OBJC_CLASS_$_SCScreenshotConfiguration`. Inspection of the application executable also showed strong references to both `SCScreenshotConfiguration` and `SCScreenshotOutput`, which are absent on macOS 15. The source's `@available`/`#available` guards alone did not fix that load-time requirement with SDK 26.2.

Version **0.6.3/build 12** explicitly weak-links ScreenCaptureKit for the app target (also propagated to its test bundle), following [Apple's weak-linking guidance](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/WeakLinking.html). Modern screenshot calls remain inside the existing macOS 26 availability gate; macOS 15 still selects the compatible backend. No SDK files or user settings are patched. `scripts/check-linkage.sh` inspects the actual binary and stops packaging if these new classes are strongly required again; it rejected the original binary and accepted the repaired binary and test bundle.

## Run ledger

Repaired source: **`5ca68ebf0e44a27d8353ff436750504d9dc5204a`**, [run 43490166026](https://github.com/naivee2000/capture-shield-lab/actions/runs/43490166026), 2026-11-13.

| Actual environment | Build/sign/register | Behavioral + native/WebKit tests | Packaging/minimum checks |
| --- | --- | --- | --- |
| macOS 15.8.2 (24H232), arm64, Xcode 26.3 / Swift 6.2.4 / SDK 26.2 | Pass | 98 tests / 20 suites reported passed | Pass |
| macOS 27.0.1 (26A434), arm64, Xcode 27.2 / Swift 6.4.2 / SDK 27.2 | Pass | 98 tests / 20 suites reported passed (split into two test-target runs) | Pass |
| Local macOS 26.6.2 (25G83), arm64, CLT Swift 6.2.4 / SDK 26.2 | Pass, isolated validation bundles | 98 tests / 20 suites reported passed | Pass |

The macOS **26.7.2 / Xcode 26.6 / Swift 6.3.3 / SDK 26.5** job built, signed, registered and passed package checks, but its concurrent suite failed with six attachment-fixture issues: delivery/visibility timeouts and already-expired handoff states. The run took 174 seconds and did not crash on load; the background-alpha test passed. This outcome is retained as a failure, pending serial-fixture investigation. CI now passes `--no-parallel` to avoid simultaneously creating dozens of WebViews on the standard 7-GB runner; assertions and production deadlines are unchanged.

Each suite leaves the two optional real-speech and UI-export tests skipped. The background-alpha WebKit test actually executed and passed on macOS 15.8.2 and 27.0.1 as well. No recording permission, account or model was provisioned on CI, and no receiver test was performed.

The screenshot/recognition selection remains: compatible screenshot + on-device `SFSpeechRecognizer` on 15.x; modern screenshot + `SpeechAnalyzer` on 26/27. Availability/selection tests do not prove the screen pixels or recognition quality of these engines on those hosts. The local validation output is separate from the running logged-in app, which was not replaced or restarted.

Official references: [Apple Xcode host requirements](https://developer.apple.com/xcode/system-requirements), [Apple macOS version list](https://support.apple.com/en-us/109033), [GitHub runner images](https://github.com/actions/runner-images).
