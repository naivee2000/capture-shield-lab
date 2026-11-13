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
bash scripts/test.sh
bash scripts/doctor.sh
```

## Evidence boundary

CI can detect unavailable APIs, dynamic-linking failures, compiler changes and failures in synthetic native/WebKit behavior, including background alpha, attachment handoff, draft preservation and layout. A hosted macOS 15.x job does not test the exact 15.6 release unless its recorded host version says 15.6. A later patch release is likewise not evidence for every earlier or future patch.

Real ChatGPT login and attachment upload, screen/audio permissions, screenshot pixels, language models/recognition and Chinese input must also be checked on the actual device. Normal/Legacy visibility requires a separately observed meeting receiver. In particular, the non-public WebKit background hook and app-hosted candidate-panel handling remain OS-dependent. A pass does not promise that every future macOS or meeting-app version will work.

Before sharing after an OS upgrade: run the tests, use a harmless image to check screenshot/crop/attachment, confirm English/Mandarin transcription if needed, then compare Normal/Legacy at the receiver (including candidates, popups and other windows). Record exact sender OS/build and sender/receiver application versions. Preserve failed or untested outcomes.

## Run ledger

Cross-version jobs are being established for version 0.6.2. Record the completed run and exact host versions here after inspecting the logs; do not infer a pass from the workflow's existence.

Official references: [Apple Xcode host requirements](https://developer.apple.com/xcode/system-requirements), [Apple macOS version list](https://support.apple.com/en-us/109033), [GitHub runner images](https://github.com/actions/runner-images).
