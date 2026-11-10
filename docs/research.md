# Research basis

Checked 2026-11-10. Documentation and experimental evidence are different kinds of support.

| Source | What it supports |
| --- | --- |
| [Apple NSWindow.SharingType.none](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none) | The legacy flag must not be relied on to omit captured content. |
| [Apple DTS, July 2025](https://developer.apple.com/forums/thread/792152) | No supported public API for generally preventing screen capture in the discussed macOS 15.4+ case. |
| [Electron BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window#winsetcontentprotectionenable) | Electron's macOS content-protection flag has ScreenCaptureKit limitations; choosing Electron alone does not solve them. |
| [Apple preventsCapture](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/preventscapture) | A public property protecting the video layer. Apple does not document the arbitrary-UI mask technique as a general window-exclusion guarantee. |
| [Daiki Matsudate's experiment](https://zenn.dev/d_date/articles/macos-capture-protection-preventscapture) | A first-person macOS 26.7 experiment using protected video data as a mask. Zoom, Meet, Teams and this development machine's macOS 26.6.2 still require independent testing. |
| [Cluely compatibility](https://support.cluely.com/en/articles/12364416-what-apps-are-supported-for-undetectability) | Cluely also documents unsupported platforms/capture modes; its broad marketing is not universal technical evidence. |
| [Swift Testing distributions](https://github.com/swiftlang/swift-testing/blob/main/Documentation/Distributions.md) | Swift Testing ships in Apple toolchains; the project does not need a third-party testing download. |

The app implements the mask idea with native Apple APIs; it does not copy an existing third-party app, modify ChatGPT, inject code, or use private WindowServer APIs. A normal launcher cannot confer this protection on another process's existing windows.

## Development skills used

- [Matt Pocock research](https://github.com/mattpocock/skills/blob/main/skills/engineering/research/SKILL.md): primary-source research and explicit evidence.
- [Superpowers brainstorming](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md): scope and route selection.
- [Superpowers writing-plans](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md): implementation boundaries and acceptance criteria.
- [Superpowers executing-plans](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md): task execution and a final independent review.
- [Superpowers verification-before-completion](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md): actual tests before completion claims.

The repositories were read, not installed wholesale. User instructions override skill defaults such as automatic commits.
