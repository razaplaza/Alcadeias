// Shell: group tabs (Work / Setup / Plan), sub-tabs, and the list views.
const GROUPS = [
  { id: 'work', name: 'Work', tabs: [['find', 'Find'], ['inbox', 'Inbox'], ['projects', 'Projects'], ['paste', 'Paste']] },
  { id: 'setup', name: 'Setup', tabs: [['layouts', 'Layouts'], ['scripts', 'Scripts'], ['shortcuts', 'Apps & links']] },
  { id: 'plan', name: 'Plan', tabs: [['calendar', 'Calendar'], ['ideas', 'Ideas']] }
];

const App = {
  group: 'work',
  tab: { work: 'find', setup: 'layouts', plan: 'calendar' },
  view: null,
  views: {},
  plan: { calendar: null, ideas: null },

  async start() {
    const init = await host.call('hello');
    App.plan.calendar = JSON.parse(init.calendar);
    App.plan.ideas = JSON.parse(init.ideas);
    App.renderGroups();
    App.show(App.group);
    host.on('refresh', () => App.view && App.view.refresh && App.view.refresh());
    host.on('status', s => toast(s.text, s.kind));
    host.on('tab', t => App.goTab(t));
    host.on('shown', t => { if (t) App.goTab(t); App.view && App.view.focus && App.view.focus(); App.view && App.view.refresh && App.view.refresh(); });
    host.on('plan', p => {
      App.plan[p.name] = JSON.parse(p.doc);
      const v = App.views[p.name];
      if (v && App.view === v) v.refresh();
    });
    document.addEventListener('keydown', App.onKey);
    document.addEventListener('contextmenu', e => e.preventDefault());
    $('#btnSettings').onclick = () => host.fire('settings');
  },

  savePlan(name) { host.fire('plan.save', { name, doc: JSON.stringify(App.plan[name]) }); },

  renderGroups() {
    const g = $('#groups');
    g.innerHTML = '';
    for (const grp of GROUPS)
      g.append(h('div', { class: 'gtab' + (grp.id === App.group ? ' on' : ''), onclick: () => App.show(grp.id) }, grp.name));
  },

  show(groupId, tabId) {
    App.group = groupId;
    if (tabId) App.tab[groupId] = tabId;
    App.renderGroups();
    const grp = GROUPS.find(x => x.id === groupId);
    const st = $('#subtabs');
    st.innerHTML = '';
    for (const [id, name] of grp.tabs)
      st.append(h('div', { class: 'stab' + (id === App.tab[groupId] ? ' on' : ''), onclick: () => App.show(groupId, id) }, name));
    App.mount(App.tab[groupId]);
  },

  goTab(id) {
    if (id === 'all' || id === 'files') id = 'find';
    const grp = GROUPS.find(g => g.tabs.some(t => t[0] === id));
    if (grp) App.show(grp.id, id);
  },

  mount(id) {
    if (App.view && App.view.unmount) App.view.unmount();
    const view = $('#view'), tools = $('#tools');
    view.innerHTML = '';
    tools.innerHTML = '';
    if (!App.views[id])
      App.views[id] = id === 'calendar' ? new CalendarView() : id === 'ideas' ? new IdeasView() : new ListView(id);
    App.view = App.views[id];
    App.view.mount(view, tools);
  },

  onKey(e) {
    if (document.querySelector('.scrim')) return;   // a dialog handles its own keys
    if (e.ctrlKey && !e.altKey && ['1', '2', '3'].includes(e.key)) {
      e.preventDefault();
      App.show(GROUPS[+e.key - 1].id);
      return;
    }
    if (e.ctrlKey && e.key === 'Tab') {
      e.preventDefault();
      const grp = GROUPS.find(g => g.id === App.group);
      const i = grp.tabs.findIndex(t => t[0] === App.tab[App.group]);
      const n = (i + (e.shiftKey ? -1 : 1) + grp.tabs.length) % grp.tabs.length;
      App.show(App.group, grp.tabs[n][0]);
      return;
    }
    if (App.view && App.view.key) App.view.key(e);
  }
};

// ---- list view (Find, Inbox, Projects, Paste, Layouts, Scripts, Apps) ----
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

class ListView {
  constructor(cat) {
    this.cat = cat;
    this.q = '';
    this.browse = '';
    this.rows = [];
    this.sel = new Set();
    this.cur = 0;
    this.seq = 0;
  }

  mount(view) {
    this.el = h('div', { class: 'list' });
    this.input = h('input', { type: 'search', placeholder: 'Search', spellcheck: 'false' });
    this.input.value = this.q;
    this.input.addEventListener('input', () => { this.q = this.input.value; this.load(true); });
    this.crumb = h('div', { class: 'crumb' });
    this.body = h('div', { class: 'tbody' });
    this.body.addEventListener('mousedown', e => this.onMouse(e));
    this.body.addEventListener('dblclick', e => { if (e.target.closest('.tr')) this.act('open'); });
    this.body.addEventListener('contextmenu', e => this.onContext(e));
    this.bar = h('div', { class: 'actions' });
    this.el.append(
      h('div', { class: 'search' }, this.input, this.crumb),
      h('div', { class: 'table' },
        h('div', { class: 'thead' }, h('div', {}, 'Key'), h('div', {}, 'Name'), h('div', {}, 'Type'), h('div', {}, 'Status'), h('div', {}, 'Details')),
        this.body),
      this.bar);
    view.append(this.el);
    this.renderCrumb();
    this.load(false);
    this.focus();
  }

  focus() { setTimeout(() => this.input && this.input.focus(), 0); }
  refresh() { this.load(false); }

  async load(resetSel) {
    const n = ++this.seq;
    const res = await host.call('rows', { cat: this.cat, q: this.q, browse: this.browse });
    if (n !== this.seq || !res) return;
    const keep = !resetSel && this.rows.length ? this.rowKey(this.rows[this.cur]) : null;
    this.rows = res.rows || [];
    let idx = 0;
    if (keep) { const j = this.rows.findIndex(r => this.rowKey(r) === keep); if (j >= 0) idx = j; }
    if (this._afterLoadSelect) {
      const name = this._afterLoadSelect.split('\\').pop().toLowerCase();
      const j = this.rows.findIndex(r => String(r.cols[1]).toLowerCase() === name);
      if (j >= 0) idx = j;
      this._afterLoadSelect = null;
    }
    if (this.rows[idx] && this.rows[idx].kind === 'msg') idx = -1;
    this.cur = Math.max(0, idx);
    this.sel = new Set(idx >= 0 && this.rows.length ? [idx] : []);
    this.render();
  }

  rowKey(r) { return r ? r.cols[1] + '|' + r.cols[4] : null; }

  render() {
    let html = '';
    this.rows.forEach((r, i) => {
      const c = r.cols;
      html += `<div class="tr${this.sel.has(i) ? ' sel' : ''}${r.kind === 'msg' ? ' msg' : ''}" data-i="${i}">` +
        `<div class="c0">${esc(c[0])}</div><div class="c1">${esc(c[1])}</div><div class="c2">${esc(c[2])}</div>` +
        `<div class="c3">${esc(c[3])}</div><div class="c4" title="${esc(c[4])}">${esc(c[4])}</div></div>`;
    });
    this.body.innerHTML = html;
    this.renderBar();
  }

  renderBar() {
    const r = this.rows[this.cur];
    const has = r && this.sel.has(this.cur) && r.kind !== 'msg';
    this.bar.innerHTML = '';
    const isInbox = this.cat === 'inbox' && !this.browse;
    this.bar.append(h('button', { class: 'accent', title: isInbox ? 'Auto-sort rules' : 'New', onclick: () => this.newItem() }, isInbox ? 'Auto-sort' : '+'));
    if (has && r.edit) this.bar.append(h('button', { onclick: () => this.act('edit') }, r.edit));
    if (has && r.del) this.bar.append(h('button', { class: 'danger', onclick: () => this.act('delete') }, r.del));
    this.bar.append(h('div', { class: 'grow' }));
    if (has) {
      const b = r.buttons || [];
      // main action on the far right
      for (let i = b.length - 1; i >= 0; i--)
        this.bar.append(h('button', { class: i === 0 ? 'accent' : '', onclick: () => this.act(b[i][0]) }, b[i][1]));
    }
  }

  renderCrumb() {
    this.crumb.innerHTML = '';
    if (!this.browse) return;
    const parts = this.browse.replace(/\\$/, '').split('\\');
    let acc = '';
    parts.forEach((p, i) => {
      acc += (i ? '\\' : '') + p;
      const path = i === 0 ? acc + '\\' : acc;
      if (i) this.crumb.append('›');
      this.crumb.append(h('span', { onclick: () => this.go(path) }, p));
    });
  }

  go(path) {
    this.browse = path;
    this.q = '';
    this.input.value = '';
    this.renderCrumb();
    this.load(true);
    this.focus();
  }

  up() {
    const p = this.browse.replace(/\\$/, '');
    const i = p.lastIndexOf('\\');
    if (i < 0) return this.go('');
    const parent = p.slice(0, i);
    this._afterLoadSelect = p;
    this.go(parent.length === 2 ? parent + '\\' : parent);
  }

  selected() { return [...this.sel].sort((a, b) => a - b).filter(i => this.rows[i] && this.rows[i].kind !== 'msg'); }

  async act(action) {
    const idx = this.selected();
    if (!idx.length) return;
    const res = await host.call('act', { cat: this.cat, browse: this.browse, action, rows: idx.map(i => i + 1) });
    if (res && res.browse) this.go(res.browse);
    else this.load(false);
  }

  newItem() { host.fire('new', { cat: this.cat, browse: this.browse }); }

  setCur(i, extend) {
    const n = this.rows.length;
    if (!n) return;
    i = Math.max(0, Math.min(n - 1, i));
    if (extend) this.sel.add(i); else this.sel = new Set([i]);
    this.cur = i;
    this.render();
    const el = this.body.querySelector(`[data-i="${i}"]`);
    if (el) el.scrollIntoView({ block: 'nearest' });
  }

  onMouse(e) {
    const tr = e.target.closest('.tr');
    if (!tr) return;
    const i = +tr.dataset.i;
    if (e.button === 2 && this.sel.has(i)) return;
    if (e.ctrlKey) { this.sel.has(i) ? this.sel.delete(i) : this.sel.add(i); this.cur = i; this.render(); }
    else if (e.shiftKey) { const [a, b] = [Math.min(this.cur, i), Math.max(this.cur, i)]; for (let k = a; k <= b; k++) this.sel.add(k); this.cur = i; this.render(); }
    else this.setCur(i);
  }

  onContext(e) {
    e.preventDefault();
    const tr = e.target.closest('.tr');
    if (!tr) return;
    const i = +tr.dataset.i;
    if (!this.sel.has(i)) this.setCur(i);
    const r = this.rows[i];
    if (!r || !r.menu || !r.menu.length) return;
    menu(e.clientX, e.clientY, r.menu.map(m => m === '-' ? '-' : [m[1], () => this.act(m[0]), m[0] === 'delete' || m[0] === 'clearclips' ? 'danger' : '']));
  }

  key(e) {
    const inSearch = document.activeElement === this.input;
    const k = e.key;
    const r = this.rows[this.cur];
    if (k === 'ArrowDown' || k === 'ArrowUp') { e.preventDefault(); this.setCur(this.cur + (k === 'ArrowDown' ? 1 : -1), e.shiftKey); return; }
    if (k === 'PageDown' || k === 'PageUp') { e.preventDefault(); this.setCur(this.cur + (k === 'PageDown' ? 10 : -10)); return; }
    if (k === 'Enter') { e.preventDefault(); this.act('open'); return; }
    if (k === 'Tab' && !e.ctrlKey) { e.preventDefault(); if (r && r.folder) this.act('browse'); return; }
    if (k === 'Backspace' && this.q === '' && this.browse) { e.preventDefault(); this.up(); return; }
    if (k === 'Escape') {
      e.preventDefault();
      if (this.q) { this.q = ''; this.input.value = ''; this.load(true); }
      else if (this.browse) this.go('');
      else host.fire('hide');
      return;
    }
    if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'm') { e.preventDefault(); this.act('move'); return; }
    if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'n') { e.preventDefault(); this.newItem(); return; }
    if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'r') { e.preventDefault(); this.act('reveal'); return; }
    if (e.ctrlKey && e.shiftKey && k.toLowerCase() === 'c') { e.preventDefault(); this.act('copypath'); return; }
    if (e.ctrlKey && !e.shiftKey && k.toLowerCase() === 'z' && !(inSearch && this.q)) { e.preventDefault(); host.call('undo').then(() => this.load(false)); return; }
    if (k === 'F2' || (e.ctrlKey && k.toLowerCase() === 'e')) { e.preventDefault(); this.act('edit'); return; }
    if (k === 'Delete' && !(inSearch && this.q)) { e.preventDefault(); this.act('delete'); return; }
    if (!inSearch && k.length === 1 && !e.ctrlKey && !e.altKey) this.input.focus();
  }
}

window.addEventListener('DOMContentLoaded', () => App.start());
