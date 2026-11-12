# 0.4.2 live attachment follow-up

Baseline: `9913a59`. Scope: reproduce the user's failed Add to Chat path in the real signed-in WKWebView, repair it, and verify portable delivery. No message is sent by automation.

## Live findings and repairs

- The observed Chinese attachment trigger is `添加文件等内容`. Its upload action is a BUTTON labelled `添加照片和文件 从计算机上传`; older labels and role=menuitem-only matching missed it. Support the observed labels/subtitle and a once-only pointer fallback for a recognized trigger that still reports closed.
- The editor's nearest composer-body DIV excludes its sibling attachment controls. Prefer its enclosing FORM. The page exposes several specialized file inputs and one generic input bound to that form. After activating the recognized attachment trigger, use only a uniquely associated input; never select a document-wide same-label upload button or infer ownership from an input's creation time.
- The actual Screenshot toolbar button captured a 1920 × 1080 display after the QA application's permission was refreshed. The native crop selected only an innocuous synthetic question. Clicking Add to Chat delivered the crop to the real website through the public WKUIDelegate callback. The thumbnail was visible, opening it showed the correct crop, and the synthetic draft remained unchanged. No Send action was performed.
- That first live trial revealed a second bug: the website represents an attachment as a filename-labelled popup thumbnail, without a permanently visible Remove button. The old observer timed out despite the image being present. The observer now accepts a new, exactly filename-matched popup with a loaded image, or a decoded local blob/data background thumbnail. It retains file-change, document, origin and one-use consent gates, rejects text-only/decorative placeholders, and does not claim server processing or image understanding from a thumbnail.

## Permission and packaging finding

The temporary `/tmp` QA bundle could not be resolved by LaunchServices by bundle identifier; the TCC UI and logs showed missing application registration and an old ad-hoc designated requirement. Moving the identical signed bundle to a persistent local cache path and registering it made it resolvable. The user authorized the permission change and completed administrator authentication. The actual capture then succeeded.

The normal app destination remains `~/Library/Caches/CaptureShieldLab/Apps/`. The build now registers each signed bundle using public `LSRegisterURL` and checks `NSWorkspace` bundle-ID resolution. This does not grant/reset privacy permissions. A rebuild can still change an ad-hoc signature and require reauthorization. QA clones may live in `/tmp`; their app bundles should use a persistent local directory and distinct bundle identifiers.

References: [Apple LSRegisterURL](https://developer.apple.com/documentation/coreservices/1446350-lsregisterurl), [Launch Services registration](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html), [code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). The [Radix pointer-driven trigger](https://github.com/radix-ui/primitives/blob/main/packages/react/dropdown-menu/src/dropdown-menu.tsx) is compatibility-test rationale, not proof of the website's implementation.

## Validation and review

- New regressions first failed for observed labels, nested composer scope, and filename-popup previews. The final suite passed **69 tests in 13 suites**, including missing callbacks, timeouts, errors, duplicate confirmation, draft retention, no send, navigation and composition safeguards.
- The requested fresh read-only review identified two important issues: a document-wide fallback could click an unrelated same-label upload button, and an in-form menu item could be mistaken for the trigger. Both received failing regressions and were fixed. No minor review findings were deferred. The later real-UI observer repair has dedicated positive/negative regression coverage and self-review; it is not represented as an additional independent review.
- Diagnostics are opt-in (`CAPTURESHIELD_ATTACHMENT_DIAGNOSTICS=1`, app menu **Inspect attachment controls**). They report control types/associations and known attachment labels, never editor values, conversations, cookies or headers. Keep diagnostics and raw capture evidence outside Git.
- Final rebuilt-app verification: **passed**. After refreshing the stale ad-hoc permission record, the actual Screenshot and Retake buttons captured the display; the crop was added by the actual Add to Chat button. Status advanced from upload-in-progress to **Attachment visible in the composer**. Opening the website thumbnail showed the intended cropped question; the synthetic draft remained unchanged and unsent. Login and the synthetic text draft also survived the required app relaunches; attachment persistence across relaunch is not promised.
- Clean clone of `7cf1d3c061d8` in a source path containing spaces: both apps built, passed strict signature verification, and resolved by their distinct bundle identifiers from a persistent local cache destination. **69 tests / 13 suites passed**, and the clone remained clean. This is reproducibility on the development host, not a second physical Mac.
- Manual Send and image-understanding check, second physical Mac, and Teams/IME receiver trials remain pending. Private Cursor stays offline-only. No new meeting-privacy pass is claimed.

### Cleanup and permission recovery

The final ad-hoc rebuild again invalidated the earlier screen-recording designated requirement. Turning the switch off/on did not replace that requirement; a reset scoped only to the QA application's ScreenCapture service, followed by enabling and relaunching it, restored capture. No other application permission or system protection was changed.

The task-created native background window was closed, and public window metadata confirmed that no screenshot-target/baseline QA window remained visible. The real QA chat window intentionally remains open with the synthetic cropped attachment and draft for the user to send manually. The pre-existing System Settings window and other user windows remain untouched by cleanup. No raw captures or test drafts are committed.
