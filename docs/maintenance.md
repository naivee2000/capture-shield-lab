# Compatibility maintenance

CaptureShield 0.5 targets Apple Silicon macOS **15.6+**. A deployment target and an available API are not runtime or receiver test results. Keep exact OS/build/client evidence in `compatibility.md`.

## Which module to repair

| Symptom | Start here | Focused verification |
| --- | --- | --- |
| OS update breaks Screenshot | `ScreenshotService` backends and `SystemCompatibility` policy | ScreenshotCompatibilityTests; actual Auto and Compatible captures |
| Wrong window/popup/candidate sharing setting | `WindowProtection` and `PanelSharingProtection` | WindowTests / PanelSharingTests; independent receiver video |
| Image chooser/thumbnail stops working after website change | `AttachmentPageBridge` / `ImageAttachmentCoordinator` | AttachmentBridgeTests, including repeated additions and delete/re-add on one document |
| Chinese input or movement regression | `CompositionTracker` / `ChatKeyboard` | Real Pinyin composition plus receiver candidate test |
| App or tools not found, old signature/permission | `bash scripts/doctor.sh` | Correct app path, version, commit, signature and lookup; app Compatibility panel for permission |

Auto uses `captureScreenshot` on macOS 26+ and `captureImage` on 15.6–15.x. Compatible always uses `captureImage`. Both use the same full-display filter excluding this app, omit the system cursor, produce SDR pixels, enforce the same size limits, and require the existing native preview/confirmation before upload. Only the modern backend is annotated as macOS 26+. Do not introduce new-OS types into the shared service or instantiate them outside an availability check.

A failed screenshot never retries or changes engine automatically. Open **Compatibility…**, choose **Compatible**, click **Done**, then explicitly take a new screenshot. Existing drafts/attachments and login data stay intact. A failed Retake keeps the existing crop and displays its error inside the preview. Private Cursor remains offline-only.

All AppKit `sharingType` writes belong to `WindowProtection`. The candidate-panel interposition only controls this process's NSPanel instances and preserves their original settings when leaving Legacy. Do not treat an unavailable/unknown OS or a diagnostic result as permission to switch to Normal or claim invisibility.

## Safe diagnostics

**Compatibility…** is an owned native sheet, follows Normal/Legacy appearance, and performs only a permission preflight. It contains OS version/build, app version/build/commit, selected and effective screenshot engine, and last screenshot error stage/numeric code. Copying is explicit. It excludes error descriptions/userInfo, webpage contents, URLs, account data, cookies, raw captures and machine identifiers.

After a changed macOS build, the next launch shows a non-blocking in-window retest notice; settings are preserved. Viewing and closing Compatibility acknowledges that launch notice, not a hiding pass. Unknown future OS versions remain unverified even if the Auto API is available.

`doctor.sh` is read-only with respect to applications, system registration, permissions and settings. Its Swift lookup helper may use normal compiler caches. It does not register/launch apps or build the project. It cannot attest another process's TCC permission; check that inside the actual app. Never add automatic `tccutil reset`, permission toggles, tool installation, or Gatekeeper changes to diagnostics.

## Toolchains and update workflow

- Runtime minimum: **macOS 15.6**; build requirements: **Swift 6.2+ and macOS SDK 26+**.
- On macOS 15.6–15.x, use **Xcode or Command Line Tools 26.0–26.3**. Newer Xcode releases may require a newer host OS. Download a compatible version from Apple's official developer downloads when Software Update does not offer one. See [Apple's toolchain matrix](https://developer.apple.com/xcode/system-requirements/) and [Command Line Tools instructions](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools).
- The manifest supplies the build scripts' minimum OS. A regression checks the runtime policy matches it. Keep Swift and SDK checks separate from the runtime minimum; do not merely lower Info.plist.
- Keep bundle IDs, app folder and web data store stable. Rebuilding an ad-hoc app may still invalidate its recording grant. Diagnose the exact built app; CaptureShieldLab and CaptureProbe have separate permissions.

Everyday launch, with no rebuild/signature change:

```bash
bash scripts/launch.sh
```

After preserving drafts and quitting the app, update from GitHub:

```bash
git pull --ff-only
bash scripts/doctor.sh
bash scripts/dev.sh
```

`doctor.sh` may report an old build before rebuilding; follow its explanation rather than resetting unrelated permissions. Use `launch.sh --chat-preview` for the existing offline build; quit a running app before changing launch modes.

## Release checklist

1. Run `bash scripts/test-support.sh` and `bash scripts/test.sh`. Check repeat uploads, no auto-send, draft preservation, permission denial/recovery, capture failures and cancellation.
2. Build from a clean clone in a path containing spaces with distinct QA IDs and persistent local bundle paths. Verify both signatures, bundle minimums and build commits; run doctor and compare signatures before/after launch.
3. On this host exercise Auto and Compatible using only synthetic screen content. Check crop, two attachments, deletion/re-add, saved engine selection, compatibility-sheet inheritance and the OS-change notice. No private screenshots or original chat data in Git.
4. On real 15.6/15.x and 27 machines, verify launch/login/session, both applicable screenshot paths, keyboard/Pinyin and normal window behavior. A simulated OS in a policy test is not an OS runtime test.
5. Independently retest Teams desktop entire-screen sharing with Chrome receiver three times: Normal visible, Legacy locally usable and absent at the receiver, complete background/other-window updates, candidate entry/paging/selection and transitions. Keep untested combinations untested.
6. Summarize changes and evidence, commit/push and read back the remote SHA. Close only task-created auxiliary windows and preserve user sessions.
