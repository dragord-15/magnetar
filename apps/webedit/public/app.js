const API = '';
const state = {
  root: '.', cwd: '.', tree: {}, open: {}, tabs: [], active: null,
  allFiles: [], paletteSel: 0, modalCb: null
};

const $ = (s) => document.querySelector(s);
const editorEl = $('#editor');
const highlightEl = $('#highlight');
const gutterEl = $('#gutter');
const scrollEl = $('#editor-scroll');
const tabsEl = $('#tabs');
const treeEl = $('#file-tree');

async function api(path, opts = {}) {
  try {
    const r = await fetch(API + path, opts);
    const ct = r.headers.get('content-type') || '';
    if (ct.includes('application/json')) return await r.json();
    return { ok: r.ok, text: await r.text() };
  } catch (e) {
    return { ok: false, error: String(e) };
  }
}
const apiGet = (p) => api(p);
const apiPost = (p) => api(p, { method: 'POST' });

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function basename(p) { const i = p.lastIndexOf('/'); return i >= 0 ? p.slice(i+1) : p; }
function dirname(p) { const i = p.lastIndexOf('/'); return i >= 0 ? p.slice(0,i) : '.'; }
function ext(p) { const b = basename(p); const i = b.lastIndexOf('.'); return i >= 0 ? b.slice(i+1).toLowerCase() : ''; }

function iconFor(name, type) {
  if (type === 'dir') return '📁';
  const e = ext(name);
  if (e === 'mg') return '◇';
  if (e === 'js' || e === 'ts') return 'JS';
  if (e === 'html' || e === 'htm') return '<>';
  if (e === 'css') return '#';
  if (e === 'json') return '{}';
  if (e === 'md') return 'M↓';
  return '📄';
}
function langFor(path) {
  const e = ext(path);
  if (e === 'mg') return 'magnetar';
  if (e === 'js') return 'javascript';
  if (e === 'ts') return 'typescript';
  if (e === 'html') return 'html';
  if (e === 'css') return 'css';
  if (e === 'json') return 'json';
  if (e === 'md') return 'markdown';
  if (e === 'c' || e === 'h') return 'c';
  if (e === 'py') return 'python';
  return 'plaintext';
}

function setStatus(msg) { $('#status-msg').textContent = msg; }
function setPos() {
  const v = editorEl.value;
  const i = editorEl.selectionStart;
  let line = 1, col = 1;
  for (let k = 0; k < i; k++) { if (v[k] === '\n') { line++; col = 1; } else col++; }
  $('#status-pos').textContent = `Ln ${line}, Col ${col}`;
}

function logOutput(text, clear=false) {
  const out = $('#panel-output');
  if (clear) out.textContent = '';
  out.textContent += text + (text.endsWith('\n') ? '' : '\n');
  out.scrollTop = out.scrollHeight;
  showPanel('output');
}

function showPanel(tab) {
  $('#panel-output').classList.toggle('hidden', tab !== 'output');
  $('#panel-search').classList.toggle('hidden', tab !== 'search');
  $('#panel-problems').classList.toggle('hidden', tab !== 'problems');
  document.querySelectorAll('.panel-tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
}

async function init() {
  try {
    const info = await apiGet('/api/cwd');
    if (info && info.ok) {
      state.cwd = info.cwd || '.';
      state.root = info.cwd || '.';
      $('#root-path').textContent = info.cwd || '.';
    } else {
      state.root = '.';
      $('#root-path').textContent = '.';
      setStatus('Connected with limited info');
    }
    await loadDir(state.root, treeEl, 0);
  } catch (e) {
    setStatus('Init failed');
    logOutput('Init error: ' + e);
  }
  bindEvents();
  setStatus('Ready');
}

async function loadDir(path, container, depth) {
  const res = await apiGet('/api/list?path=' + encodeURIComponent(path));
  if (!res || !res.ok) { container.innerHTML = '<div class="tree-item">Failed to load</div>'; return; }
  const entries = (res.entries || []).slice().sort((a,b) => {
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  state.tree[path] = entries;
  container.innerHTML = '';
  if (path !== state.root && depth === 0) {
    const up = document.createElement('div');
    up.className = 'tree-item dir';
    up.style.paddingLeft = (8 + depth*12) + 'px';
    up.innerHTML = `<span class="twisty"></span><span class="icon">..</span><span class="name">..</span>`;
    up.onclick = () => openDirInTree(dirname(path) === '' ? '.' : dirname(path));
    container.appendChild(up);
  }
  for (const e of entries) {
    state.allFiles.push({ ...e });
    const row = document.createElement('div');
    row.className = 'tree-item ' + (e.type === 'dir' ? 'dir' : 'file');
    row.dataset.path = e.path;
    row.style.paddingLeft = (8 + depth*12) + 'px';
    const twisty = e.type === 'dir' ? (state.open[e.path] ? '▾' : '▸') : '';
    row.innerHTML = `<span class="twisty">${twisty}</span><span class="icon">${esc(iconFor(e.name,e.type))}</span><span class="name">${esc(e.name)}</span>`;
    if (e.type === 'dir') {
      const kids = document.createElement('div');
      kids.className = 'tree-children';
      row.onclick = async (ev) => {
        ev.stopPropagation();
        if (state.open[e.path]) {
          state.open[e.path] = false;
          kids.innerHTML = '';
          row.querySelector('.twisty').textContent = '▸';
        } else {
          state.open[e.path] = true;
          row.querySelector('.twisty').textContent = '▾';
          await loadDir(e.path, kids, depth + 1);
        }
      };
      container.appendChild(row);
      container.appendChild(kids);
      if (state.open[e.path]) await loadDir(e.path, kids, depth + 1);
    } else {
      row.onclick = () => openFile(e.path);
      container.appendChild(row);
    }
  }
}

async function openDirInTree(path) {
  state.root = path;
  state.allFiles = [];
  await loadDir(path, treeEl, 0);
}

async function refreshTree() {
  state.allFiles = [];
  await loadDir(state.root, treeEl, 0);
  setStatus('Explorer refreshed');
}

async function openFile(path) {
  if (state.tabs.find(t => t.path === path)) { activateTab(path); return; }
  setStatus('Opening ' + path + '...');
  const res = await apiGet('/api/read?path=' + encodeURIComponent(path));
  if (!res || !res.ok) { setStatus('Failed to open: ' + (res && res.error || '')); logOutput('Error opening ' + path + ': ' + (res && res.error)); return; }
  state.tabs.push({ path, content: res.content || '', saved: res.content || '', modified: false });
  renderTabs();
  activateTab(path);
  setStatus('Opened ' + path);
}

function activateTab(path) {
  state.active = path;
  renderTabs();
  const t = state.tabs.find(x => x.path === path);
  if (!t) return;
  $('#welcome').classList.add('hidden');
  $('#editor-wrap').classList.remove('hidden');
  editorEl.value = t.content;
  $('#status-lang').textContent = langFor(path);
  updateHighlight();
  updateGutter();
  setPos();
  highlightActiveTree(path);
}

function closeTab(path) {
  const i = state.tabs.findIndex(t => t.path === path);
  if (i < 0) return;
  const t = state.tabs[i];
  if (t.modified && !confirm('Discard unsaved changes to ' + basename(path) + '?')) return;
  state.tabs.splice(i,1);
  if (state.active === path) {
    state.active = state.tabs.length ? state.tabs[Math.max(0,i-1)].path : null;
  }
  renderTabs();
  if (state.active) activateTab(state.active);
  else { $('#editor-wrap').classList.add('hidden'); $('#welcome').classList.remove('hidden'); editorEl.value=''; highlightEl.innerHTML=''; gutterEl.innerHTML=''; $('#status-lang').textContent='plaintext'; }
}

function renderTabs() {
  tabsEl.innerHTML = '';
  for (const t of state.tabs) {
    const el = document.createElement('div');
    el.className = 'tab' + (t.path === state.active ? ' active' : '');
    el.innerHTML = `<span class="tname" title="${esc(t.path)}">${esc(basename(t.path))}</span>${t.modified?'<span class="tmod">•</span>':''}<span class="tclose" data-close="${esc(t.path)}">×</span>`;
    el.onclick = (e) => {
      if (e.target.dataset.close) closeTab(e.target.dataset.close);
      else activateTab(t.path);
    };
    tabsEl.appendChild(el);
  }
}

function highlightActiveTree(path) {
  document.querySelectorAll('.tree-item.file').forEach(n => n.classList.toggle('active', n.dataset.path === path));
}

async function saveActive() {
  if (!state.active) return;
  const t = state.tabs.find(x => x.path === state.active);
  if (!t) return;
  t.content = editorEl.value;
  try {
    const r = await fetch('/api/save?path=' + encodeURIComponent(t.path), { method: 'POST', body: t.content });
    const j = await r.json();
    if (j && j.ok) {
      t.saved = t.content; t.modified = false; renderTabs();
      setStatus('Saved ' + t.path);
    } else {
      setStatus('Save failed');
      logOutput('Save failed: ' + (j && j.error || 'unknown'));
    }
  } catch (e) {
    setStatus('Save failed');
    logOutput('Save failed: ' + e);
  }
}

async function buildActive() {
  if (!state.active) { setStatus('No file open'); return; }
  const t = state.tabs.find(x => x.path === state.active);
  if (t && t.modified) await saveActive();
  setStatus('Building ' + state.active + '...');
  logOutput('> magc ' + state.active + ' -o /tmp/webedit_build', true);
  const res = await apiPost('/api/build?path=' + encodeURIComponent(state.active));
  if (res && res.ok) {
    logOutput(res.output || '(no output)');
    logOutput('\n[OK] Build succeeded (exit 0)');
    setStatus('Build succeeded');
  } else {
    logOutput((res && res.output) || '');
    logOutput('\n[FAIL] Build failed (exit ' + ((res && res.code) != null ? res.code : '?') + ')');
    setStatus('Build failed');
  }
}

// --- Syntax highlighting (simple tokenizer for Magnetar/JS/C-like) ---
const MG_KW = new Set(["fn","let","var","if","else","while","for","loop","break","continue","return","struct","const","static","as","use","extern","switch","case","default","in","from","to","sizeof","true","false","null","defer","import","typeof","match","async","await","pub","self","and","or","not","class","impl","enum","trait"]);
const MG_TYPES = new Set(["void","bool","int","i64","u8","u32","u64","usize","char","string","float","double"]);
function highlightCode(src, lang) {
  const s = src || '';
  let out = '', i = 0;
  const n = s.length;
  const isIdStart = c => /[A-Za-z_$]/.test(c);
  const isId = c => /[A-Za-z0-9_$]/.test(c);
  while (i < n) {
    const c = s[i];
    if (c === '/' && s[i+1] === '/') {
      let j = i+2; while (j < n && s[j] !== '\n') j++;
      out += `<span class="hl-com">${esc(s.slice(i,j))}</span>`; i = j; continue;
    }
    if (c === '/' && s[i+1] === '*') {
      let j = i+2; while (j+1 < n && !(s[j]==='*'&&s[j+1]==='/')) j++;
      j = Math.min(j+2, n);
      out += `<span class="hl-com">${esc(s.slice(i,j))}</span>`; i = j; continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      let j = i+1; while (j < n) { if (s[j]==='\\') { j+=2; continue; } if (s[j]===c) { j++; break; } if (c!=='`' && s[j]==='\n') break; j++; }
      out += `<span class="hl-str">${esc(s.slice(i,j))}</span>`; i = j; continue;
    }
    if (/[0-9]/.test(c)) {
      let j = i+1; while (j < n && /[0-9a-fA-FxX._]/.test(s[j])) j++;
      out += `<span class="hl-num">${esc(s.slice(i,j))}</span>`; i = j; continue;
    }
    if (isIdStart(c)) {
      let j = i+1; while (j < n && isId(s[j])) j++;
      const w = s.slice(i,j);
      let k = j; while (k < n && (s[k]===' '||s[k]==='\t')) k++;
      if ((lang === 'magnetar' || lang === 'javascript' || lang === 'typescript' || lang === 'c') && MG_KW.has(w)) out += `<span class="hl-kw">${esc(w)}</span>`;
      else if ((lang === 'magnetar' || lang === 'c') && MG_TYPES.has(w)) out += `<span class="hl-type">${esc(w)}</span>`;
      else if (s[k] === '(') out += `<span class="hl-fn">${esc(w)}</span>`;
      else out += esc(w);
      i = j; continue;
    }
    if (c === '#' && (i===0 || s[i-1]==='\n')) {
      let j = i+1; while (j < n && s[j] !== '\n') j++;
      out += `<span class="hl-pre">${esc(s.slice(i,j))}</span>`; i = j; continue;
    }
    out += esc(c); i++;
  }
  if (s.endsWith('\n')) out += ' ';
  return out;
}

function updateHighlight() {
  if (!state.active) return;
  highlightEl.innerHTML = highlightCode(editorEl.value, langFor(state.active));
  syncSizes();
  syncScroll();
}
function updateGutter() {
  const lines = editorEl.value.split('\n').length;
  let g = '';
  for (let i=1;i<=lines;i++) g += i + '\n';
  gutterEl.textContent = g;
}
function syncSizes() {
  // keep textarea and highlight same scrollable size
  editorEl.style.width = 'auto';
  editorEl.style.height = 'auto';
  const sw = Math.max(editorEl.scrollWidth, scrollEl.clientWidth);
  const sh = Math.max(editorEl.scrollHeight, scrollEl.clientHeight);
  editorEl.style.width = sw + 'px';
  editorEl.style.height = sh + 'px';
  highlightEl.style.width = sw + 'px';
  highlightEl.style.height = sh + 'px';
}
function syncScroll() {
  highlightEl.style.transform = `translate(${-editorEl.scrollLeft}px, ${-editorEl.scrollTop}px)`;
  gutterEl.scrollTop = editorEl.scrollTop;
}

// --- Search ---
async function doSearch() {
  const q = $('#search-input').value.trim();
  if (!q) return;
  const res = await apiGet('/api/search?path=' + encodeURIComponent(state.root) + '&q=' + encodeURIComponent(q));
  const box = $('#search-results');
  box.innerHTML = '';
  if (!res || !res.ok) { box.textContent = 'Search failed'; return; }
  const results = res.results || [];
  if (!results.length) { box.textContent = 'No results.'; return; }
  for (const r of results) {
    const d = document.createElement('div');
    d.className = 'sr-item';
    d.textContent = r.path;
    d.onclick = () => openFile(r.path);
    box.appendChild(d);
  }
  logOutput(`Search "${q}": ${results.length} file(s) matched`);
}

// --- Quick open palette ---
let paletteFiles = [];
function openPalette() {
  paletteFiles = [];
  function collect(path) {
    const entries = state.tree[path] || [];
    for (const e of entries) {
      if (e.type === 'dir') collect(e.path);
      else paletteFiles.push(e);
    }
  }
  collect(state.root);
  if (!paletteFiles.length) {
    // fallback: include open tabs
    for (const t of state.tabs) paletteFiles.push({ path: t.path, name: basename(t.path), type: 'file' });
  }
  state.paletteSel = 0;
  $('#palette-input').value = '';
  $('#palette').classList.remove('hidden');
  renderPalette();
  $('#palette-input').focus();
}
function closePalette() { $('#palette').classList.add('hidden'); }
function renderPalette() {
  const q = $('#palette-input').value.toLowerCase();
  const list = $('#palette-list');
  const filtered = paletteFiles.filter(f => f.path.toLowerCase().includes(q)).slice(0, 50);
  list.innerHTML = '';
  filtered.forEach((f, i) => {
    const d = document.createElement('div');
    d.className = 'palette-item' + (i === state.paletteSel ? ' sel' : '');
    d.innerHTML = `<span>${esc(f.name)}</span><span class="p-path">${esc(f.path)}</span>`;
    d.onclick = () => { closePalette(); openFile(f.path); };
    list.appendChild(d);
  });
  list._filtered = filtered;
}

// --- Modal for new file/folder ---
function promptModal(title, placeholder, cb) {
  $('#modal-title').textContent = title;
  const inp = $('#modal-input');
  inp.placeholder = placeholder || '';
  inp.value = '';
  $('#modal').classList.remove('hidden');
  inp.focus();
  state.modalCb = cb;
}
function closeModal(ok) {
  const cb = state.modalCb; state.modalCb = null;
  const v = $('#modal-input').value.trim();
  $('#modal').classList.add('hidden');
  if (ok && cb) cb(v);
}

// --- Events ---
function bindEvents() {
  editorEl.addEventListener('input', () => {
    const t = state.tabs.find(x => x.path === state.active);
    if (t) { t.content = editorEl.value; t.modified = t.content !== t.saved; renderTabs(); }
    updateHighlight(); updateGutter(); setPos();
  });
  editorEl.addEventListener('scroll', syncScroll);
  editorEl.addEventListener('click', setPos);
  editorEl.addEventListener('keyup', setPos);
  editorEl.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      e.preventDefault();
      const start = editorEl.selectionStart, end = editorEl.selectionEnd;
      const v = editorEl.value;
      editorEl.value = v.substring(0,start) + '    ' + v.substring(end);
      editorEl.selectionStart = editorEl.selectionEnd = start + 4;
      editorEl.dispatchEvent(new Event('input'));
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.key === 's') { e.preventDefault(); saveActive(); }
    if (e.ctrlKey && e.key === 'b') { e.preventDefault(); buildActive(); }
    if (e.ctrlKey && e.key === 'p') { e.preventDefault(); openPalette(); }
    if (e.ctrlKey && e.key === 'f' && !e.shiftKey) {
      const ae = document.activeElement;
      if (ae === editorEl) { e.preventDefault(); showPanel('search'); $('#search-input').focus(); }
    }
    if (e.key === 'Escape') { closePalette(); closeModal(false); }
  });

  $('#btn-save').onclick = saveActive;
  $('#btn-build').onclick = buildActive;
  $('#btn-refresh').onclick = refreshTree;
  $('#btn-new-file').onclick = () => promptModal('New File (relative to root)', 'path/to/file.txt', async (v) => {
    if (!v) return;
    const p = state.root === '.' ? v : state.root + '/' + v;
    await fetch('/api/save?path=' + encodeURIComponent(p), { method: 'POST', body: '' });
    await refreshTree(); openFile(p);
  });
  $('#btn-new-dir').onclick = () => promptModal('New Folder (relative to root)', 'path/to/folder', async (v) => {
    if (!v) return;
    const p = state.root === '.' ? v : state.root + '/' + v;
    await apiPost('/api/mkdir?path=' + encodeURIComponent(p));
    await refreshTree();
  });

  document.querySelectorAll('.panel-tab').forEach(t => t.onclick = () => showPanel(t.dataset.tab));
  $('#panel-close').onclick = () => { document.getElementById('panel').style.height = '35px'; };
  $('#search-btn').onclick = doSearch;
  $('#search-input').addEventListener('keydown', e => { if (e.key === 'Enter') doSearch(); });

  $('#palette-input').addEventListener('input', () => { state.paletteSel = 0; renderPalette(); });
  $('#palette-input').addEventListener('keydown', (e) => {
    const list = $('#palette-list')._filtered || [];
    if (e.key === 'ArrowDown') { e.preventDefault(); state.paletteSel = Math.min(state.paletteSel+1, list.length-1); renderPalette(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); state.paletteSel = Math.max(state.paletteSel-1, 0); renderPalette(); }
    else if (e.key === 'Enter') { e.preventDefault(); if (list[state.paletteSel]) { closePalette(); openFile(list[state.paletteSel].path); } }
    else if (e.key === 'Escape') { closePalette(); }
  });
  $('#palette').addEventListener('click', (e) => { if (e.target.id === 'palette') closePalette(); });

  $('#modal-cancel').onclick = () => closeModal(false);
  $('#modal-ok').onclick = () => closeModal(true);
  $('#modal-input').addEventListener('keydown', e => { if (e.key==='Enter') closeModal(true); if(e.key==='Escape') closeModal(false); });

  // resizer
  const resizer = $('#resizer'); const sidebar = $('#sidebar');
  let dragging = false;
  resizer.addEventListener('mousedown', () => { dragging = true; resizer.classList.add('dragging'); });
  window.addEventListener('mousemove', (e) => { if (!dragging) return; const w = Math.max(160, Math.min(500, e.clientX)); sidebar.style.width = w + 'px'; });
  window.addEventListener('mouseup', () => { dragging = false; resizer.classList.remove('dragging'); });
}

init();
