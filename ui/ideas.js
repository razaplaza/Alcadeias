// Idea cards in an S / A / B / C tier list.
const TIERS = [['S', '#f87171'], ['A', '#fb923c'], ['B', '#facc15'], ['C', '#86efac']];
const tierColor = t => (TIERS.find(x => x[0] === t) || TIERS[2])[1];

const Ideas = {
  doc: () => App.plan.ideas,
  save() { App.savePlan('ideas'); },
  tag(id) { return (Ideas.doc().tags || []).find(t => t.id === id); },
  newTag(name) {
    const d = Ideas.doc();
    d.tags = d.tags || [];
    const t = { id: uid(), name, color: COLORS[d.tags.length % COLORS.length] };
    d.tags.push(t);
    return t;
  }
};

class IdeasView {
  constructor() { this.q = ''; this.filter = new Set(); this.showArchived = false; }

  mount(view, tools) {
    this.root = view;
    this.tools = tools;
    this.renderTools();
    this.render();
  }

  refresh() { this.renderTools(); this.render(); }
  focus() {}

  renderTools() {
    const t = this.tools;
    t.innerHTML = '';
    const d = Ideas.doc();
    const input = h('input', { type: 'search', placeholder: 'Search', style: 'width:180px', value: this.q });
    input.addEventListener('input', () => { this.q = input.value; this.render(); });
    const chips = h('div', { class: 'chips' });
    for (const tag of d.tags || []) {
      const c = h('span', { class: 'chip' + (this.filter.has(tag.id) ? ' on' : ''),
        onclick: () => { this.filter.has(tag.id) ? this.filter.delete(tag.id) : this.filter.add(tag.id); this.renderTools(); this.render(); } },
        h('i', { style: `background:${tag.color}` }), tag.name);
      c.addEventListener('contextmenu', e => { e.preventDefault(); this.tagMenu(e, tag); });
      chips.append(c);
    }
    chips.append(h('span', { class: 'chip add', title: 'New tag', onclick: () => this.addTag() }, '+'));
    t.append(chips, input,
      h('button', { class: 'icon', title: 'Archived', style: this.showArchived ? 'background:var(--panel2)' : '', onclick: () => { this.showArchived = !this.showArchived; this.renderTools(); this.render(); } },
        svg('M3 4h18v4H3zM5 8v12h14V8M10 12h4')),
      h('button', { class: 'accent', onclick: () => this.edit({ id: uid(), text: '', tier: d.lastTier || 'B', tags: [], done: 0, archived: 0, order: Date.now() }, true) }, '+'));
  }

  visible(c) {
    if (!!c.archived !== this.showArchived) return false;
    if (this.filter.size && !(c.tags || []).some(t => this.filter.has(t))) return false;
    if (this.q) {
      const hay = (c.text + ' ' + (c.tags || []).map(id => (Ideas.tag(id) || {}).name || '').join(' ')).toLowerCase();
      if (!this.q.toLowerCase().split(/\s+/).every(w => hay.includes(w))) return false;
    }
    return true;
  }

  render() {
    const d = Ideas.doc();
    d.cards = d.cards || [];
    this.root.innerHTML = '';
    const wrap = h('div', { class: 'tiers' });
    for (const [tier, color] of TIERS) {
      const cards = d.cards.filter(c => c.tier === tier && this.visible(c))
        .sort((a, b) => (+a.done - +b.done) || (+a.order - +b.order));
      const box = h('div', { class: 'cards', 'data-tier': tier });
      cards.forEach(c => box.append(this.cardEl(c)));
      const row = h('div', { class: 'tier' }, h('div', { class: 'tl', style: `background:${color}` }, tier), box);
      this.dropZone(row, box, tier);
      wrap.append(row);
    }
    this.root.append(wrap);
  }

  cardEl(c) {
    const meta = h('div', { class: 'meta' });
    (c.tags || []).forEach(id => { const t = Ideas.tag(id); if (t) meta.append(h('i', { style: `--c:${t.color}` }, t.name)); });
    const el = h('div', { class: 'card' + (c.done ? ' done' : ''), draggable: 'true', 'data-id': c.id },
      h('p', {}, c.text), meta.childNodes.length ? meta : null);
    el.addEventListener('click', () => this.edit(c, false));
    el.addEventListener('contextmenu', e => { e.preventDefault(); e.stopPropagation(); this.cardMenu(e, c); });
    el.addEventListener('dragstart', e => { e.dataTransfer.setData('text/plain', c.id); e.dataTransfer.effectAllowed = 'move'; setTimeout(() => el.classList.add('dragging'), 0); });
    el.addEventListener('dragend', () => { el.classList.remove('dragging'); this.clearMarks(); });
    return el;
  }

  clearMarks() {
    this.root.querySelectorAll('.drop-mark').forEach(m => m.remove());
    this.root.querySelectorAll('.tier.over').forEach(t => t.classList.remove('over'));
  }

  // where in a row the dragged card would land
  insertIndex(box, x, y) {
    const cards = [...box.querySelectorAll('.card:not(.dragging)')];
    for (let i = 0; i < cards.length; i++) {
      const r = cards[i].getBoundingClientRect();
      if (y < r.top) return i;
      if (y <= r.bottom && x < r.left + r.width / 2) return i;
    }
    return cards.length;
  }

  dropZone(row, box, tier) {
    row.addEventListener('dragover', e => {
      e.preventDefault();
      this.clearMarks();
      row.classList.add('over');
      const i = this.insertIndex(box, e.clientX, e.clientY);
      const cards = [...box.querySelectorAll('.card:not(.dragging)')];
      const mark = h('div', { class: 'drop-mark' });
      cards[i] ? box.insertBefore(mark, cards[i]) : box.append(mark);
    });
    row.addEventListener('dragleave', e => { if (!row.contains(e.relatedTarget)) this.clearMarks(); });
    row.addEventListener('drop', e => {
      e.preventDefault();
      const id = e.dataTransfer.getData('text/plain');
      const d = Ideas.doc();
      const card = d.cards.find(c => c.id === id);
      if (!card) return;
      const i = this.insertIndex(box, e.clientX, e.clientY);
      const others = d.cards.filter(c => c.tier === tier && c.id !== id && this.visible(c)).sort((a, b) => (+a.done - +b.done) || (+a.order - +b.order));
      others.splice(i, 0, card);
      card.tier = tier;
      others.forEach((c, k) => (c.order = k + 1));
      Ideas.save();
      this.clearMarks();
      this.render();
    });
  }

  cardMenu(e, c) {
    menu(e.clientX, e.clientY, [
      [c.done ? 'Not done' : 'Done', () => { c.done = c.done ? 0 : 1; Ideas.save(); this.render(); }],
      [c.archived ? 'Unarchive' : 'Archive', () => { c.archived = c.archived ? 0 : 1; Ideas.save(); this.render(); }],
      ['Schedule', () => this.schedule(c)],
      '-',
      ['Delete', () => this.remove(c), 'danger']]);
  }

  remove(c) {
    const d = Ideas.doc();
    d.cards = d.cards.filter(x => x.id !== c.id);
    Ideas.save();
    this.render();
  }

  // Idea -> calendar task (first line = title, rest = description)
  schedule(c) {
    const lines = String(c.text).split('\n');
    const now = Cal.now();
    const { s, e } = Cal.span();
    const start = Math.max(s, Math.min(e - 60, Math.ceil((now.mins + 1) / 60) * 60));
    taskModal({ id: uid(), title: lines[0].slice(0, 120), desc: lines.slice(1).join('\n'), date: ymd(now.date), start, end: start + 60, label: '' }, true,
      () => toast('Added to the calendar'));
  }

  tagMenu(e, tag) {
    menu(e.clientX, e.clientY, [
      ['Rename', () => this.renameTag(tag)],
      ['Delete', () => {
        const d = Ideas.doc();
        d.tags = d.tags.filter(t => t.id !== tag.id);
        d.cards.forEach(c => (c.tags = (c.tags || []).filter(t => t !== tag.id)));
        this.filter.delete(tag.id);
        Ideas.save(); this.refresh();
      }, 'danger']]);
  }

  addTag() { this.tagDialog(null); }
  renameTag(tag) { this.tagDialog(tag); }

  tagDialog(tag) {
    modal((box, close) => {
      let color = tag ? tag.color : COLORS[(Ideas.doc().tags || []).length % COLORS.length];
      const name = h('input', { type: 'text', value: tag ? tag.name : '', placeholder: 'Tag', autofocus: true });
      const sw = h('div', { class: 'swatches' });
      const draw = () => { sw.innerHTML = ''; COLORS.forEach(c => sw.append(h('span', { class: c === color ? 'on' : '', style: `background:${c}`, onclick: () => { color = c; draw(); } }))); };
      draw();
      const save = () => {
        const n = name.value.trim();
        if (!n) return;
        if (tag) { tag.name = n; tag.color = color; } else Ideas.newTag(n).color = color;
        Ideas.save(); close(); this.refresh();
      };
      name.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); save(); } });
      box.append(h('h3', {}, tag ? 'Edit tag' : 'New tag'), name, sw,
        h('div', { class: 'buttons' }, h('button', { onclick: close }, 'Cancel'), h('button', { class: 'accent', onclick: save }, 'Save')));
    }, 360);
  }

  edit(c, isNew) {
    const d = Ideas.doc();
    let tier = c.tier || 'B';
    const tags = new Set(c.tags || []);
    modal((box, close) => {
      const text = h('textarea', { rows: 5, placeholder: 'Idea', autofocus: true }, c.text || '');
      const pick = h('div', { class: 'tierpick' });
      const drawPick = () => {
        pick.innerHTML = '';
        TIERS.forEach(([t, col]) => pick.append(h('div', { class: t === tier ? 'on' : '', style: t === tier ? `background:${col}` : '', onclick: () => { tier = t; drawPick(); } }, t)));
      };
      drawPick();
      const chips = h('div', { class: 'chips' });
      const drawChips = () => {
        chips.innerHTML = '';
        (d.tags || []).forEach(t => chips.append(h('span', { class: 'chip' + (tags.has(t.id) ? ' on' : ''), onclick: () => { tags.has(t.id) ? tags.delete(t.id) : tags.add(t.id); drawChips(); } }, h('i', { style: `background:${t.color}` }), t.name)));
      };
      drawChips();
      const save = () => {
        const v = text.value.trim();
        if (!v) { text.focus(); return; }
        Object.assign(c, { text: v, tier, tags: [...tags] });
        if (isNew) { d.cards = d.cards || []; d.cards.push({ ...c, created: new Date().toISOString() }); d.lastTier = tier; }
        Ideas.save(); close(); this.render();
      };
      text.addEventListener('keydown', e => {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); save(); }
        if (e.ctrlKey && ['1', '2', '3', '4'].includes(e.key)) { e.preventDefault(); tier = TIERS[+e.key - 1][0]; drawPick(); }
      });
      const small = (label, fn, cls = '') => h('button', { class: cls, onclick: () => { fn(); close(); this.render(); } }, label);
      box.append(text, h('div', { class: 'row' }, pick, chips),
        h('div', { class: 'buttons' },
          isNew ? null : small('Delete', () => { d.cards = d.cards.filter(x => x.id !== c.id); Ideas.save(); }, 'danger left'),
          isNew ? null : small(c.done ? 'Not done' : 'Done', () => { c.done = c.done ? 0 : 1; Ideas.save(); }),
          isNew ? null : small(c.archived ? 'Unarchive' : 'Archive', () => { c.archived = c.archived ? 0 : 1; Ideas.save(); }),
          isNew ? null : h('button', { onclick: () => { close(); this.schedule(c); } }, 'Schedule'),
          h('button', { class: 'accent', onclick: save }, 'Save')));
    }, 520);
  }

  key(e) {
    if (e.target.matches('input,textarea,select')) return;
    if (e.key === 'Escape') host.fire('hide');
    if (e.key === '+' || (e.ctrlKey && e.key.toLowerCase() === 'n')) {
      e.preventDefault();
      this.edit({ id: uid(), text: '', tier: Ideas.doc().lastTier || 'B', tags: [], done: 0, archived: 0, order: Date.now() }, true);
    }
  }
}
