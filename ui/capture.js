// The quick idea box (Ctrl+Shift+S). Enter saves, Shift+Enter = new line,
// Ctrl+1–4 picks S/A/B/C, Esc closes.
const TIERS = [['S', '#f87171'], ['A', '#fb923c'], ['B', '#facc15'], ['C', '#86efac']];
const Cap = {
  doc: { tags: [], lastTier: 'B' },
  tier: 'B',
  tags: [],        // selected tag ids
  newTags: [],     // created here, sent with the card

  open(docText) {
    try { Cap.doc = JSON.parse(docText); } catch { Cap.doc = { tags: [], lastTier: 'B' }; }
    Cap.doc.tags = Cap.doc.tags || [];
    Cap.tier = Cap.doc.lastTier || 'B';
    Cap.tags = [];
    Cap.newTags = [];
    $('#t').value = '';
    Cap.closePop();
    Cap.draw();
    setTimeout(() => $('#t').focus(), 0);
  },

  allTags() { return Cap.doc.tags.concat(Cap.newTags); },

  draw() {
    const tp = $('#tiers');
    tp.innerHTML = '';
    TIERS.forEach(([t, c]) => tp.append(h('div', { class: t === Cap.tier ? 'on' : '', style: t === Cap.tier ? `background:${c}` : '', onmousedown: e => { e.preventDefault(); Cap.tier = t; Cap.draw(); } }, t)));
    const ch = $('#chips');
    ch.innerHTML = '';
    Cap.tags.forEach(id => {
      const t = Cap.allTags().find(x => x.id === id);
      if (t) ch.append(h('span', { class: 'chip on', onmousedown: e => { e.preventDefault(); Cap.tags = Cap.tags.filter(x => x !== id); Cap.draw(); } }, h('i', { style: `background:${t.color}` }), t.name));
    });
  },

  save() {
    const text = $('#t').value.trim();
    if (!text) return;
    host.call('idea.add', { card: { text, tier: Cap.tier, tags: Cap.tags }, newTags: Cap.newTags });
    // ready for the next one (the box normally closes, but stay correct if not)
    Cap.doc.tags = Cap.doc.tags.concat(Cap.newTags);
    Cap.doc.lastTier = Cap.tier;
    Cap.newTags = [];
    Cap.tags = [];
    $('#t').value = '';
    Cap.draw();
  },

  // ---- tag picker ----
  openPop() {
    const pop = $('#tagpop'), add = $('#add').getBoundingClientRect();
    pop.classList.remove('hidden');
    pop.style.left = Math.max(8, Math.min(add.left - 160, innerWidth - 240)) + 'px';
    pop.style.top = '12px';
    $('#tq').value = '';
    Cap.drawPop();
    $('#tq').focus();
  },
  closePop() { $('#tagpop').classList.add('hidden'); },
  popOpen() { return !$('#tagpop').classList.contains('hidden'); },
  matches() {
    const q = $('#tq').value.trim().toLowerCase();
    return Cap.allTags().filter(t => !Cap.tags.includes(t.id) && t.name.toLowerCase().includes(q));
  },
  drawPop() {
    const list = $('#tlist');
    list.innerHTML = '';
    const q = $('#tq').value.trim();
    const m = Cap.matches();
    m.forEach((t, i) => list.append(h('div', { class: i === 0 ? 'on' : '', onmousedown: e => { e.preventDefault(); Cap.pick(t.id); } }, h('span', { class: 'chip', style: 'background:none;padding:0' }, h('i', { style: `background:${t.color}` }), t.name))));
    if (q && !Cap.allTags().some(t => t.name.toLowerCase() === q.toLowerCase()))
      list.append(h('div', { class: m.length ? '' : 'on', onmousedown: e => { e.preventDefault(); Cap.create(q); } }, `+ ${q}`));
  },
  pick(id) { Cap.tags.push(id); Cap.closePop(); Cap.draw(); $('#t').focus(); },
  create(name) {
    const all = Cap.allTags();
    const t = { id: uid(), name, color: COLORS[all.length % COLORS.length] };
    Cap.newTags.push(t);
    Cap.pick(t.id);
  }
};

host.on('open', doc => Cap.open(doc));
host.on('plan', p => { if (p.name === 'ideas') { try { const d = JSON.parse(p.doc); Cap.doc.tags = d.tags || []; } catch {} } });

document.addEventListener('keydown', e => {
  if (e.ctrlKey && ['1', '2', '3', '4'].includes(e.key)) { e.preventDefault(); Cap.tier = TIERS[+e.key - 1][0]; Cap.draw(); return; }
  if (Cap.popOpen()) {
    if (e.key === 'Escape') { e.preventDefault(); Cap.closePop(); $('#t').focus(); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      const m = Cap.matches(), q = $('#tq').value.trim();
      if (m.length) Cap.pick(m[0].id); else if (q) Cap.create(q);
    }
    return;
  }
  if (e.key === 'Escape') { e.preventDefault(); host.fire('capture.hide'); return; }
  if (e.key === 'Enter' && !e.shiftKey && e.target.id === 't') { e.preventDefault(); Cap.save(); return; }
});
document.addEventListener('input', e => { if (e.target.id === 'tq') Cap.drawPop(); });
document.addEventListener('contextmenu', e => e.preventDefault());
$('#add').addEventListener('mousedown', e => { e.preventDefault(); Cap.popOpen() ? Cap.closePop() : Cap.openPop(); });

host.call('hello').then(r => { if (!host.live) Cap.open(r.ideas); });
