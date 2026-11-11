# ChatGPT window implementation record

Approved plan: native WKWebView in the existing Swift/AppKit app; default Legacy sharing; existing account and web history; text only; preserved synthetic lab and independent recorder; portable source delivery through GitHub.

## Decisions and gates

- The user's project-wide commit/push authorization is recorded in AGENTS.md. No additional commit authorization is required for this work.
- Use the existing clean `codex/initial-lab` branch/workspace. Keep a compact execution ledger here rather than installing the external skill repositories or their bookkeeping scripts.
- Follow the selected superpowers execution, test-first and verification workflow, including one independent final review. GUI integration is validated in the actual app; meaningful pure behavior has automated coverage.
- Pre-flight: changing the default launch to ChatGPT must preserve `--session` as synthetic-only. The verifier's WebView uses a nonpersistent store and bundled synthetic HTML, never the chat session.
- Login gate: validate the official website, then ask the user to sign in personally. Existing Google users may add an OpenAI password if their account offers it. No browser cookie import, user-agent impersonation or automatic API fallback.
- Capture gate: the plain AppKit laptop observation does not certify WebKit content. Physical local visibility and three receiver-side Teams trials remain separate human checks.

## Progress

- Baseline: d33c8f7, clean working tree. Original lab has 13 behavioral tests; no ChatGPT window yet.
- Implementing launch routing, navigation boundaries and restored-window placement with test-first checks.
- RED: three new tests failed against placeholder routing/navigation/placement; the fourth preserved-position case already passed. GREEN: all 17 tests passed after implementation.
- First app build succeeded. Swift 6 WebKit callbacks required explicit MainActor/Sendable completion signatures; corrected and rebuilt without warnings.
- Actual app inspection: ChatGPT home rendered its login buttons, sidebar and text entry; official login dialog opened. No site rejection encountered at this stage. User login/history confirmation is pending; the window-specific screenshot is blank under Legacy and cannot prove physical local visibility.
- Synthetic WebView uses a nonpersistent store, offline HTML with a restrictive CSP, and load readiness/error in the existing recorder handshake. Reports identify native versus WebView content. Local confirmation can now target either candidate independently.
- Independent read-only review identified repeated-Hide popup loss and unrestricted image/file clipboard paste. Both regression tests failed before the fixes. Pending restore now merges visible windows; app paste inserts only plain native text and rejects file/image/PDF representations. No scripts are injected into the real website.
- Review GREEN: all 19 tests passed. Swift 6 event-monitor isolation returns a Sendable boolean instead of returning NSEvent across isolation. Final QA bundle build and strict code-signature verification passed without warnings.
- Actual synthetic UI: Chinese/Unicode paste, complete synthetic streaming reply and suppressed right-click menu observed. The rebuilt QA verifier was denied TCC recording access and correctly saved not-tested results; no capture success is claimed.
- Real login, physical local visibility and laptop Teams receiver checks remain pending. Preserve the current login window while preparing source delivery; do not overwrite its running bundle or collect account data for debugging.
