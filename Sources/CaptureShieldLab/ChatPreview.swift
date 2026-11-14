import AppKit

enum ChatPreview {
    static let html = #"""
    <!doctype html><html data-theme="light" lang="en"><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src blob: data:; form-action 'none'">
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
    <label>Attach synthetic image <input id="image-file" type="file" accept="image/png,image/jpeg"></label>
    <p id="image-status" role="status">Images: 0 · Sends: 0</p><div id="attachments"></div><input id="image-dimensions" aria-label="Decoded image dimensions" readonly value="No image dimensions">
    <button id="send">Stream reply</button></div><p id="reply" aria-live="polite">Ready.</p>
    <div class="actions"><button id="popup">Open test popup</button><button id="dialog">Open test dialog</button></div>
    <button id="compose-start">Begin synthetic composition</button><button id="compose-end">Commit synthetic composition</button><input id="compose-status" aria-label="Synthetic composition status" readonly value="Composition idle">
    <p>English: teh recieve. Chinese: 输入与换行测试。</p>
    <p>Other applications should cover this window when focused.</p><p>End of synthetic content.</p>
    </main><script>
    const toggle=document.querySelector('[aria-controls="app-shell-sidebar"]');
    toggle.onclick=()=>{const open=toggle.getAttribute('aria-expanded')==='true';toggle.setAttribute('aria-expanded',String(!open));document.body.classList.toggle('folded',open);};
    let sends=0; let imageSequence=0;
    const status=()=>document.querySelector('#image-status').textContent='Images: '+document.querySelector('#attachments').children.length+' · Sends: '+sends;
    document.querySelector('#send').onclick=()=>{sends++;status();const target=document.querySelector('#reply');target.textContent='';let i=0;const text='Synthetic reply complete. 中文输入保持正常。';const id=setInterval(()=>{target.textContent+=text[i++];if(i===text.length)clearInterval(id)},60);};
    document.querySelector('#image-file').onchange=async e=>{
      const file=e.target.files[0];if(!file)return;
      const bytes=(await file.arrayBuffer()).byteLength;
      const number=++imageSequence;
      const card=document.createElement('span');card.style='display:inline-flex;flex-direction:column;margin:4px';
      const image=document.createElement('img');const blob=URL.createObjectURL(file);
      image.onload=()=>document.querySelector('#image-dimensions').value='Last image: '+image.naturalWidth+' x '+image.naturalHeight;
      image.src=blob;image.alt=file.name;image.width=80;image.height=80;
      const remove=document.createElement('button');remove.type='button';
      remove.textContent='Remove image '+number;remove.setAttribute('aria-label','Remove file');
      remove.onclick=()=>{URL.revokeObjectURL(blob);card.remove();status()};
      card.append(image,remove);document.querySelector('#attachments').append(card);
      document.querySelector('#image-file').value='';status();
    };
    document.querySelector('#popup').onclick=()=>window.open('about:blank','CaptureShieldSyntheticPopup');
    for(const [id,event,label] of [['compose-start','compositionstart','Composition active'],['compose-end','compositionend','Composition idle']]){document.getElementById(id).onclick=()=>{const editor=document.querySelector('[contenteditable]');editor.focus();editor.dispatchEvent(new CompositionEvent(event,{bubbles:true}));document.querySelector('#compose-status').value=label;};}
    document.querySelector('#dialog').onclick=()=>confirm('Synthetic dialog. Check mode and opacity inheritance.');
    </script></body></html>
    """#
    @MainActor static func sampleImage() -> CGImage {
        let image = NSImage(size: NSSize(width: 1000, height: 600))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
        let text = "CaptureShield · synthetic image test\n\nWhat is 21 + 21?\n\n中文示例 · No personal data"
        (text as NSString).draw(in: NSRect(x: 50, y: 100, width: 900, height: 440), withAttributes: [
            .font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        NSColor.systemBlue.setFill(); NSRect(x: 800, y: 30, width: 100, height: 100).fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

}
