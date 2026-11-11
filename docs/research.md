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

## ChatGPT web integration

- [Apple WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) and [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore): native web rendering with persistent or nonpersistent website storage. This does not establish that OpenAI supports every third-party embedded environment.
- [Apple WKUIDelegate](https://developer.apple.com/documentation/webkit/wkuidelegate): popup creation, JavaScript dialogs, file pickers and media permissions. App-owned windows need their own capture settings.
- [Google OAuth secure-browser policy](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers): embedded user agents can be blocked. Switching rendering engines does not remove this restriction.
- [OpenAI password settings](https://help.openai.com/en/articles/4936828-resetting-or-changing-your-chatgpt-password) and [account settings](https://help.openai.com/en/articles/4936827-changing-your-openai-account-email-address): existing social-login users may add an OpenAI password when their account offers it. The account owner performs credential changes, not the agent.
- [Apple ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession): an app-specific authorization callback mechanism, not a general transfer of Safari/Chrome login cookies into WKWebView.
- [OpenAI Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source): eligible plan usage for API inference does not grant access to existing ChatGPT conversations. This is a different integration route and is not implemented in this website-based release.

The approved route uses the unmodified official website, the normal WebKit user agent and no injected scripts in the real ChatGPT session. Synthetic HTML is confined to the offline lab.

## Development skills used

- [Matt Pocock research](https://github.com/mattpocock/skills/blob/main/skills/engineering/research/SKILL.md): primary-source research and explicit evidence.
- [Superpowers brainstorming](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md): scope and route selection.
- [Superpowers writing-plans](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md): implementation boundaries and acceptance criteria.
- [Superpowers executing-plans](https://github.com/obra/superpowers/blob/main/skills/executing-plans/SKILL.md): task execution and a final independent review.
- [Superpowers verification-before-completion](https://github.com/obra/superpowers/blob/main/skills/verification-before-completion/SKILL.md): actual tests before completion claims.

The repositories were read, not installed wholesale. User instructions override skill defaults such as automatic commits.
