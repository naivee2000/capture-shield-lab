# Observed compatibility

## Version 0.6.3 cross-version validation (2026-11-13)

See [exact OS, toolchain and CI results](os-validation.md). The first actual macOS 15 run found that the 0.6.2 executable strongly required screenshot classes introduced in macOS 26, despite source availability guards. Version 0.6.3 weak-links those references and checks the binary before packaging. Repaired source passed clean builds, signatures/registration and synthetic AppKit/WebKit tests on **macOS 15.8.2, 26.7.2 and 27.0.1**, plus local 26.6.2 regression. The final matrix runs native fixtures serially after the concurrent 26.7.2 run exposed attachment-fixture timeouts; no assertions or production deadlines were weakened. These results supersede the older "15.x/27 runtime pending" statements **only for those automated checks and exact versions**, not physical-device capture, account/recognition or receiver behavior. The declared floor remains 15.6; that exact point release is not independently tested.

## Version 0.6.2 background and responsive UI (2026-11-13)

See the [UI implementation and validation ledger](ui-062.md). Content alpha is now 1; Legacy background paint is 0.8. The compact speech strip is 36 points, settings and retained text are disclosures, and notices no longer reserve a permanent footer. Web background transparency uses an isolated **non-public WebKit appearance hook**; it requires per-system verification. Audio capture and the deferred blue/purple indicator investigation are unchanged. No new Teams receiver verdict is claimed.

## Version 0.6.1 compact transcription panel (2026-11-13)

The bottom panel is reduced from 180 to 112 logical points. Smaller native controls and a combined action/status row leave more space for the chat. The transcript scrolls within 40 points, content is aligned near the footer, and the full status is available as a tooltip. Recording and draft-insertion evidence remains in the [0.6 ledger](speech-06.md); receiver verification is still separate. Local verification: 55 existing window/speech tests passed; the running app was visually checked at 980- and 640-point window widths, then restored to its prior frame. All controls fit and closing/reopening the panel worked. No new audio or receiver-hiding claim is made. A clean clone of `97fef281d26b` in a path containing spaces built and strictly signed both 0.6.1/build 10 apps; registration and doctor checks passed and the clone stayed clean. This was on the same development Mac.


## Version 0.6 speech and Dock behavior (2026-11-12)

See the [speech/Dock implementation and evidence ledger](speech-06.md). Recognition uses selected-app audio and on-device English/Mandarin engines; this is independent of Legacy receiver compatibility. The current host is macOS 26.6.2. No new Teams, physical-keyboard, headphone, macOS 15.6 or 27 verdict is implied by synthetic tests or Dock activation policy.


Date: 2026-11-10. Development host: Apple Silicon, macOS 26.6.2 (25G83), 1920 × 1080 display.

## Version 0.5 compatibility layer (2026-11-12)

| Check | Result and boundary |
| --- | --- |
| Deployment | Apple Silicon macOS 15.6+; build requires Swift 6.2+ and SDK 26+. Both apps compile at the lower deployment target |
| Screenshot selection | Auto selects modern on 26+ / compatible on older supported systems; Compatible can be selected manually on all supported systems. No automatic retry/fallback on failure |
| Existing regression baseline | All 70 prior tests passed at the lower deployment target |
| New regression | 77 tests / 15 suites passed, including minimum-version policy, 15.6/26/27/future selection, permission denial with no repeated prompt across engine switches, sanitized errors, manual-only retry, settings persistence and protected sheet inheritance |
| Auto, actual UI | Captured the synthetic desktop, cropped and added two images; after deleting test attachments and returning from Compatible, a new synthetic question attached successfully. Existing draft/login preserved; nothing sent |
| Compatible, actual UI | Two actual capture/Retake attempts returned the system remote-control curtain, not the visible synthetic desktop. Normal-desktop capture is **not verified** in this environment. A crop of only the non-personal wallpaper background was added through the real website successfully; this is attachment-pipeline evidence, not a normal-desktop capture pass |
| Compatibility UI and diagnostics | Correct app/system/build/engine/preflight displayed; Compatible preference read back; switching preserved draft/remaining attachment; simulated prior OS-build triggered the notice and the real build was stored. QA ended in Auto. Doctor found the old default 0.1.0 installation and correctly accepted the 0.5 QA apps; launch preserved the code-signature hash |
| macOS 15.6/15.x and 27 runtime | Compatibility implemented; actual-device runtime tests pending. Selection-policy tests do not certify either OS |
| Receiver privacy | No new Teams/IME or cursor verdict; Private Cursor remains offline-only |
| Reproducibility | Clean clone of `251305b7a812` in a path containing spaces: both apps built, strictly signed and registered; 77 tests / 15 suites plus script checks passed; doctor accepted both bundles; clone clean. Both Mach-O load commands and Info.plist report minimum macOS 15.6 (SDK 26.2). Same development host; no second-OS runtime claim |
| Cleanup | Task-created synthetic background closed; window metadata confirmed none remained. Existing QA chat retained with one synthetic question and draft; System Settings and other user windows preserved |

See [maintenance](maintenance.md) for repair ownership, safe diagnostics and operator test steps. No login data, private chat, meeting links or raw captures are included.

## Version 0.4.3 repeated attachment repair (2026-11-12)

| Check | Result and boundary |
| --- | --- |
| Root cause | The isolated-world script declared request configuration as a top-level const; the second evaluation in the same document failed before replacing the old request. Configuration now stays inside the per-request function |
| Regression | Both keep-existing and remove-previous scenarios failed on the second image before the fix. Each now completes three additions, retains the draft, and prevents duplicate confirmation/send. Full suite: 70 tests / 13 suites passed |
| Real signed-in ChatGPT | Actual Screenshot/crop/Add to Chat used four times without navigation or reload: two images coexist; removing one permits a replacement; removing all permits a new image. Every addition reached attachment-visible status. Synthetic draft unchanged; no message sent |
| Packaging | Version 0.4.3/build 7. Persistent QA apps built, strictly signed and registered. An initial clean clone exposed delayed NSWorkspace registration visibility; the helper now retries the exact-path lookup for up to 1.9 seconds, without relaxing path checks. Final clean clone of `3494a31c7f3b`, in a source path containing spaces and with fresh app identifiers: both apps built/signed/registered on the first build, 70 tests / 13 suites passed, clone clean. Same development host, not a second physical Mac |
| Cleanup and boundaries | Task background window closed and absence verified from window metadata. Pre-existing chat window retained with its synthetic draft and one replacement test image. Manual image-understanding and Teams/IME/cursor claims unchanged |

No authentication data, real conversation, meeting link or raw screenshot is included. The fix changes only the request variable scope; origin, document identity, file association and one-use confirmation checks remain intact.

## Version 0.4.2 live attachment validation (2026-11-12)

| Check | Result and boundary |
| --- | --- |
| Real Screenshot and crop | Actual toolbar capture succeeded after app registration/permission refresh; cropped only a synthetic question |
| Real Add to Chat | Cropped image visible in the signed-in composer and opened correctly in the website image viewer; synthetic draft preserved, no message sent |
| Preview-state repair | First live trial exposed a false timeout for the website's filename-labelled popup thumbnail. Final rebuilt-app trial passed: upload-in-progress then attachment-visible status, correct crop in the website viewer, unchanged draft, no send |
| Automated suite | 69 tests / 13 suites passed |
| Reproducibility | Clean clone of `7cf1d3c061d8` with a source path containing spaces: both apps built, registered and strictly signed, 69 tests passed, clone clean. Same development host |
| Image understanding | User must send manually; not tested |
| Teams / IME / Private Cursor | No new receiver test. Prior candidate-panel evidence remains local-only; Private Cursor remains offline-only |

See the [0.4.2 evidence ledger](attachment-042.md). No raw images, drafts or account data are committed.

## Version 0.4.1 repair validation (2026-11-12)

| Check | Result and boundary |
| --- | --- |
| User's reported meeting setup | Teams desktop, entire-screen sharing on macOS 26.6.2 (25G83), Chrome receiver: Normal visible, Legacy hidden, Pinyin candidates visible before this repair. Client versions and three-repeat retest pending |
| Candidate ownership | Public WindowServer metadata and app NSWindow metadata agree: the reproduced Pinyin strip is an app-hosted NSPanel, layer 20, originally sharing=1. Input-source menu belongs to TextInputMenuAgent and is a separate surface |
| Candidate repair, local | A new real Pinyin candidate logged sharing=0 before its first order call in Legacy. Switching to Normal restores the original sharing setting. Selection/expansion remain functional. No receiver/flash verdict |
| Keyboard, local | Actual Pinyin composition blocks Cmd-Shift-Down; after commit it moves 40 points. All four directions, screen constraints, modifiers and unknown/modal composition gates also have regression coverage |
| Reproducibility | Clean clone of `b474a96`, including a source path with spaces: both apps built/signed, 63 tests passed, clone clean. Same development host |
| Attachment repair, synthetic | Lazy and generic controls, chooser consent, unchanged draft/no send, display/error/timeout and navigation/re-crop recovery covered. Offline UI displayed a cropped sample attachment |
| Live ChatGPT attachment/readback | Not tested during 0.4.1; superseded by the 0.4.2 live attachment trial above. Image understanding still requires the user to send manually |
| Private Cursor | Other reported faults deferred; normal builds remain disabled, offline experiment only |
| Wider input/capture lifecycle | Other predictor/correction UI, external-process candidates, sleep/crash, Teams first-frame/mode-switch flashes and second physical Mac remain untested |

Detailed repair evidence and review findings: [0.4.1 ledger](repair-041.md). Raw captures, real conversations and account data are excluded from Git.

## Version 0.4: images, movement and gated cursor experiment (2026-11-11)

The user requested source delivery first and a questionnaire for later laptop/receiver tests. No new meeting result or physical-local pointer success is claimed.

| Check | Observed result |
| --- | --- |
| Automated suite | 50 tests in 12 suites passed after the independent review fixes, including native upload, stale consent, image limits, recovery UI and recorder finalization |
| Clean-clone reproducibility | Source `1b42260` built and locally signed both apps from a fresh clone; all 50 tests passed and the clone stayed clean. Same development host, not an independent second computer |
| Offline native UI | Synthetic image displayed, cropped to the question and attached (5,208 bytes); no message sent. A typed draft survived mode changes and Cmd-Option-Up moved the actual window by 40 points |
| Experimental pointer UI | Legacy-only toggle changed on/off; Esc restored its off state. These control states do not certify local pointer pixels or receiver output |
| CaptureProbe UI | Separate full-display + cursor recording control rendered. New recording was not started during this task |
| Production private cursor | Disabled pending receiver evidence; experiment only available in --chat-preview, default off |
| Live ChatGPT image upload and response | Not tested in this revision; native handoff succeeded only in the offline synthetic WebView |
| Screenshot permission / captured display / multi-monitor setup | Implemented; not exercised end-to-end in this revision. Crop-to-pixel mapping is covered by automated tests |
| Teams trials, physical local pointer, IME/native sheets and sleep/crash recovery | Not tested; laptop questionnaire pending |

Two recorder defects found by final review (concurrent Stop/Quit and self-cancelled auto-stop) were reproduced and fixed. Two preview defects (covered errors and disabled re-confirmation) were also reproduced and fixed. No deferred review findings remain. Task-created QA windows were closed and zero visible QA windows confirmed; no user browser tab was closed.

## Version 0.3: window refinements (2026-11-11)

The operator reports that **Legacy hides the current chat window from the other participant during sharing**. This is feedback about their existing build/setup; exact OS/client versions and repeat counts were not provided. The new native titlebar, normal window level and 80% opacity require fresh receiver-side checks.

| Check | Observed result |
| --- | --- |
| Native window, settings and synthetic WebKit tests | 32 tests passed, including frame restoration, mode/zoom persistence, sheet appearance, hydration, editor replacement, authentication isolation and offscreen sidebar controls |
| Native UI preview | Normal/Legacy switching, 70/90/140% page sizes, explicit sidebar expansion, Unicode paste, retained English misspellings, popup mode/zoom inheritance and a managed JavaScript dialog exercised |
| Real signed-out ChatGPT page | Loaded in isolated QA WebView; dark compact layout and initial sidebar collapse observed. Signed-out and signed-in markup require different recognized composer hooks |
| Normal stacking and 80% Legacy opacity | Actual NSWindow level/style/alpha properties verified; physical local translucency and other-app occlusion not independently certified by window-only screenshots |
| New whole-display/meeting capture | Not tested in this revision; previous results remain separately recorded below |
| Chinese IME candidates / receiver-side prediction windows | Not tested; system candidate windows are outside app-owned window settings |
| Icon and local build | Original SVG/PNG/ICNS generated, visually inspected; both app bundles include the icon and pass local signing checks |
| Clean-clone reproducibility | Source `da346af` built and signed both applications from a fresh clone; all 32 tests passed and the clone stayed clean. Same host, not an independent second computer |

Temporary debugging emitted only control metadata, never field values or conversations, and was removed from the source. QA app identifiers and stores were separate from normal-use builds. Test-only captures and debugging files are not delivered through Git.

## Version 0.2: ChatGPT / WebView

These results are separate from the earlier native-editor observations below.

| Check | Observed result |
| --- | --- |
| Official ChatGPT page in persistent WKWebView | Homepage, sidebar, text input and official sign-in dialog loaded; no website rejection encountered at this point |
| Account login, original history, authenticated responses, restart persistence | Not tested: account owner sign-in pending |
| Offline synthetic WebView | Actual UI rendered; Unicode/Chinese plain-text paste, complete synthetic streaming reply and suppressed right-click menu observed |
| Automated behavior suite | 19 tests passed, including repeated-hide and file/image paste regressions |
| Build / local signing | Both applications built and code signatures verified; final QA bundles built separately from the login window |
| Clean-clone reproducibility | Source c4a06d6 built and signed both apps from a fresh clone; all 19 tests passed and the clone stayed clean. Same host, not an independent second computer |
| Independent WebView full-display capture | Not tested: macOS TCC denied the rebuilt QA verifier; all four stages and meeting rows remained not-tested |
| Physical local ChatGPT visibility and three laptop-to-Teams receiver trials | Not tested |
| Live website popups, restart login persistence, confirmed local-data clearing, global shortcut in another app | Not tested end-to-end; source behavior is implemented |

No raw screenshots, cookies or chat history are included. A blank window-only screenshot under Legacy is not proof of the intended whole-display behavior. Refresh the final installed CaptureProbe permission if needed, then repeat both capture orders with Synthetic WebView and complete the separate receiver-side tests. The earlier native text result must not be presented as a ChatGPT/WebView pass.

## Local independent SCStream run

Both orders were exercised: capture before the window appeared, and window before capture started. Each run used twelve fresh stable-state samples per mode, with no window/application exclusions.

| Mode | Capture observation | Overall status |
| --- | --- | --- |
| Ordinary | Visible control; worst differing-pixel fraction 0.92493 | Control passed |
| Unprotected mask | Visible control; worst differing-pixel fraction 0.92497 | Control passed |
| Legacy sharing flag | Sampled background matched | Local visibility/input unconfirmed |
| Protected mask | Sampled background matched; differing-pixel fraction 0, mean RGB error 0 | Local visibility/input unconfirmed |

The ordinary panel was visually inspected and accepted edited synthetic text. The operator is using remote desktop, so physical visibility/input in protected mode remains unconfirmed and is not recorded as pass. Neither these sampled runs nor their controls certify startup flashes, movement, sleep/wake or meeting clients.

Earlier attempts correctly remained not-tested when recording permission was denied or the baseline was invalid. One invalid baseline visibly contained another application overlapping the synthetic background; that run was not counted. A stale ad-hoc permission registration required removing and re-adding the current CaptureProbe bundle through System Settings, with explicit user authorization.

## Meeting clients

| Client | Status |
| --- | --- |
| Zoom | Not tested |
| Google Meet | Not tested |
| Teams, development Mac as sender | Whole-display baseline failed; see the earlier headless-host attempt below |
| Teams, personal laptop as sender | Operator reports Legacy sharing stays visible locally, disappears at the receiver, and leaves other windows visible and updating; limited positive observation |

### Personal laptop → Teams → development Mac: operator observation

The operator subsequently clarified that this test ran on their **personal laptop**, sharing its **entire screen** through Teams to the development Mac. This is the opposite direction from the earlier failed trial below.

| Mode | Sender's laptop screen | Received shared screen |
| --- | --- | --- |
| Ordinary | Visible | Visible |
| Mask control | Visible | Visible |
| Legacy sharing | Visible | Lab window absent; other windows remain visible and update normally |
| Protected mask | Lab window absent | Lab window absent |

This is a positive operator-reported observation of the desired **window-only visibility behavior** for Legacy sharing in that setup. Protected mask fails the local-visibility requirement in the reported laptop setup; absence from a capture alone is not success.

Use Legacy sharing for further tests on that laptop. Do not generalize this result to other OS builds, meeting clients or capture modes. The exact laptop OS build, Teams client/version, source build, typed-input check, three repeated trials, and lifecycle/transition checks were not independently recorded. Physical visibility on the headless development host remains unconfirmed.

### Earlier development Mac → Teams → laptop attempt

- Sender: this macOS 26.6.2 host, Chrome 157.0.8103.39, Teams web meeting.
- The Chrome picker explicitly selected Entire Screen with system audio off. Its screen thumbnail showed normal desktop content and the ordinary lab window.
- Two fresh sharing streams were attempted. The receiver reported an entirely dark picture for the ordinary markers 2468 and 8642.
- The lab process was then fully exited during the second stream; the receiver still reported black while an ordinary CaptureProbe results window was shown. A fresh third stream without the lab was not tested.
- Teams console diagnostics included NotAllowedError / permissionDeniedError. Chrome's macOS recording switch was on; this does not by itself establish that every media request succeeded.
- The system's display hardware report listed the Apple M4 GPU but no connected physical displays, while the graphical session exposed a 1920 × 1080 display. A headless/virtual-display interaction is a possible, unproven factor.
- No protected-mode receiver pass is claimed because the visible control never passed. This is not evidence of successfully hiding only the lab window.
- Sharing was stopped. Retest first with the lab closed on a Mac with an attached or built-in display, confirm a normal changing desktop reaches the receiver, and only then test the four lab modes.

No meeting invitation, passcode, account data, or raw capture is stored in this document. Update a client result only after recording its actual client/version, sharing mode, receiver observations and trial count.
