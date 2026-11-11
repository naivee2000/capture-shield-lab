# Observed compatibility

Date: 2026-11-10. Development host: Apple Silicon, macOS 26.6.2 (25G83), 1920 × 1080 display.

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
