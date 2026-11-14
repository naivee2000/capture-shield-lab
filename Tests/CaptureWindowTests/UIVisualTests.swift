import AppKit
import WebKit
import Testing
import CaptureCore
@testable import CaptureShieldLab

/// Opt-in render exports of synthetic content only, never the account's WebView.
/// Set CAPTURESHIELD_UI_EXPORT_DIR to a local directory outside Git.
@MainActor @Suite(.serialized) struct UIVisualTests {
    static let html = #"""
    <!doctype html><html><head><meta charset="utf-8"><style>
    :root{font:16px -apple-system,sans-serif;color:#eee;background:#101010}
    *{box-sizing:border-box}body{margin:0} main{height:100vh;display:flex;flex-direction:column;background:#101010}
    header{padding:14px 20px;font-weight:600;border-bottom:1px solid #444}
    #messages{flex:1;min-height:0;overflow:auto;padding:16px 24px}
    h2{font-size:19px;color:#6ee7c8;margin-top:0}p{line-height:1.55;margin:8px 0}
    pre{background:#20282e;padding:12px;border-radius:8px;font-size:14px;overflow:auto}
    form{margin:8px 16px 12px;padding:16px;background:#25292d;border:1px solid #555;border-radius:16px}
    textarea{width:100%;resize:none;min-height:60px;background:transparent;border:0;color:white;font:inherit;outline:none}
    .actions{display:flex;justify-content:space-between;align-items:center;font-size:13px;color:#bbb}
    button{padding:5px 12px;background:#35443f;color:white;border:1px solid #738b80;border-radius:8px}
    #attachment{display:none;width:48px;height:48px;border-radius:5px;margin-bottom:4px}
    </style></head><body><main><header>CaptureShield · synthetic layout comparison</header>
    <div id="messages"><h2>Room to read the answer</h2><p>Only the background should be translucent. Text, code and images keep their normal contrast.</p>
    <p>中文输入、图片附件和草稿应完整保留。</p><pre><code>const total = 7 + 5;
    console.log(total); // 12</code></pre><p>This is a local fixture. No account, meeting audio or real conversation is used.</p>
    <p>Resize the window and continue reading. The recording controls remain available below.</p></div>
    <form data-composer-body><img id="attachment" alt="Synthetic attachment" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='48' height='48'%3E%3Crect width='48' height='48' fill='%233fbf9b'/%3E%3Ctext x='10' y='31' font-size='22' fill='black'%3E42%3C/text%3E%3C/svg%3E">
    <div data-rich-text-layout><textarea id="prompt-textarea" placeholder="Ask a question"></textarea></div><div class="actions"><span>＋ Attach image</span><button>Send</button></div></form>
    </main><script>window.sends=0;document.querySelector('form').onsubmit=e=>{e.preventDefault();window.sends++};</script></body></html>
    """#
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_EXPORT_DIR"] != nil))
    func exportSyntheticLayouts() async throws {
        guard let folder = ProcessInfo.processInfo.environment["CAPTURESHIELD_UI_EXPORT_DIR"] else { return }
        let directory = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let owner = ChatWindow(configuration: config, isMain: false, preferences: .init(mode: .normal), preview: true)
        defer { owner.webView.stopLoading(); owner.closeTestFixture() }
        owner.window?.title = "CaptureShield synthetic comparison"; owner.window?.orderFront(nil)
        owner.showSpeechPane(true)
        owner.speechPane.setSources([.init(bundleID: "synthetic.audio", name: "Synthetic Audio", pid: 1)], savedBundle: "synthetic.audio")
        owner.webView.loadHTMLString(Self.html, baseURL: nil)
        for _ in 0..<100 {
            if (try? await owner.webView.evaluateJavaScript("!!document.querySelector('[data-cs-editor]')")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        for size in [NSSize(width: 980, height: 700), NSSize(width: 640, height: 480)] {
            owner.window?.setFrame(NSRect(origin: NSPoint(x: 100, y: 100), size: size), display: true)
            #expect(owner.window?.frame.size == size)
            for scenario in ["idle", "multiline", "image", "recording", "processing", "retained", "cancelled", "error"] {
                owner.speechPane.setTranscript("")
                _ = try await owner.webView.evaluateJavaScript("document.querySelector('textarea').value=\(scenario == "multiline" ? "'Synthetic draft 中文\\n'.repeat(12)" : "''");document.querySelector('#attachment').style.display='\(scenario == "image" ? "block" : "none")';document.querySelector('textarea').dispatchEvent(new Event('input',{bubbles:true}));")
                #if !CAPTURESHIELD_UI_BEFORE
                owner.speechPane.showMessage("Choose a source. Browser audio includes other tabs. Microphone is off.")
                let phase: SpeechSessionState.Phase = scenario == "recording" ? .recording : scenario == "processing" ? .transcribing : scenario == "retained" ? .ready : .idle
                if scenario == "retained" { owner.speechPane.setTranscript("A retained synthetic transcript. 中文可编辑。") }
                owner.speechPane.update(phase: phase, busy: false, inserting: false, uncertain: false, sourceName: "Synthetic Audio")
                owner.speechPane.setElapsed(37)
                if scenario == "error" { owner.speechPane.showMessage("Synthetic test error. Your draft is unchanged. Open details to recover.", error: true) }
                if scenario == "retained" { owner.speechPane.toggleTranscript() }
                #else
                owner.speechPane.status.stringValue = "Choose a source. Microphone is off."
                owner.setStatus("Choose a source. Microphone is off.")
                #endif
                owner.window?.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                #expect(owner.window?.frame.size == size)
                #expect(owner.window?.contentView?.bounds.width == size.width)
                let webImage = try await owner.webView.takeSnapshot(configuration: nil)
                let content = try #require(owner.window?.contentView)
                let native = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: native)
                let output = NSImage(size: content.bounds.size)
                output.lockFocus()
                NSColor(srgbRed: 16/255, green: 16/255, blue: 16/255, alpha: 1).setFill(); content.bounds.fill()
                NSImage(cgImage: try #require(native.cgImage), size: content.bounds.size).draw(in: content.bounds)
                webImage.draw(in: owner.webView.convert(owner.webView.bounds, to: content))
                output.unlockFocus()
                let bitmap = try #require(output.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("\(Int(size.width))x\(Int(size.height))-\(scenario).png"))
                #expect(try await owner.webView.evaluateJavaScript("window.sends") as? Int == 0)
            }
        }
    }
}
