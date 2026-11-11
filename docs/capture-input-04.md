# CaptureShield 0.4 implementation ledger

## Approved brief

Single-display screenshot, app-owned crop preview, explicit attachment confirmation, manual message sending; clipboard raster images and copied PNG/JPEG files; no continuous capture. Current account and website upload flow stay intact. Private cursor is experimental until independent receiver tests pass, local pointer remains visible, scope is app-owned surfaces only. Cmd-Option-arrow moves the front chat window by 40 points. Keep the independent recorder unfiltered, with a separate cursor-included path. Deliver portable source and clean-clone verification through the existing private repository.

## Tasks

1. Core geometry, attachment authorization and lifecycle tests; normalized image decoding and temporary storage.
2. Screenshot service, crop preview, native file-upload bridge, clipboard and synthetic UI integration.
3. Window movement, gated private cursor experiment and cursor-included recorder.
4. App/receiver validation where available, final independent review, clean-clone build, documentation and GitHub delivery.

## Constraints and rulings

- Baseline: `6c60d98`, clean `codex/initial-lab` branch. Continue this existing project branch; no main checkout edits or unrelated changes.
- The user-approved plan is the specification. Use the requested Superpowers inline execution, test-first regression and final fresh-context review methods without installing the whole skill library.
- Pre-flight: image preview and cursor are app-owned surfaces sharing mode/lifecycle; attachment handoff must be invalidated by navigation; movement must preserve IME and modal behavior; capture for user input excludes this app, whereas the independent verifier excludes nothing.
- Ruling: cursor support stays unavailable in normal builds until an actual receiver verdict exists. The offline `--chat-preview` alone exposes its explicitly labeled experiment, so unverified behavior cannot silently become a protection claim.
- No account content, screenshots, clipboard content, invitations or credentials enter this document or Git. Temporary test logs live outside the checkout.
- The user requested delivery first and a receiver questionnaire afterward. Teams/physical-local trials are therefore deferred, not a blocker for the independent image/movement delivery; production cursor support remains disabled.

## Evidence

Source implementation and review fixes are complete. Clean-clone delivery verification is pending below. Live ChatGPT, screenshot permission, recording and physical-local/receiver checks remain not-tested unless explicitly recorded.

- Core tests failed on unchanged movement, absent crop mapping and missing consent handling, then passed after implementation.
- Image decoding/storage tests failed before implementation. Orientation and active-store isolation now pass. ImageIO generates harmless color/dimension EXIF fields; the metadata assertion checks removal of the source comment and GPS rather than rejecting newly generated color metadata.
- Native WKWebView upload regression failed before implementation, then passed: the file is readable by the synthetic page, existing draft stays unchanged, no send occurs, duplicate confirmation is ignored and navigation drops the staged image. Offline about:blank lacks crypto.randomUUID; document identities now originate in native UUIDs inside the isolated content world.
- Cursor lease/eligibility and IME/modal key-policy tests failed before implementation and passed afterward. Independent cursor configuration failed when showsCursor was false and passed with the new explicit include-cursor configuration. The initial full suite passed 45 tests; broader final validation is pending.
- Final independent review found concurrent Stop/Quit and self-cancelled auto-stop finalization defects. The reviewer also found covered preview errors and a disabled re-confirm button after fallback; these were regraded as important because they block recovery. All four were reproduced with failing tests, fixed in one pass, and the complete suite passed 50 tests in 12 suites. No deferred minor findings.
- The review declined live ChatGPT, physical-local/Teams, real IME/sheets and unfinished delivery checks. Ruling: live/receiver/IME checks remain explicitly not-tested per the user's delivery-first request; documentation and reproducibility remain required before delivery.
- Actual isolated offline UI: native preview displayed correctly; drag crop selected the question; its cropped image appeared as a 5,208-byte attachment without sending. A draft survived mode changes and Cmd-Option-Up moved the actual window from screen Y=160 to Y=120 (40 points). Legacy-only experimental cursor toggle and Esc-to-off were observed, not a physical-local or receiver verdict. Changed the cursor toolbar control to a compact icon to reduce overflow.
