---
name: capture-shield-compatibility
description: Review, test and repair CaptureShield on Apple Silicon macOS 15.8.2 through 27.x using the actual packaged app, isolated UI fixtures and recorded host evidence. Use for this repository's OS upgrades, UI regressions and test cleanup, not as a claim that meeting receivers cannot see content.
---

# CaptureShield compatibility

Read the repository's `AGENTS.md`, `docs/ui-validation.md`, and `docs/os-validation.md` before testing. Resolve their paths from the repository root; never assume a particular external disk or developer account. Read `docs/maintenance.md` when locating an OS-specific implementation. Keep the existing deployment floor unless the user explicitly changes it.

## Run and diagnose

- Start with a clean-source inventory: commit, working-tree changes, actual OS/build, architecture, toolchain, app version/build and running app paths. Preserve user sessions and uncommitted changes.
- Use the commands and evidence schema in `docs/ui-validation.md`. Run `scripts/test-ui.sh --preflight` before UI automation. Full Xcode and an authorized graphical session are required; CLT-only builds cannot establish UI success. Keep `DEVELOPER_DIR` process-scoped.
- Test the app produced by `scripts/build.sh`, through the independent XCTest project. Use unique test bundle IDs, `--chat-preview`, temporary preferences and synthetic inputs. Do not direct the fixture at a personal app or load ChatGPT account storage. Preview speech is deterministic synthetic output, not capture or recognition.
- Run the existing suite once and the UI suite three sequential rounds on each available actual OS. Disable parallel UI execution and failure retries. Zero, missing, skipped or partially executed UI cases cannot pass. Exercise the documented deliberate-negative control to establish that wrong expectations fail.
- Keep the first failure. Classify it as application, harness or environment failure before changing anything. Reproduce an application bug with a meaningful failing assertion, make the smallest repair, then rerun affected and complete suites. Do not relax assertions or relabel environment failures as application passes.
- An unavailable target OS or UI authorization is `not-tested`. Runner labels are not exact versions. Record the host's actual patch/build; never reuse an older commit's report as a new result. A hosted 27.x test cannot certify all future versions.

## Evidence boundaries

Report four independent layers: build/sign/register; actual packaged-app UI; real ChatGPT/capture/speech/IME functionality; independent meeting receiver. Use `pass`, `fail`, or `not-tested` with counts and failure stage. Preserve the source commit, app version/build and executable hash, actual system/build, architecture and toolchain.

Window sharing properties, alpha metadata, local screenshots, black captures and Dock disappearance do not establish receiver privacy. Chinese Unicode text or synthetic composition events do not establish physical Pinyin/candidate behavior. Receiver checks need exact sender/receiver clients, full-screen sharing and an independent observer.

Do not modify TCC databases, disable SIP, extract cookies, clear login data, silently change modes or suppress mandatory capture indicators. This skill adds no authorization: follow the user's current scope and the repository's commit/push rules.

## Deliver and clean

Use a clean clone, a checkout path containing spaces and a separate build directory. Review the diff and state completed validation before the authorized commit/push; read back the remote SHA. Preserve current repository visibility.

Extract a sanitized technical summary before running the per-run cleanup command. Start with `cleanup-tests.sh --dry-run`, inspect ownership and use state, then remove only explicitly identified runs. Keep source tests, fixtures, the Skill and summaries. Never recursively delete an arbitrary path supplied by a report. Do not close unrelated windows, unregister personal apps, remove account stores or wipe shared caches. If inspection fails or ownership is uncertain, retain the resource and explain it.

Raw images, audio, transcripts, chats, invitation links and xcresult attachments stay outside Git. Close only task-created test windows and verify temporary mounts, files and registered test apps are gone. Record actual reclaimed space and justified retained items.
