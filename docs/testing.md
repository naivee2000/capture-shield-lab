# Manual verification matrix

Do not generalize a pass from one app, browser, OS version, display, or sharing mode to another. Source-build success and hidden-window success are separate outcomes.

## Record each trial

Use an ignored file under artifacts/ or the report directory. Record:

- Date, macOS version/build, display resolution and scale.
- Application and browser name/version; browser vs native Teams must be distinguished.
- Capture order: capture first vs window first.
- Entire display vs selected window vs browser tab. Whole-display is the first-release target.
- Protection mode, receiver device/client, and evidence location.
- Local visibility and typing, remote content leakage, black/blank rectangle, frame/border/shadow leakage, flashes.
- Result: pass / fail / not-tested, with a concrete reason.

Do not store meeting invitation URLs, passcodes, login data, cookies, or real chat content in Git.

## ChatGPT and WebView checks (0.2)

First run the disposable WebView with `bash scripts/dev.sh --web-test`. In CaptureProbe choose **Synthetic WebView** and test both capture orders. Do not have a real chat window overlapping the test display. After recording, select Legacy and Protected mask in turn and confirm each only from the actual local screen.

Then validate the real ChatGPT window with synthetic messages:

1. Sign in personally, verify the original account/history, create a fresh test chat and receive a complete reply. Never give the agent your password or OTP.
2. Send a follow-up, use Chinese input, copy a reply, scroll, navigate back/forward and open an HTTPS link. Popup windows must stay within the app with Legacy set before display.
3. Restart the app and check whether the session persists. Restore the app after disconnecting an external display; its window should be on a remaining display.
4. Test Cmd-Shift-Space with both the app and another app focused. Main, popup and attached dialog windows should all disappear together and return together. Shortcut conflicts must be reported.
5. Test loss of network and Reload. A terminated WebKit content process must show a recovery message; never automatically resubmit a prompt.
6. Test **Clear login…** only when you intend to sign this app out: Cancel must preserve the session; Confirm must close popups and return to a fresh signed-out page, without back-navigation into old private pages. Cloud history remains unchanged.
7. File pickers, downloads and microphone/camera requests are unsupported in this version. System candidate windows and OS dialogs are separate surfaces; record their behavior separately.

For each of three laptop-to-receiver Teams trials, record source commit, client/OS versions, startup order, local text entry and complete receiver background. Other windows must visibly continue updating. A synthetic WebView pass is not a claim that the live website, dialogs or every capture method passes.

## Local interaction checks

Test ordinary, legacy, unprotected mask and protected mask. Use only synthetic content.

1. Type, select, paste, and scroll text.
2. Drag, resize, hide/show; try starting recording both before and after showing the panel.
3. Change Spaces and enter/leave another app's full-screen view.
4. Sleep/wake or lock/unlock: mask failure must hide content, not disable protection silently. Reinitialize and run a fresh verification.
5. If available, move between displays, vary display scale, and unplug/reconnect an external display.
6. Separately inspect system menus, context menus, tooltips, IME candidate windows and permission dialogs. They are separate surfaces and are not protected by this panel's mask.
7. Check built-in screenshots and screen recordings separately; don't infer those results from SCStream.

The automated verifier intentionally aborts if you move/resize the panel during a fixed-baseline run. Interaction tests are manual receiver/recording tests.

## Meetings: Zoom, Google Meet, Teams

For each application, run at least **three trials** with an independent receiving device:

1. Use a private test meeting and synthetic desktop content. Keep microphone and camera off unless explicitly needed.
2. Share the **entire test display**. Sharing just the checkerboard/window/tab is a different test and cannot establish full-display exclusion.
3. Receiver confirms the ordinary and unprotected-mask controls are visible.
4. Switch to protected mode; confirm local visibility and typing.
5. Receiver observes while typing, dragging, resizing, scrolling, hiding/showing and restarting sharing. Look for transient frames and window chrome as well as text.
6. Receiver confirms the background is continuous where the panel sits. A black/blank rectangle is failure.
7. Repeat using the opposite startup order. Retain receiver evidence when consented to by the test participants.

The app never joins meetings, changes other applications' capture settings, or uploads recordings automatically. Meeting rows in automatic reports remain not-tested; record manual meeting results in a separate trial report rather than turning a local capture pass into a meeting pass.

## Automated classifier tolerances

Pixels are decoded from BGRA to RGBA. A pixel differs if any RGB channel differs from baseline by more than 16/255. A sampled frame matches only if the differing-pixel fraction is at most 0.0005 and mean RGB absolute error is at most 1.5/255. Black/flat baselines are rejected. The ordinary and unprotected-mask controls must differ from the background in more than 5% of pixels.

These are lab thresholds, not a security proof. Inspect the saved PNGs alongside numeric results. The requested stream rate is 5 fps and each stage compares 12 fresh stable-state samples after a 200 ms presentation-time boundary; startup transitions and shorter flashes are not certified by this test. Use receiver recordings for the real meeting path.

## Native-window and appearance regression checks (0.3)

Use `bash scripts/dev.sh --chat-preview` for a disposable offline page in the real chat shell. A QA build can use a separate `CAPTURESHIELD_APP_ROOT` and `CAPTURESHIELD_BUNDLE_PREFIX` so its preferences, browser store and bundle registration cannot collide with daily-use apps.

- Focus another ordinary app: it should cover the chat window. Drag the title text and toolbar blank areas; select text in the page without moving the window. Check native minimize/zoom and reopen.
- Select Normal: opaque window, ordinary shareability. Select Legacy: 80% whole-window opacity with the existing exclusion flag. Repeat from a popup and inspect both windows. Create a JavaScript dialog in both modes; it must inherit the current mode.
- Keep an unsent synthetic draft, switch modes, change zoom, hide/show and close/reopen the window. Input/session state must survive. Relaunch at a saved non-fullscreen size three times: the frame must not grow with each titlebar reconstruction.
- Exercise 70%, 90% and 140%, the disabled zoom limits and percentage reset. Check long code lines, long input with internal scrolling and the sidebar toggle. Changes must be saved.
- Check delayed webpage hydration and replacement editors. Initially collapse the sidebar even when the first control is not interactive yet; after a real user toggle, never force it closed again on text updates.
- Type English misspellings with spaces, inspect prediction/correction behavior, then test actual Chinese IME composition and selection separately. Unicode paste alone does not verify IME candidates. Check the receiver as well as the local desktop.
- Recheck sharing after changing window type, titlebar and opacity. Existing 0.2 observations are not a 0.3 certification. Record three independent receiving-side trials on the user's working laptop setup.
- Inspect the icon in the generated app bundle and Dock/Finder. Build from a clean clone with no graphics tools installed beyond Apple developer tools.

The synthetic integration tests never load account pages. The live page adapter targets only recognized ChatGPT composer controls and reads no message/input values. If controls change, its safe behavior is to leave the page unchanged; the toolbar reports when the sidebar control is unavailable.
