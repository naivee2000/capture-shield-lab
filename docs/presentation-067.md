# 0.6.7 webpage presentation and update resilience

Version **0.6.7/build 16** repairs the Legacy webpage backdrop and the native history button. Runtime remains Apple Silicon macOS 15.6+; build requirements remain Swift 6.2+/SDK 26+.

## Observed faults and repair

The current ChatGPT shell paints a large opaque `::before` decoration behind its main surface. Clearing only an element's own background left that decoration intact. A synthetic WKWebView regression failed with an empty-region alpha of 1 before this repair. Recognized canvas surfaces now clear their own fill and large, empty, noninteractive decorative pseudo-backgrounds. Message/code/media/control surfaces are excluded. A single native backdrop stays at 80% opacity in Legacy; the whole window and foreground content stay at alpha 1. Normal retains an opaque native backdrop. The Legacy capture flag is unchanged.

The current navigation rail hides the old toggle when history is collapsed. Its scoped Home button opens a flyout, after which the existing toggle pins it on wide layouts. Old selectors could not find that entry. `PageLayoutRules` supports both the classic target relationship and the observed navigation rail, without relying on generated class names. A Home label only qualifies inside the known sidebar's navigation region, with an unambiguous button and expanded state; arbitrary links or duplicate controls are not clicked. Narrow windows keep the native drawer.

Sidebar actions return an observed `expanded`, `collapsed`, `unavailable`, `not-ready`, `timeout` or `stale` result. Three seconds bounds the operation. Repeated requests join the active operation; explicit user input waits for an initial automatic collapse before starting its own action. Each action clicks its identified opener/closer once, with a separate pin step when needed. It never reloads the chat or repeatedly clicks until an uncertain action appears to succeed. The target region, control visibility and expanded state are checked together. The hover-only classic opener remains supported.

## Checks after website or system updates

Open **Compatibility → Check page compatibility**. It reads the current page's structural status, not its messages or history titles. The report includes the local adapter version, layout, sidebar state, surface/decorative-layer counts, remaining painted layers, macOS/WebKit build and the appearance property's actual readback. `ready` is a structural result, **not a pixel or receiver guarantee**. Copying the diagnostic is an explicit action; no report is uploaded automatically. An unrecognized page or unsupported WebKit hook is reported without changing Legacy or reloading/clearing the chat.

The adapter uses an isolated WebKit content world, coalesced relevant DOM/resize events, idempotent writes and per-document identities. Same-URL reloads and stale asynchronous replies cannot apply old page results. Appearance eligibility is separate from editor eligibility: a recognized shell may retain its backdrop while a drawer hides the editor, but unknown editors are never modified. Authentication and unknown pages restore their own presentation. Existing upload, dictation and account-store behavior is retained.

macOS and WebKit build changes produce a retest notice. The non-public WebKit background hook is capability-checked and read back, rather than inferred from an available selector. If unsupported, content remains readable and the limitation is explicit. Future website/OS versions still require validation; this is a maintainable compatibility layer, not universal future-proofing. Adapter rules ship locally with reviewed application builds; the app does not download executable fixes.

## Repeatable verification

```bash
bash scripts/test.sh --no-parallel --filter 'PageAdapterTests|CompactUITests|PageCompatibilityTests'
bash scripts/test.sh --no-parallel
python3 -m unittest discover -s Tests/ScriptTests -v
bash scripts/test-ui.sh --preflight
bash scripts/test-ui.sh
```

Native regressions exercise pseudo-background pixels and opaque foreground/code, classic and rail layouts, wide pinning/narrow drawers, wrapper/class/language changes, hidden/replaced editors, ambiguous controls, no-op clicks/timeouts, concurrent requests, same-URL navigation, read-only diagnostics and settled-DOM stability. Unsupported background capability and WebKit-build changes have explicit tests.

The packaged suite now contains **12 scenarios**, adding real toolbar history actions, retained drafts, mode switching and the compatibility sheet. Its preview has a synthetic rail/pseudo-background fixture and an independent nonpersistent store. The usual 980×700/640×480 and 70/90/140% cases remain in the suite. CI runs three sequential UI rounds per available actual OS, without retries; exact hosts and results belong in the release ledger, not inferred from runner labels.

## Recorded validation

The repaired application source is identical across the corrective test commits. The final tested commit and exact host/build/toolchain, package hashes and round counts are recorded in [the release ledger](validation-presentation-067.json). The three CI hosts each completed **three sequential rounds of 12 packaged-app UI scenarios**, without retries or skipped UI cases. Final negative-control and cleanup outcomes are included in the ledger.

Local macOS 26.6.2 completed the native suite (136 reported tests, two optional skips), 20 script tests, the six background pixel combinations and clean-clone build/sign/register checks. The clone and separate build directories contained spaces. A distinct packaged app also opened the official **signed-out** ChatGPT page: the native sidebar opened/closed, mode changes and the read-only page check retained a harmless draft, and no message was sent. Its structural report was ready with background drawing disabled by actual readback. This does not establish logged-in history navigation, physical desktop translucency or receiver hiding.

The first application failures and two test-harness failures are retained. One snapshot had checked DOM eligibility before the native background acknowledgement; it now waits for actual readback and still checks pixels. One macOS 15 startup UI assertion read the WebKit AX value immediately after key synthesis; it now waits for the complete test draft without retyping. The corrected macOS 15 suite completed all three rounds and the deliberate negative control. Both corrections observe completion without repeating the action or changing application behavior.

## Live-device acceptance

On the sender Mac, record app version/commit, OS/WebKit build, website language and window size. Use harmless content and keep existing drafts/images:

1. In Legacy, move a bright then dark test window behind the chat. Empty page areas should reveal 20% of the background; text, replies, images and code stay clear. Repeat after refresh, mode changes and a new reply.
2. Open/close history from the native toolbar, including at 640×480. Move back to the editor and type; history must remain open until explicitly closed or the website performs its normal navigation. Select an existing harmless chat manually to verify real history navigation.
3. Run the page check before/after the actions; confirm it exposes no draft or account information. An unsupported result is a limitation to investigate, not a reason to clear login data.
4. Separately repeat the Teams entire-screen receiver check. A local rendering pass or a hidden Dock icon is not a receiver result.

The [compatibility skill](../.agents/skills/capture-shield-compatibility/SKILL.md) and [maintenance guide](maintenance.md) route updates through the same diagnostics and tests. Preserve the first failure, add a synthetic structural fixture without copying a real page/account, apply the smallest rule change, then repeat native, packaged, live and receiver checks at their respective evidence boundaries.
