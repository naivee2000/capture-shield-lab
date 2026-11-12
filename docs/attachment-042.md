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
- Final rebuilt-app observer verification: pending.
- Clean-clone build/sign/test: pending.
- Manual Send and image-understanding check, second physical Mac, and Teams/IME receiver trials remain pending. Private Cursor stays offline-only. No new meeting-privacy pass is claimed.
