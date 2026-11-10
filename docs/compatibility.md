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
| Microsoft Teams (Chrome web) | Join route redirected to Microsoft login; operator handoff in progress, no shared-screen receiver result yet |

No meeting invitation, passcode, account data, or raw capture is stored in this document. Update a client result only after recording its actual client/version, sharing mode, receiver observations and trial count.
