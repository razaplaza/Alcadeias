// Calendar: Month / Week (Mon–Sun) / Today. A "day" runs from dayStart to
// dayEnd and may pass midnight (11:00 → 01:00): a task at 00:30 belongs to the
// day that started the evening before. Times are minutes from that day's
// 00:00 and can exceed 1440.
const pad2 = n => String(n).padStart(2, '0');
const ymd = d => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const parseYmd = s => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const mondayOf = d => addDays(new Date(d.getFullYear(), d.getMonth(), d.getDate()), -((d.getDay() + 6) % 7));
const hhmm = m => `${pad2(Math.floor(m / 60) % 24)}:${pad2(m % 60)}`;
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const Cal = {
  doc: () => App.plan.calendar,
  span() {
    const d = Cal.doc();
    const s = +d.dayStart, e0 = +d.dayEnd;
    return { s, e: e0 <= s ? e0 + 1440 : e0 };
  },
  // planner "now": before dayEnd past midnight still counts as yesterday
  now() {
    const t = new Date();
    let mins = t.getHours() * 60 + t.getMinutes();
    let date = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    const { s, e } = Cal.span();
    if (e > 1440 && mins < e - 1440 && mins < s) { date = addDays(date, -1); mins += 1440; }
    return { date, mins };
  },
  // time-input value -> planner minutes
  fromInput(v) {
    if (!v) return null;
    const [hh, mm] = v.split(':').map(Number);
    let m = hh * 60 + mm;
    const { s, e } = Cal.span();
    if (e > 1440 && m < s && m + 1440 <= e) m += 1440;
    return m;
  },
  label(id) { return (Cal.doc().labels || []).find(l => l.id === id); },
  color(t) { const l = Cal.label(t.label); return l ? l.color : '#7c6cf2'; },
  save() { App.savePlan('calendar'); }
};

class CalendarView {
  constructor() {
    const d = Cal.doc();
    this.view = d.view === 'month' || d.view === 'day' ? d.view : 'week';
    this.anchor = Cal.now().date;
    this.follow = true;          // keep showing the current period
    this.timer = null;
  }

  mount(view, tools) {
    this.root = view;
    this.tools = tools;
    this.renderTools();
    this.render();
    this.timer = setInterval(() => this.tick(), 30000);
    this.ro = new ResizeObserver(() => this.render());
    this.ro.observe(view);
  }

  unmount() { clearInterval(this.timer); if (this.ro) this.ro.disconnect(); }
  refresh() { this.render(); }
  focus() {}

  tick() {
    if (this.follow) {
      const now = Cal.now().date;
      if (ymd(now) !== ymd(this.anchor)) this.anchor = now;
    }
    this.render(true);
  }

  setView(v) {
    this.view = v;
    Cal.doc().view = v;
    Cal.save();
    this.anchor = Cal.now().date;
    this.follow = true;
    this.renderTools();
    this.render();
  }

  move(dir) {
    const a = this.anchor;
    this.anchor = this.view === 'month' ? new Date(a.getFullYear(), a.getMonth() + dir, 1)
      : addDays(a, this.view === 'week' ? 7 * dir : dir);
    this.follow = false;
    this.render();
  }

  goNow() { this.anchor = Cal.now().date; this.follow = true; this.render(); }

  renderTools() {
    const t = this.tools;
    t.innerHTML = '';
    this.titleEl = h('div', { class: 'cal-title', onclick: () => this.goNow() });
    const seg = h('div', { class: 'seg' },
      ...[['month', 'Month'], ['week', 'Week'], ['day', 'Today']].map(([v, n]) =>
        h('div', { class: v === this.view ? 'on' : '', onclick: () => this.setView(v) }, n)));
    t.append(
      h('button', { class: 'icon', onclick: () => this.move(-1) }, svg('M15 18l-6-6 6-6')),
      this.titleEl,
      h('button', { class: 'icon', onclick: () => this.move(1) }, svg('M9 18l6-6-6-6')),
      seg,
      h('button', { class: 'accent', onclick: () => this.newTask() }, '+'),
      h('button', { class: 'icon', onclick: e => this.settings(e) }, svg('M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z')));
  }

  days() {
    if (this.view === 'day') return [this.anchor];
    const m = mondayOf(this.anchor);
    return DAYS.map((_, i) => addDays(m, i));
  }

  title() {
    const a = this.anchor;
    if (this.view === 'month') return `${MONTHS[a.getMonth()]} ${a.getFullYear()}`;
    if (this.view === 'day') return `${DAYS[(a.getDay() + 6) % 7]} ${a.getDate()} ${MONTHS[a.getMonth()].slice(0, 3)}`;
    const d = this.days(), f = d[0], l = d[6];
    return f.getMonth() === l.getMonth() ? `${MONTHS[f.getMonth()].slice(0, 3)} ${f.getDate()} – ${l.getDate()}`
      : `${MONTHS[f.getMonth()].slice(0, 3)} ${f.getDate()} – ${MONTHS[l.getMonth()].slice(0, 3)} ${l.getDate()}`;
  }

  render(soft) {
    if (!this.root) return;
    if (this.titleEl) this.titleEl.textContent = this.title();
    const keepScroll = soft && this.bodyEl ? this.bodyEl.scrollTop : null;
    this.root.innerHTML = '';
    if (this.view === 'month') this.renderMonth();
    else this.renderGrid(keepScroll);
  }

  tasksOn(dateStr) {
    return (Cal.doc().tasks || []).filter(t => t.date === dateStr).sort((a, b) => a.start - b.start);
  }

  // ---- week / day ----------------------------------------------------
  renderGrid(keepScroll) {
    const { s, e } = Cal.span();
    const days = this.days();
    const hours = Math.ceil((e - s) / 60);
    const cal = h('div', { class: 'cal' });
    this.root.append(cal);
    const headH = 36;
    const avail = this.root.clientHeight - headH - 2;
    const hourH = Math.max(40, Math.floor(avail / hours));
    this.hourH = hourH;
    const cols = `56px repeat(${days.length}, 1fr)`;
    const now = Cal.now();
    const todayStr = ymd(now.date);

    const head = h('div', { class: 'cal-head', style: `grid-template-columns:${cols}` }, h('div'));
    days.forEach(d => {
      const isToday = ymd(d) === todayStr;
      head.append(h('div', { class: isToday ? 'today' : '' }, DAYS[(d.getDay() + 6) % 7], h('b', {}, d.getDate())));
    });

    const body = h('div', { class: 'cal-body' });
    this.bodyEl = body;
    const grid = h('div', { class: 'cal-grid', style: `grid-template-columns:${cols};--hour:${hourH}px;height:${hours * hourH}px` });
    const gutter = h('div', { class: 'cal-hours' });
    for (let k = 0; k < hours; k++) gutter.append(h('div', {}, hhmm(s + k * 60)));
    grid.append(gutter);
    this.dayCols = [];
    days.forEach(d => {
      const ds = ymd(d);
      const col = h('div', { class: 'cal-day' + (ds === todayStr ? ' today' : ''), 'data-date': ds });
      this.layout(this.tasksOn(ds)).forEach(({ t, c, n }) => col.append(this.taskEl(t, c, n, s, hourH)));
      if (ds === todayStr && now.mins >= s && now.mins <= e)
        col.append(h('div', { class: 'now', style: `top:${(now.mins - s) / 60 * hourH}px` }));
      grid.append(col);
      this.dayCols.push(col);
    });
    body.append(grid);
    cal.append(head, body);

    if (keepScroll != null) body.scrollTop = keepScroll;
    else if (hours * hourH > body.clientHeight && now.mins >= s && now.mins <= e)
      body.scrollTop = Math.max(0, (now.mins - s) / 60 * hourH - body.clientHeight / 3);
  }

  // side-by-side columns for overlapping tasks
  layout(tasks) {
    const out = [];
    let cluster = [], clusterEnd = -1;
    const flush = () => {
      const colsEnd = [];
      const placed = cluster.map(t => {
        let c = colsEnd.findIndex(end => end <= t.start);
        if (c < 0) { c = colsEnd.length; colsEnd.push(0); }
        colsEnd[c] = this.end(t);
        return { t, c };
      });
      placed.forEach(p => out.push({ ...p, n: colsEnd.length }));
      cluster = [];
      clusterEnd = -1;
    };
    for (const t of tasks) {
      if (cluster.length && t.start >= clusterEnd) flush();
      cluster.push(t);
      clusterEnd = Math.max(clusterEnd, this.end(t));
    }
    if (cluster.length) flush();
    return out;
  }

  end(t) { return t.end != null && t.end !== '' && +t.end > +t.start ? +t.end : +t.start + 25; }

  taskEl(t, c, n, s, hourH) {
    const top = (t.start - s) / 60 * hourH;
    const hasEnd = t.end != null && t.end !== '' && +t.end > +t.start;
    const height = hasEnd ? Math.max(18, (t.end - t.start) / 60 * hourH) : 22;
    const w = 100 / n;
    const el = h('div', {
      class: 'task', 'data-id': t.id,
      style: `top:${top}px;height:${height - 2}px;left:calc(${c * w}% + 3px);width:calc(${w}% - 6px);right:auto;--c:${Cal.color(t)}`
    }, h('b', {}, t.title || '(untitled)'));
    if (height >= 36) el.append(h('span', {}, hhmm(t.start) + (hasEnd ? '–' + hhmm(t.end) : '')));
    if (hasEnd) el.append(h('div', { class: 'grip' }));
    el.addEventListener('pointerdown', ev => this.pointer(ev, t, el));
    el.addEventListener('contextmenu', ev => { ev.preventDefault(); ev.stopPropagation(); this.taskMenu(ev, t); });
    return el;
  }

  // Ctrl+drag moves a task; Ctrl+drag on its bottom edge changes the end.
  pointer(ev, t, el) {
    if (ev.button !== 0) return;
    if (!ev.ctrlKey) { el.onclick = () => this.edit(t); return; }
    ev.preventDefault();
    el.onclick = null;
    const resize = ev.target.classList.contains('grip');
    const y0 = ev.clientY, start0 = +t.start, end0 = t.end != null && t.end !== '' ? +t.end : null, date0 = t.date;
    const snap = m => Math.round(m / 5) * 5;
    const { s, e } = Cal.span();
    let moved = false;
    el.setPointerCapture(ev.pointerId);
    el.classList.add('drag');
    const onMove = mv => {
      const dm = snap((mv.clientY - y0) / this.hourH * 60);
      if (dm !== 0) moved = true;
      if (resize) {
        t.end = Math.max(start0 + 5, Math.min(e, end0 + dm));
      } else {
        const len = end0 != null ? end0 - start0 : 0;
        let ns = Math.max(s, Math.min(e - Math.max(len, 5), start0 + dm));
        t.start = ns;
        if (end0 != null) t.end = ns + len;
        const col = this.dayCols.find(cl => { const r = cl.getBoundingClientRect(); return mv.clientX >= r.left && mv.clientX < r.right; });
        if (col && col.dataset.date !== t.date) { t.date = col.dataset.date; moved = true; }
      }
      this.renderLive(t);
    };
    const onUp = () => {
      el.removeEventListener('pointermove', onMove);
      el.removeEventListener('pointerup', onUp);
      if (moved) Cal.save();
      else { t.start = start0; t.end = end0; t.date = date0; }
      this.render(true);
    };
    el.addEventListener('pointermove', onMove);
    el.addEventListener('pointerup', onUp);
  }

  // cheap re-render while dragging: move the one block
  renderLive(t) {
    const { s } = Cal.span();
    const el = this.root.querySelector(`.task[data-id="${t.id}"]`);
    const col = this.dayCols.find(c => c.dataset.date === t.date);
    if (!el || !col) return;
    if (el.parentElement !== col) col.append(el);
    el.style.top = (t.start - s) / 60 * this.hourH + 'px';
    if (t.end != null && t.end !== '') el.style.height = Math.max(18, (t.end - t.start) / 60 * this.hourH) - 2 + 'px';
    const span = el.querySelector('span');
    if (span) span.textContent = hhmm(t.start) + (t.end != null && t.end !== '' ? '–' + hhmm(t.end) : '');
  }

  taskMenu(ev, t) {
    menu(ev.clientX, ev.clientY, [['Edit', () => this.edit(t)], ['Delete', () => this.remove(t), 'danger']]);
  }

  remove(t) {
    const d = Cal.doc();
    d.tasks = d.tasks.filter(x => x.id !== t.id);
    Cal.save();
    this.render(true);
  }

  edit(t) { taskModal(t, false, () => this.render(true)); }

  newTask() {
    const now = Cal.now();
    const today = ymd(now.date);
    // default day: today if it's on screen, else the first day shown
    let date;
    if (this.view === 'day') date = ymd(this.anchor);
    else if (this.view === 'week') { const d = this.days().map(ymd); date = d.includes(today) ? today : d[0]; }
    else date = this.anchor.getMonth() === now.date.getMonth() && this.anchor.getFullYear() === now.date.getFullYear() ? today : ymd(new Date(this.anchor.getFullYear(), this.anchor.getMonth(), 1));
    const { s, e } = Cal.span();
    const start = date === today ? Math.max(s, Math.min(e - 60, Math.ceil((now.mins + 1) / 60) * 60)) : s + 60;
    taskModal({ id: uid(), title: '', desc: '', date, start, end: start + 60, label: '' }, true, () => this.render(true));
  }

  // ---- month ------------------------------------------------------------
  renderMonth() {
    const a = this.anchor;
    const first = new Date(a.getFullYear(), a.getMonth(), 1);
    const start = mondayOf(first);
    const daysInMonth = new Date(a.getFullYear(), a.getMonth() + 1, 0).getDate();
    const weeks = Math.ceil((((first.getDay() + 6) % 7) + daysInMonth) / 7);
    const todayStr = ymd(Cal.now().date);
    const cal = h('div', { class: 'cal' });
    const head = h('div', { class: 'cal-head', style: 'grid-template-columns:repeat(7,1fr)' }, ...DAYS.map(d => h('div', {}, d)));
    const grid = h('div', { class: 'month', style: `grid-template-rows:repeat(${weeks},1fr)` });
    cal.append(head, grid);
    this.root.append(cal);
    const cellH = (grid.clientHeight || 600) / weeks;
    const maxChips = Math.max(1, Math.floor((cellH - 26) / 20));
    for (let i = 0; i < weeks * 7; i++) {
      const d = addDays(start, i);
      const ds = ymd(d);
      const cell = h('div', { class: 'mcell' + (d.getMonth() !== a.getMonth() ? ' other' : '') + (ds === todayStr ? ' today' : ''),
        onclick: () => { this.view = 'day'; this.anchor = d; this.follow = ds === todayStr; Cal.doc().view = 'day'; this.renderTools(); this.render(); } },
        h('div', { class: 'd' }, h('b', {}, d.getDate())));
      const tasks = this.tasksOn(ds);
      tasks.slice(0, maxChips).forEach(t => {
        const chip = h('div', { class: 'mchip', style: `--c:${Cal.color(t)}` }, `${hhmm(t.start)} ${t.title}`);
        chip.addEventListener('click', ev => { ev.stopPropagation(); this.edit(t); });
        chip.addEventListener('contextmenu', ev => { ev.preventDefault(); ev.stopPropagation(); this.taskMenu(ev, t); });
        cell.append(chip);
      });
      if (tasks.length > maxChips) cell.append(h('div', { class: 'mmore' }, `+${tasks.length - maxChips}`));
      grid.append(cell);
    }
  }

  // ---- settings (start / end of your day) -----------------------------------
  settings(ev) {
    const old = $('#calpop');
    if (old) { old.remove(); return; }
    const d = Cal.doc();
    const opts = sel => Array.from({ length: 24 }, (_, i) => h('option', { value: i * 60, selected: (+sel % 1440) === i * 60 }, `${pad2(i)}:00`));
    const st = h('select', {}, ...opts(d.dayStart));
    const en = h('select', {}, ...opts(d.dayEnd));
    const pop = h('div', { class: 'pop', id: 'calpop' },
      h('h4', {}, 'Calendar settings'),
      h('div', { class: 'field' }, h('label', {}, 'Start time'), st),
      h('div', { class: 'field' }, h('label', {}, 'End time'), en),
      h('div', { class: 'buttons', style: 'display:flex;gap:8px;justify-content:flex-end' },
        h('button', { onclick: () => pop.remove() }, 'Cancel'),
        h('button', { class: 'accent', onclick: () => {
          d.dayStart = +st.value;
          d.dayEnd = +en.value === 0 ? 1440 : +en.value;
          Cal.save(); pop.remove(); this.render();
        } }, 'Save')));
    document.body.append(pop);
    const r = ev.currentTarget.getBoundingClientRect();
    pop.style.top = r.bottom + 8 + 'px';
    pop.style.left = Math.min(r.right - 300, innerWidth - 310) + 'px';
    setTimeout(() => document.addEventListener('mousedown', function off(e) { if (!pop.contains(e.target)) { pop.remove(); document.removeEventListener('mousedown', off); } }), 0);
  }

  key(e) {
    if (e.target.matches('input,textarea,select')) return;
    if (e.key === 'ArrowLeft') { e.preventDefault(); this.move(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); this.move(1); }
    else if (e.key === '+' || (e.ctrlKey && e.key.toLowerCase() === 'n')) { e.preventDefault(); this.newTask(); }
    else if (e.key === 'Escape') host.fire('hide');
  }
}

function svg(d) {
  const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  s.setAttribute('viewBox', '0 0 24 24');
  const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  p.setAttribute('d', d);
  s.append(p);
  return s;
}

// Add / edit a task. onDone runs after saving or deleting.
function taskModal(t, isNew, onDone) {
  const doc = Cal.doc();
  doc.labels = doc.labels || [];
  doc.tasks = doc.tasks || [];
  let label = t.label || '';
  modal((box, close) => {
    const title = h('input', { type: 'text', value: t.title || '', placeholder: 'Title', autofocus: true });
    const desc = h('textarea', { placeholder: 'Description', rows: 3 }, t.desc || '');
    const date = h('input', { type: 'date', value: t.date });
    const start = h('input', { type: 'time', value: hhmm(+t.start) });
    const end = h('input', { type: 'time', value: t.end != null && t.end !== '' ? hhmm(+t.end) : '' });
    const chips = h('div', { class: 'chips' });
    const renderChips = () => {
      chips.innerHTML = '';
      chips.append(h('span', { class: 'chip' + (label === '' ? ' on' : ''), onclick: () => { label = ''; renderChips(); } }, 'None'));
      for (const l of doc.labels) {
        const c = h('span', { class: 'chip' + (label === l.id ? ' on' : ''), onclick: () => { label = l.id; renderChips(); } }, h('i', { style: `background:${l.color}` }), l.name);
        c.addEventListener('contextmenu', ev => { ev.preventDefault(); menu(ev.clientX, ev.clientY, [['Delete label', () => { doc.labels = doc.labels.filter(x => x.id !== l.id); if (label === l.id) label = ''; Cal.save(); renderChips(); }, 'danger']]); });
        chips.append(c);
      }
      chips.append(h('span', { class: 'chip add', onclick: () => newLabel() }, '+'));
    };
    const newLabel = () => {
      let color = COLORS[doc.labels.length % COLORS.length];
      const name = h('input', { type: 'text', placeholder: 'Label', style: 'width:140px' });
      const sw = h('div', { class: 'swatches' });
      const drawSw = () => { sw.innerHTML = ''; COLORS.forEach(c => sw.append(h('span', { class: c === color ? 'on' : '', style: `background:${c}`, onclick: () => { color = c; drawSw(); } }))); };
      drawSw();
      const add = () => { const n = name.value.trim(); if (!n) return; const l = { id: uid(), name: n, color }; doc.labels.push(l); label = l.id; Cal.save(); renderChips(); };
      name.addEventListener('keydown', ev => { if (ev.key === 'Enter') { ev.preventDefault(); ev.stopPropagation(); add(); } });
      chips.innerHTML = '';
      chips.append(name, sw, h('button', { onclick: add }, 'Add'));
      name.focus();
    };
    renderChips();
    const save = () => {
      const st = Cal.fromInput(start.value);
      let en = Cal.fromInput(end.value);
      if (!title.value.trim()) { title.focus(); return; }
      if (st == null || !date.value) return;
      if (en != null && en <= st) { toast('End is before start', 'warn'); end.focus(); return; }
      Object.assign(t, { title: title.value.trim(), desc: desc.value, date: date.value, start: st, end: en == null ? '' : en, label });
      if (isNew) doc.tasks.push(t);
      Cal.save();
      close();
      onDone && onDone();
    };
    [title, date, start, end].forEach(x => x.addEventListener('keydown', ev => { if (ev.key === 'Enter') { ev.preventDefault(); save(); } }));
    desc.addEventListener('keydown', ev => { if (ev.key === 'Enter' && ev.ctrlKey) { ev.preventDefault(); save(); } });
    box.append(
      h('h3', {}, isNew ? 'New task' : 'Edit task'),
      title, desc,
      h('div', { class: 'row' }, date, start, h('span', { style: 'color:var(--faint)' }, '–'), end),
      chips,
      h('div', { class: 'buttons' },
        isNew ? null : h('button', { class: 'danger left', onclick: () => { doc.tasks = doc.tasks.filter(x => x.id !== t.id); Cal.save(); close(); onDone && onDone(); } }, 'Delete'),
        h('button', { onclick: close }, 'Cancel'),
        h('button', { class: 'accent', onclick: save }, 'Save')));
  }, 480);
}
