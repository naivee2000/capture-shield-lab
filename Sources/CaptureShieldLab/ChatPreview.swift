import Foundation

enum ChatPreview {
    static let html = #"""
    <!doctype html><html data-theme="light" lang="en"><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; form-action 'none'">
    <style>
    :root {font:16px -apple-system,sans-serif;color:#eee;background:#101010;--spacing:4px}
    body {margin:0} nav {width:220px;background:#222;padding:16px;position:fixed;inset:0 auto 0 0}
    main {margin-left:252px;padding:24px} body.folded nav {display:none} body.folded main{margin-left:0}
    button {font:inherit;padding:6px 10px;background:#2b353b;border:1px solid #55636e;color:white;border-radius:7px}
    h1{font-size:26px;color:#65e4ca} pre{background:#222;padding:16px;overflow:auto}
    [data-composer-body]{border:1px solid #555;border-radius:16px;padding:18px;margin-top:20px}
    [data-rich-text-layout]{margin-block:14px} [contenteditable]{padding:8px;white-space:pre-wrap;outline:none;min-height:44px}
    aside{color:#a8b4b7;font-size:13px} .actions{display:flex;gap:8px;margin-top:8px}
    </style></head><body>
    <nav id="app-shell-sidebar"><strong>Test history</strong><p>Synthetic conversation</p><p>No account data</p></nav>
    <main><button aria-label="Toggle sidebar" aria-controls="app-shell-sidebar" aria-expanded="true">Sidebar</button>
    <h1>CaptureShield UI preview</h1><aside>Offline synthetic page · use Normal mode to inspect screenshots.</aside>
    <p>Text selection, typing, scrolling and copy should work normally. This page never contacts ChatGPT.</p>
    <pre><code>const reply = "Hello, 世界";
    // Long code line for horizontal scrolling: ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ</code></pre>
    <div data-composer-body><div data-rich-text-layout="single-line"><div data-composer-markdown contenteditable="true" role="textbox" aria-label="Synthetic chat input" spellcheck="true"></div></div>
    <button id="send">Stream reply</button></div><p id="reply" aria-live="polite">Ready.</p>
    <div class="actions"><button id="popup">Open test popup</button><button id="dialog">Open test dialog</button></div>
    <p>English: teh recieve. Chinese: 输入与换行测试。</p>
    <p>Other applications should cover this window when focused.</p><p>End of synthetic content.</p>
    </main><script>
    const toggle=document.querySelector('[aria-controls="app-shell-sidebar"]');
    toggle.onclick=()=>{const open=toggle.getAttribute('aria-expanded')==='true';toggle.setAttribute('aria-expanded',String(!open));document.body.classList.toggle('folded',open);};
    document.querySelector('#send').onclick=()=>{const target=document.querySelector('#reply');target.textContent='';let i=0;const text='Synthetic reply complete. 中文输入保持正常。';const id=setInterval(()=>{target.textContent+=text[i++];if(i===text.length)clearInterval(id)},60);};
    document.querySelector('#popup').onclick=()=>window.open('about:blank','CaptureShieldSyntheticPopup');
    document.querySelector('#dialog').onclick=()=>confirm('Synthetic dialog. Check mode and opacity inheritance.');
    </script></body></html>
    """#
}
