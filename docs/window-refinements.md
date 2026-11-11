# Window refinements (0.3)

Approved: ordinary NSWindow behavior; native draggable title/toolbar; Normal (opaque, capturable) and Legacy (80% window opacity) modes; persisted 70–140% page zoom, default 90%; initially collapsed sidebar; compact composer; app-only suppression of text suggestions; original icon; portable GitHub delivery.

## Decisions

- Keep the existing lab and unfiltered recorder independent. The latest user report confirms Legacy hides the current window for their sharing setup; exact client/OS versions and repeat counts are not recorded.
- Centralize mode/zoom so popups, sheets and restored windows inherit the current choice, rather than resetting to Legacy during presentation.
- Standard titlebar/toolbar drag regions must not steal webpage selection/input. Chat windows use normal stacking, not floating panels.
- This phase authorizes small, scoped webpage presentation/input scripts. They may adjust known chat controls but must not read conversation/input values, authentication data, or modify login pages. Unknown markup falls back to the unmodified page.
- WebKit text checker preferences are app-scoped and configured before constructing any WebView. System IME candidate windows remain separate surfaces; no global keyboard changes.
- Use isolated QA bundles/preferences and disposable synthetic pages for tests. Preserve pre-existing windows and login sessions; close only windows/tabs opened for this task without quitting applications or killing processes.
- Continue the previously selected execution/verification workflow, including one fresh-context final source review.

## Progress

- Baseline dc8d685; working tree clean. Added persistence, range and default regressions before implementing settings.
- Preference regressions were observed failing before implementation. The original floating-panel regression also failed against the old NSPanel, floating level, missing native chrome and alpha 1; it passed after the new NSWindow implementation.
- Actual WebKit integration caught replacement-editor settings being delayed when animation frames paused in a covered window. Coalesced timers fixed the regression; unknown/authentication-page isolation tests passed.
- Independent final review identified frame/content-rectangle confusion and premature sidebar initialization. Both regressions failed first, then passed after outer-frame restoration and acknowledged/bounded sidebar retries. Preview text-check defaults now use nonpersistent registration instead of writing production defaults.
- UI preview checks: native window controls, 70/90/140% scaling, explicit sidebar expansion, Unicode paste, unchanged misspelled English input, popup mode/zoom inheritance, parent mode synchronization and an owned JavaScript dialog were observed. Physical local transparency, other-app occlusion and real IME/receiver behavior still need the laptop checks; window-property tests do not certify receiver pixels.
- Live signed-out WKWebView exposed a second composer (`mobile-composer-prompt`) and a hidden email field; temporary metadata-only diagnostics identified these without reading any input values. Added a synthetic regression for this markup and for choosing the visible close-sidebar control ahead of open controls.
- The live sidebar keeps its close button offscreen after collapse. A regression reproduced selection of that hidden control instead of the opener. Sidebar/auth visibility now checks viewport intersection; editor styling can still be maintained while the editor itself is scrolled out of view.
- Final regression suite: 32 tests passed across six suites. Temporary layout diagnostics were removed. Native UI checks and the signed-out real page remain separate from physical local/receiver certification.

- Added and verified a regression for a known collapsed sidebar opener that is transparent until hover. The native toolbar can select it by its explicit sidebar target and collapsed ARIA state, without broad button matching.
- Clean-clone verification of source commit `da346af`: both applications built and passed local signature verification; all 32 tests passed and the clone remained clean. This was a fresh checkout on the development host, not a second physical computer.
- Launch scripts now check whether the exact app bundle being rebuilt is running, so unrelated isolated QA copies do not block normal development. Shell syntax checks passed; an inactive target was accepted and a running QA target was rejected.
