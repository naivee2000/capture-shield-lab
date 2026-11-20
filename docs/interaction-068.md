# 0.6.8 image confirmation, resizing and history

Version **0.6.8 / build 17**, Apple Silicon, macOS 15.6+ runtime, Swift 6.2+/SDK 26+ to build. Login storage, chat drafts, attachments, transcription, shortcuts, pinning and the background-only Legacy transparency are retained.

## Image confirmation

In the image preview, **Return or keypad Enter** performs the same confirmation as **Add to Chat ↵**. Only unmodified keys in that owned window qualify. Composition and modal input take precedence; crop dragging and disabled/busy confirmation do not add an image. The key is consumed during handoff, and a held key stays consumed until release even if the attachment finishes first. The coordinator still requires a visible completed webpage attachment; file-chooser success alone is insufficient. After confirmation, normal chat Return behavior resumes. Adding may upload the image, but CaptureShield does not send the message.

Crops are stored in source image coordinates. Changing window size only changes the drawing transform; **Reset crop** clears the selection. Failures retain the crop and require explicit recovery. No page reload, draft replacement, clipboard operation or automatic retry is introduced.

## Legacy resize grip

Legacy disables native edge resizing and places a small diagonal grip in the bottom-right **inside** the protected window. A 22-point trailing gutter keeps it outside page scrollbars, editor/attachment controls, transcription and preview buttons; it adds no full bottom row. Drag with the ordinary arrow. The top-left stays fixed, the normal minimum is 640×480, and dimensions remain within the display's usable region. Position/size persist through the existing save path. Normal restores native edge resizing and removes the gutter/grip.

Because AppKit disables its green zoom widget on a nonresizable shell, Legacy supplies a zoom/restore button at the same traffic-light location. Normal retains the system widget. Title dragging, minimize, Always on Top and keyboard movement are unchanged. No global cursor mutation, hidden cursor lease, private resize API or timer-based arrow override is used. Private Cursor remains offline-only.

A preliminary isolated AppKit experiment requested `disableCursorRects()` plus `NSCursor.arrow.set()`. The remote development interaction did not supply continuous live-resize/system-cursor samples, so it is **not evidence that native edges reliably keep an arrow**. The approved in-window fallback is used uniformly. Capture applications can sample the system cursor independently; a window flag, synthetic grip test or drawn arrow is not a receiver verdict. Independent capture must include the system cursor (`showsCursor = true`).

## Website history

The native Sidebar toolbar button, its overflow action and simulated open/pin operations are removed. Use the **website's Home / 首页 hover entry** and normal website navigation. The user reported that this real entry works while the native wrapper remained unreliable; the older synthetic tests did not establish live reliability.

Automatic collapse is attempted at most once after initial ready layout, including when the sidebar is already collapsed. Trusted hover, focus or click on the known history region cancels automatic collapse. Failed initial collapse is not retried on every DOM mutation. Structural layout/background recognition and the read-only Compatibility check remain, without reading history titles or modifying a draft.

## Repeatable verification

```bash
bash scripts/test.sh --no-parallel
python3 -m unittest discover -s Tests/ScriptTests -v
bash scripts/test-ui.sh --preflight
bash scripts/test-ui.sh
```

The packaged suite runs 14 scenarios three sequential rounds per available actual OS, without failure retries. [UI prerequisites and cleanup](ui-validation.md) apply. The review targets are actual macOS 15.8.2, 26 and 27 hosts; exact patch/build, commit and counts go in [the release ledger](validation-interaction-068.json). Missing environments remain `not-tested`.

## Sender and receiver acceptance

On the updated sender, preserve a harmless existing draft and image. Add a full screenshot with Return, a crop with keypad Enter, resize after selecting a crop, add several images, delete/re-add, cancel and recover from a failed upload. Check crop pixels, counts, unchanged draft and no automatic sends. Test held Return while the preview/handoff is active; release before using normal chat Return. Physical Pinyin composition must retain normal candidate selection.

At 980×700 and 640×480, test Legacy grip hover/drag, zoom/restore, minimize, title dragging, keyboard movement, app switching and Normal edges. Open website history by Home hover/focus; verify it stays available while typing and after mode/sheet changes. There must be no native Sidebar item in the toolbar or overflow.

Repeat **three times** with Teams desktop entire-display sharing and an independent Chrome receiver. Record sender OS/build, application commit and both client versions. Receiver should see an ordinary arrow rather than resize arrows, no hidden-window/grip artifacts, and normal background updates. Record physical local usability and receiver visibility separately. Real ChatGPT and receiver results cannot be inferred from offline UI or native tests; no universal hiding claim is made.
