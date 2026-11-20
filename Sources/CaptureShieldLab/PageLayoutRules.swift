import Foundation

/// Versioned, local rules for presentation only. No account data or network calls.
/// Keep layout matching here so a site change does not alter uploads or dictation.
enum PageLayoutRules {
    static let version = "0.6.8.1"
    static let script = #"""
    const adapterVersion = '0.6.8.1';
    const documentID = crypto.randomUUID ? crypto.randomUUID() : String(Math.random()) + String(Date.now());
    const sidebarSelector = 'button[aria-controls="app-shell-sidebar"],button[aria-controls="ds-sidebar"],button[aria-label="Close sidebar"],button[aria-label="Hide sidebar"],button[aria-label="Open sidebar"],button[aria-label="Toggle sidebar"],button[aria-label="关闭边栏"],button[aria-label="隐藏边栏"],button[aria-label="打开边栏"],button[aria-label="关闭侧边栏"],button[aria-label="打开侧边栏"],button[aria-label="显示/隐藏侧边栏"]';
    const nameOfControl = e => {
      const name = e.getAttribute('aria-label') || e.getAttribute('title');
      if (name) return name.trim();
      const copy = e.cloneNode(true); copy.querySelectorAll('kbd,[aria-hidden="true"]').forEach(n => n.remove());
      return (copy.textContent || '').replace(/\s+/g,' ').trim();
    };
    const enabledControl = e => !e.disabled && e.getAttribute('aria-disabled') !== 'true';
    const unique = values => values.length === 1 ? values[0] : null;
    const railHome = () => unique([...document.querySelectorAll('#app-shell-sidebar nav button[aria-expanded],#app-shell-sidebar [role="navigation"] button[aria-expanded]')]
      .filter(e => visible(e) && enabledControl(e) && /^(Home|首页)$/.test(nameOfControl(e))));
    const sidebarButtons = () => [...document.querySelectorAll(sidebarSelector)].filter(enabledControl);
    const targetOf = e => document.getElementById(e.getAttribute('aria-controls') || '')
      || document.getElementById('app-shell-sidebar') || document.getElementById('ds-sidebar');
    const closeName = e => /^(Close sidebar|Hide sidebar|关闭边栏|隐藏边栏|关闭侧边栏)$/.test(nameOfControl(e));
    const hoverControl = e => {
      if (e.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
      const r=e.getBoundingClientRect(),s=getComputedStyle(e);
      return r.width>0 && r.height>0 && r.right>0 && r.bottom>0 && r.left<innerWidth && r.top<innerHeight && s.display!=='none' && s.visibility!=='hidden';
    };
    const transparentOpener = e => e.getAttribute('aria-expanded')==='false' && targetOf(e) && hoverControl(e);
    const sidebar = () => {
      const home = railHome(), controls = sidebarButtons();
      const openControls = controls.filter(e => (visible(e) || (e.hasAttribute('aria-controls') && hoverControl(e) && !targetOf(e)?.contains(e))) && (e.getAttribute('aria-expanded') === 'true' || closeName(e))
        && targetOf(e) && visible(targetOf(e)));
      const close = unique(openControls.filter(closeName)) || unique(openControls);
      const open = unique(controls.filter(e => (visible(e) || transparentOpener(e)) && e.getAttribute('aria-expanded') === 'false'))
        || unique(controls.filter(e => visible(e) && /^(Open sidebar|打开边栏|打开侧边栏)$/.test(nameOfControl(e))));
      const collapsed = home || (open && targetOf(open) && !visible(targetOf(open)));
      return {profile:home?'navigation-rail':controls.length?'classic':'unknown', home, close, open,
        state:close?'expanded':collapsed?'collapsed':'unavailable', floating:home?.getAttribute('aria-expanded') === 'true'};
    };
    const knownShell = () => {
      const s = sidebar();
      return s.profile !== 'unknown' && !!document.querySelector('main,[role="main"],#thread');
    };
    let disposed = false, initialSidebarAttempted = false;
    const createdAt = performance.now();
    const initialCollapse = () => {
      if(userChoseSidebar || initialSidebarAttempted) return;
      const s=sidebar();
      if(s.state==='unavailable') return;
      // Record an already-closed layout immediately. A background WebView may
      // throttle the hydration timer until after the website opens its drawer.
      if(s.state==='collapsed') { initialSidebarAttempted=true; return; }
      if(performance.now()-createdAt<250) return;
      // Already collapsed is a completed initial layout too. Never wait for a
      // later user hover/focus to open history and then collapse it underneath them.
      initialSidebarAttempted=true;
      // Home may navigate to a different chat. Never synthesize that action
      // to dismiss a flyout; leave website hover/focus behavior to the website.
      if(s.state==='expanded' && !s.floating) s.close?.click();
    };
    const ownedMarkers = new Map();
    const markSurface = (node, attribute, next) => {
      if(!next.has(node)) next.set(node,new Set()); next.get(node).add(attribute);
      set(node,attribute,'');
    };
    const syncMarkers = next => {
      for(const [node,attributes] of ownedMarkers) for(const attribute of attributes)
        if(!next.get(node)?.has(attribute)) node.removeAttribute(attribute);
      ownedMarkers.clear(); for(const [node,attributes] of next) ownedMarkers.set(node,attributes);
    };
    const contentSurface = node => node.matches('button,input,textarea,pre,code,article,img,video,canvas,svg,[data-message-author-role],[data-cs-thumbnail]')
      || !!node.closest('article,pre,code,[data-message-author-role],[data-cs-thumbnail]');
    const decorative = (node,pseudo) => {
      const s=getComputedStyle(node,pseudo),r=node.getBoundingClientRect();
      return (s.content==='""'||s.content==="''") && ['absolute','fixed'].includes(s.position) && s.pointerEvents==='none'
        && r.width>=innerWidth*.5 && r.height>=innerHeight*.4
        && parseFloat(s.width)>=r.width*.5 && parseFloat(s.height)>=r.height*.5;
    };
    const backgroundSurfaces = editor => {
      const surfaces=new Set();
      const main=document.querySelector('main,[role="main"],#thread');
      for(const start of [editor?.parentElement,main]) for(let node=start;node&&node!==document.body;node=node.parentElement) {
        if(!contentSurface(node) && (node.matches('main,[role="main"],#thread') || node.getBoundingClientRect().width>=innerWidth*.65)) surfaces.add(node);
      }
      return surfaces;
    };
    const applyBackground = editor => {
      const next=new Map();
      for(const node of backgroundSurfaces(editor)) {
        markSurface(node,'data-cs-surface',next);
        if(decorative(node,'::before')) markSurface(node,'data-cs-backdrop-before',next);
        if(decorative(node,'::after')) markSurface(node,'data-cs-backdrop-after',next);
      }
      syncMarkers(next);
    };
    const painted = style => style.backgroundImage !== 'none'
      || !['transparent','rgba(0, 0, 0, 0)'].includes(style.backgroundColor);
    const report = () => {
      const s=sidebar();
      let opaque=0,decorations=0;
      const editors=[...document.querySelectorAll(editorSelector)].filter(rendered);
      const recognized=editors.length===1||knownShell();
      const surfaces=backgroundSurfaces(editors.length===1?editors[0]:null);
      if(themed) for(const node of [document.documentElement,document.body,...surfaces]) {
        if(painted(getComputedStyle(node))) opaque++;
        for(const [attribute,pseudo] of [['data-cs-backdrop-before','::before'],['data-cs-backdrop-after','::after']])
          if(decorative(node,pseudo)) { decorations++; if(painted(getComputedStyle(node,pseudo))) opaque++; }
      }
      const reason=!allowed()?'unsupported-page':isAuthentication()?'authentication':!themed||!recognized?'unrecognized-layout':opaque?'opaque-page-surface':'ready';
      return {version:adapterVersion,documentID,profile:s.profile,sidebar:s.state,eligible:themed,
        surfaces:Math.min(surfaces.size,100),decorations:Math.min(decorations,100),opaque:Math.min(opaque,100),reason};
    };
    """#
}
