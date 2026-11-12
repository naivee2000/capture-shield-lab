# 0.4.1 repair ledger

Baseline: `e812b54`. Approved scope: investigate Chinese candidate-window leakage, repair screenshot attachment delivery, then unify shortcuts. Current development Mac only; no receiver deployment.

## Constraints and rulings

- Preserve normal Pinyin composition. Window protection does not imply protection of input-method-owned surfaces. No private APIs or new IME engine.
- Attachment callback completion is not evidence of a visible attachment. Keep the crop for recovery; never rewrite a draft or send a message.
- Only synthetic content in tests; no account data, chat text, invitations, raw captures or credentials in Git.
- Ruling: use the requested Superpowers test-first and final-review methods in this existing `codex/initial-lab` workspace, with this focused ledger; do not install entire skill repositories.
- Shared interfaces: attachment navigation invalidation and composition tracking both belong to each WebView; isolated-world state must reset on navigation. Keyboard changes must not interrupt marked text. Cursor qualification remains unchanged.
- Test bundles use a separate bundle identifier and application path. The default installed 0.1.0 application must not be used as evidence for current source.

## Progress

- Investigation and baseline build: complete; actual candidate ownership and first-order settings observed.
- Attachment regression and repair: synthetic/local repair complete; live website validation pending.
- Shortcut/composition regression and repair: complete, including actual Pinyin commit-to-movement recovery.
- Final review and clean clone: complete. GitHub synchronization follows the documented pre-commit summary. Live/receiver trials remain pending.

## Evidence boundary

User reports Teams desktop entire-screen sharing from macOS 26.6.2 (25G83), viewed in Chrome: Normal visible, Legacy hidden, system Pinyin candidates visible. This is a user-reported result, not a new local or receiver verification. Screenshot 1 has not been supplied. Private Cursor faults remain deferred and the feature remains restricted to offline preview.

### Investigation observations (development Mac, 2026-11-12)

- Baseline `e812b54`, version 0.4.0/build 4, isolated bundle `dev.naivee2000.captureshield.baseline041.lab`, built and signed at `/tmp/captureshield041-baseline/Apps/CaptureShieldLab.app`.
- The user reproduced a synthetic Pinyin candidate strip in Normal mode. Public WindowServer metadata attributed window 545 (layer 20, 397×28 points at x=539/y=491) to the same PID as the test application; its main window was 474 (layer 0). These IDs are transient. An earlier TextInputMenuAgent layer-101 window was the input-source menu, a different surface.
- Ruling: do not classify the candidate as an external input-method process from appearance alone. Next inspect the app's public NSWindow collection before selecting a protection strategy.
- Public [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient) manages marked text and geometry; [IMKCandidates](https://developer.apple.com/documentation/inputmethodkit/imkcandidates) is attached to an input-method server. Neither document promises a client-side, capture-exclusion API for another process's candidates.
- Regression RED: lazy generic file control never received bytes; callback without a thumbnail discarded the crop. Both failed on the baseline, then passed with the new bridge/coordinator.
- Shortcut RED: Cmd-Shift-Up did not move, while the deprecated Cmd-Option-Up still did. New centralized definitions reverse that behavior.

### Local application checks and final review

- Internal NSWindow diagnostics identified the candidate as an app-owned `NSPanel.ViewBridge.rendezvous`, with sharing=1 before the repair. This name is diagnostic only: protection does not match or call private classes/selectors.
- The repair intercepts the public NSWindow ordering method within this process and sets the public sharing property for NSPanel before forwarding. A real new Pinyin candidate in Legacy logged `sharing=0`, `wasVisible=false` before ordering; mode changes updated the existing candidate too. Native candidate selection and expansion continued to work. These are local object/timing observations, not receiver frame evidence.
- Real UI uncovered a WebKit processing-key event after compositionend which latched the DOM tracker on. A regression failed, then passed when keyCode 229 alone stopped asserting composition. Actual Pinyin then blocked movement during composition and restored a 40-point move after committing.
- Actual offline UI displayed a cropped synthetic question as a 35,897-byte attachment, preserved the existing synthetic draft and reported the preview visible without sending. Live website verification remains separate.
- Final fresh-context read-only review found four important issues: unrelated newly created file controls, decorative-image false positives, transient composer unavailability deleting the crop, and old async composition snapshots surviving reset. All enter the single review fix pass with dedicated regressions.
- Final rulings: live website/receiver results remain pending until tested; first-order property evidence does not certify remote frames. Wider IME/sleep/crash/subclass paths remain untested. A hypothesized SPA bypass was not established because URL KVO already invalidates consent. Clean-clone and remote-SHA checks remain required before delivery.

- Final review fixes: all four dedicated regressions first failed on the relevant behavior (after correcting the async fixture to return a serializable value), then the complete suite passed **63 tests / 13 suites**. Input association now requires composer/form ownership or synchronous dispatch from a recognized attachment action; a new unrelated input is insufficient. Preview acknowledgment requires file-name association and a visible remove control. Document identity is independent of composer visibility. Composition synchronization is generation-bound.
- No minor review findings were deferred. Live/receiver and wider lifecycle limitations above remain explicit; this is a test build pending live validation.
- The original ABC input source was restored and read back from HIToolbox after the local Pinyin tests.

- Clean clone of `b474a969144ad8ac5147005b50db8c11b0670685` in a fresh local path containing spaces built both apps and passed strict ad-hoc signature checks; **63 tests / 13 suites passed**, and the clone remained clean. Info.plist reported version 0.4.1 and build commit b474a969144a. This was the development host, not a second physical Mac.
