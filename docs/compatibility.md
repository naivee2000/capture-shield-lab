# Observed compatibility

Date: 2026-11-10. Development host: Apple Silicon, macOS 26.6.2 (25G83), 1920 × 1080 display.

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
| Microsoft Teams (Chrome web) | Whole-display baseline failed: receiver reported a fully dark screen with an ordinary window; protection compatibility remains unverified |

### Teams attempt details

- Sender: this macOS 26.6.2 host, Chrome 157.0.8103.39, Teams web meeting.
- The Chrome picker explicitly selected Entire Screen with system audio off. Its screen thumbnail showed normal desktop content and the ordinary lab window.
- Two fresh sharing streams were attempted. The receiver reported an entirely dark picture for the ordinary markers 2468 and 8642.
- The lab process was then fully exited during the second stream; the receiver still reported black while an ordinary CaptureProbe results window was shown. A fresh third stream without the lab was not tested.
- Teams console diagnostics included NotAllowedError / permissionDeniedError. Chrome's macOS recording switch was on; this does not by itself establish that every media request succeeded.
- The system's display hardware report listed the Apple M4 GPU but no connected physical displays, while the graphical session exposed a 1920 × 1080 display. A headless/virtual-display interaction is a possible, unproven factor.
- No protected-mode receiver pass is claimed because the visible control never passed. This is not evidence of successfully hiding only the lab window.
- Sharing was stopped. Retest first with the lab closed on a Mac with an attached or built-in display, confirm a normal changing desktop reaches the receiver, and only then test the four lab modes.

No meeting invitation, passcode, account data, or raw capture is stored in this document. Update a client result only after recording its actual client/version, sharing mode, receiver observations and trial count.
