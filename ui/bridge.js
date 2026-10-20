// Page <-> AutoHotkey messages. Inside Alcadeias this uses WebView2's
// postMessage; opened in a normal browser it talks to a small stand-in host
// so the interface can be developed and tested without Windows.
const host = (() => {
  const wv = window.chrome && window.chrome.webview;
  let seq = 0;
  const pending = new Map();
  const listeners = {};

  function deliver(m) {
    if (m.reply) {
      const fn = pending.get(m.reply);
      pending.delete(m.reply);
      if (fn) fn(m.result);
    } else if (m.event) {
      (listeners[m.event] || []).forEach(f => f(m.value));
    }
  }

  function send(m) {
    if (wv) wv.postMessage(m);
    else setTimeout(() => Mock.receive(m, deliver), 5);
  }

  if (wv) wv.addEventListener('message', e => deliver(e.data));

  return {
    live: !!wv,
    call(cmd, args = {}) {
      return new Promise(res => {
        const id = ++seq;
        pending.set(id, res);
        send({ id, cmd, ...args });
      });
    },
    fire(cmd, args = {}) { send({ id: 0, cmd, ...args }); },
    on(ev, fn) { (listeners[ev] = listeners[ev] || []).push(fn); },
    emit(ev, value) { deliver({ event: ev, value }); }
  };
})();

// ---- stand-in host (browser only) ---------------------------------------
const Mock = (() => {
  const store = { calendar: null, ideas: null };
  const sample = {
    find: [
      { kind: 'goto', cols: ['', 'Inbox has loose files', 'Inbox', '', 'Downloads + Desktop'], buttons: [['open', 'Go']], menu: [] },
      { kind: 'item', cols: ['', 'Pilot episode', 'Project', '2h', 'C:\\Videos\\CLUK Content\\2026-10-01 Pilot episode'], folder: 1, buttons: [['open', 'Open project'], ['browse', 'Look inside']], menu: [['open', 'Open project'], ['browse', 'Look inside'], '-', ['edit', 'Edit…'], ['delete', 'Remove']], edit: 'Edit', del: 'Remove' },
      { kind: 'file', src: 'recent', cols: ['', 'CLUK Content', 'Folder', '5m', 'C:\\Videos'], folder: 1, buttons: [['open', 'Open'], ['browse', 'Look inside'], ['move', 'Move to…']], menu: [['open', 'Open'], ['browse', 'Look inside'], ['reveal', 'Show in Explorer']], edit: 'Rename', del: 'Forget' },
      { kind: 'file', src: 'recent', cols: ['', 'invoice-0921.pdf', 'PDF', '1d', 'C:\\Downloads'], folder: 0, buttons: [['open', 'Open'], ['move', 'Move to…'], ['reveal', 'Show in folder']], menu: [['open', 'Open']], edit: 'Rename', del: 'Forget' }
    ],
    inbox: [
      { kind: 'file', src: 'inbox', cols: ['', 'clip_final_v3.mp4', 'MP4', '3m', '→ CLUK Content?   Downloads'], buttons: [['move', 'Move to…'], ['open', 'Open'], ['reveal', 'Show in folder']], menu: [['move', 'Move to…'], '-', ['quickrule', 'Always move .mp4 files to CLUK Content']], edit: 'Rename', del: 'Recycle' },
      { kind: 'file', src: 'inbox', cols: ['', 'thumbnail draft.png', 'PNG', '1h', 'Downloads'], buttons: [['move', 'Move to…']], menu: [], edit: 'Rename', del: 'Recycle' }
    ],
    layouts: [{ kind: 'item', cols: ['Ctrl+Alt+1', 'Writing', 'Layout', '3 windows', "chrome.exe 'Claude' → M1 right half"], buttons: [['open', 'Apply'], ['preview', 'Preview']], menu: [], edit: 'Edit', del: 'Remove' }],
    scripts: [{ kind: 'item', cols: ['', 'Razer macro keyboard', 'Script', '● Running', 'v1 · Razer_macro_keyboard.ahk'], buttons: [['keymap', 'Key map'], ['code', 'Edit code'], ['start', 'Reload']], menu: [], edit: 'Edit', del: 'Remove' }]
  };
  function rows(cat, q) {
    let r = (sample[cat] || []).slice();
    if (q) r = r.filter(x => x.cols.join(' ').toLowerCase().includes(q.toLowerCase()));
    if (!r.length) r = [{ kind: 'msg', cols: ['', q ? 'No matches' : 'Nothing here yet', '', '', ''] }];
    return { rows: r };
  }
  function load(name) {
    if (!store[name]) {
      let saved = null;
      try { saved = localStorage.getItem('alc-' + name); } catch {}
      store[name] = saved || (name === 'calendar'
        ? '{"version":1,"dayStart":660,"dayEnd":60,"view":"week","labels":[],"tasks":[]}'
        : '{"version":1,"lastTier":"B","tags":[],"cards":[]}');
    }
    return store[name];
  }
  function save(name, doc) { store[name] = doc; try { localStorage.setItem('alc-' + name, doc); } catch {} }
  window.__mockLog = [];
  return {
    receive(m, deliver) {
      window.__mockLog.push(m);
      let result = '';
      switch (m.cmd) {
        case 'hello': result = { version: 'mock', calendar: load('calendar'), ideas: load('ideas'), ideaHotkey: 'Ctrl+Shift+S' }; break;
        case 'rows': result = rows(m.cat, m.q); break;
        case 'act': result = m.action === 'browse' ? { browse: 'C:\\Videos\\CLUK Content' } : {}; break;
        case 'plan.save': save(m.name, m.doc); break;
        case 'idea.add': {
          const d = JSON.parse(load('ideas'));
          (m.newTags || []).forEach(t => { if (!d.tags.some(x => x.id === t.id)) d.tags.push(t); });
          d.cards.push({ id: 'i' + Date.now(), text: m.card.text, tier: m.card.tier, tags: m.card.tags, created: new Date().toISOString(), done: 0, archived: 0, order: Date.now() });
          d.lastTier = m.card.tier;
          save('ideas', JSON.stringify(d));
          deliver({ event: 'plan', value: { name: 'ideas', doc: JSON.stringify(d) } });
          break;
        }
      }
      if (m.id) deliver({ reply: m.id, result });
    }
  };
})();

// Clicking a button never steals keyboard focus from where you're typing.
document.addEventListener('mousedown', e => {
  if (e.target.closest('button, .stab, .gtab, .seg div, .chip, .tierpick div')) e.preventDefault();
});

// ---- small shared helpers --------------------------------------------------
const $ = (sel, el = document) => el.querySelector(sel);
const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v;
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(kid));
  return el;
};
const uid = () => Math.random().toString(36).slice(2, 10);
const COLORS = ['#7c6cf2', '#f06a6a', '#f5b544', '#4ade80', '#38bdf8', '#f472b6', '#fb923c', '#a3a3a3'];

function toast(text, kind = '') {
  const t = $('#toast');
  if (!t) return;
  t.textContent = text;
  t.className = 'on ' + kind;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.className = ''), kind === 'error' ? 4500 : 2200);
}

// Right-click style menu. items: [label, fn, cls?] or '-'
function menu(x, y, items) {
  closeMenu();
  const m = h('div', { class: 'menu', id: 'ctxmenu' });
  for (const it of items) {
    if (it === '-') { m.append(h('hr')); continue; }
    m.append(h('div', { class: it[2] || '', onmousedown: e => { e.preventDefault(); closeMenu(); it[1](); } }, it[0]));
  }
  document.body.append(m);
  const r = m.getBoundingClientRect();
  m.style.left = Math.min(x, innerWidth - r.width - 6) + 'px';
  m.style.top = Math.min(y, innerHeight - r.height - 6) + 'px';
  setTimeout(() => document.addEventListener('mousedown', closeMenu, { once: true }), 0);
}
function closeMenu() { const m = $('#ctxmenu'); if (m) m.remove(); }

// Modal dialog: build(body, close) fills it; returns the close function.
function modal(build, width) {
  const scrim = h('div', { class: 'scrim' });
  const box = h('div', { class: 'modal' });
  if (width) box.style.width = width + 'px';
  scrim.append(box);
  const close = () => { scrim.remove(); document.removeEventListener('keydown', onKey, true); };
  const onKey = e => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); close(); } };
  document.addEventListener('keydown', onKey, true);
  scrim.addEventListener('mousedown', e => { if (e.target === scrim) close(); });
  if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
  build(box, close);
  document.body.append(scrim);
  // focus right away, so the first keystrokes land in the dialog
  const f = box.querySelector('[autofocus]') || box.querySelector('input,textarea');
  if (f) f.focus();
  return close;
}
