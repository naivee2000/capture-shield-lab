# Implementation record

Approved scope: native editable macOS 26 / Apple Silicon capture-protection experiment, separate unfiltered full-display capture app, truthful results, private GitHub source delivery to naivee2000/capture-shield-lab. No ChatGPT integration.

## Decisions

- Swift tools 6.2, no external dependencies; two locally ad-hoc signed bundles.
- Test-first for pixel classification, coordinate mapping and evidence gates; actual GUI/capture checks for native rendering behavior.
- Existing directory is empty. No user's code to preserve. No commits without explicit user authorization.
- Apply the supplied skills' research, execution and evidence principles. Use this small record instead of installing skill scripts or creating per-task commits; user instructions take precedence.
- Independent final read-only review after implementation, as required by the execution skill.
- Human local-visibility confirmation is separate from automated capture observation. A capture image cannot prove the protected UI is visible to a person.

## Progress

- Research and design approved in chat; source references will be retained in research.md.
- Core behavioral tests written before implementation.
- RED observed: 9 tests, 7 failed against placeholder classification logic; 2 rejection tests passed.
- Ruling: use bundled Swift Testing with scripts/test.sh correcting framework search paths and disabling the missing optional Foundation overlay on affected CLT installations. Bare swift test remains available on working Xcode/toolchain installations. No SDK or system configuration is modified.
- Core GREEN: all 9 tests passed after implementation.
- Ruling: package the two signed apps in ~/Library/Caches/CaptureShieldLab/Apps. The current exFAT source volume generates AppleDouble files that break resource signatures. Source and reports remain in the project; both bundles retain stable paths and identifiers for permission attribution.
- Independent read-only review found stale-frame control contamination, resettable lifecycle errors, unstable display-index selection, and missing process/heartbeat validation.
- Review RED: added regressions for frame epochs, display reordering/removal, lifecycle latching and dead/stale lab state; all four new tests failed against placeholder behavior before the fixes.
- Ruling: automatic samples are stable-state samples after a 200 ms presentation-time boundary. Transition flashes remain a mandatory manual receiver/video check; sampled results do not certify them.
- Review GREEN: all 13 tests passed, including the four added regressions. Both applications compiled and their local code signatures verified.
- Actual UI: ordinary panel rendered and accepted replacement test text. Dark-control contrast was corrected after visual inspection.
- Capture validation: recording denials and one invalid baseline were correctly reported not-tested. Following review fixes and an explicitly authorized permission refresh, a 12-sample-per-mode capture-first run had visible ordinary/mask controls and matching protected backgrounds. Physical local visibility/input and meetings are still unconfirmed; see compatibility.md.
- Private GitHub repository created under naivee2000; the user explicitly authorized the reviewed source and verification records to be committed and pushed to main.
- Both capture-before-window and window-before-capture runs completed with visible controls and matching protected-background samples. Physical local viewing remains unconfirmed because the operator is connected by remote desktop. An overlapping-window baseline was correctly rejected.
