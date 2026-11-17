'use strict';

const { SCOPE_ACTIVE, SCOPE_SELECTION, SCOPE_NOTES, MAX_SELECTED_NOTES } = require('./context');
const { describeProposal } = require('./changes');
const { text, clip } = require('./util');

const CONTEXT_DIFF_STYLE = `
.harness-scope-bar { display:flex; flex-direction:column; gap:5px; margin-bottom:6px; padding:6px 8px;
  border:1px solid var(--background-modifier-border,#e1dce6); border-radius:8px;
  background:var(--background-secondary-alt,#faf8fc); }
.harness-scope-top { display:flex; align-items:center; justify-content:space-between; gap:6px; flex-wrap:wrap; }
.harness-scope-tabs { display:flex; align-items:center; gap:3px; flex-wrap:wrap; }
.harness-scope-tab { border:1px solid transparent; border-radius:6px; background:transparent;
  color:var(--text-muted,#827b87); padding:3px 7px; font-size:11px; cursor:pointer; }
.harness-scope-tab:hover { background:var(--background-secondary,#eeeaf1); color:var(--text-normal,#2f2b35); }
.harness-scope-tab.active { background:#8c7eab; color:#fff; border-color:#8c7eab; font-weight:600; }
.harness-scope-actions { display:flex; align-items:center; gap:4px; }
.harness-scope-mini { border:1px solid var(--background-modifier-border,#e1dce6); border-radius:5px;
  background:transparent; color:var(--text-muted,#827b87); padding:2px 6px; font-size:10.5px; cursor:pointer; }
.harness-scope-mini:hover { background:var(--background-secondary,#eeeaf1); color:var(--text-normal,#2f2b35); }
.harness-scope-status { font-size:11px; color:var(--text-muted,#827b87); line-height:1.45;
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-scope-status.warn { color:#b06a2b; }
.harness-scope-status.denied { color:#b03b54; }
.harness-msg-ctx { display:inline-flex; align-items:center; gap:4px; margin-bottom:4px; padding:2px 7px;
  border-radius:999px; background:rgba(140,126,171,.14); color:#5f5179; font-size:10.5px; }
.harness-citations { display:flex; flex-wrap:wrap; align-items:center; gap:5px; margin-top:7px; padding-top:6px;
  border-top:1px dashed var(--background-modifier-border,#e5e0ec); font-size:11px; }
.harness-citations-label { color:var(--text-muted,#827b87); font-size:10.5px; margin-right:2px; }
.harness-cite-pill { display:inline-flex; align-items:center; gap:3px; padding:2px 8px; border-radius:999px;
  border:1px solid var(--background-modifier-border,#d9d2e0); background:var(--background-secondary,#f5f2f8);
  color:var(--text-accent,#6d5e8d); font-size:11px; cursor:pointer; max-width:240px;
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-cite-pill:hover { border-color:#8c7eab; background:rgba(140,126,171,.15); }
.harness-diff-card { margin:8px 0 4px; border:1px solid var(--background-modifier-border,#d9d2e0); border-radius:8px;
  background:var(--background-primary,#fff); overflow:hidden; font-size:11.5px; }
.harness-diff-head { display:flex; align-items:center; justify-content:space-between; gap:6px; padding:7px 9px;
  background:var(--background-secondary,#f6f4f9); border-bottom:1px solid var(--background-modifier-border,#e5e0ec); }
.harness-diff-title-row { display:flex; align-items:center; gap:6px; min-width:0; flex:1; }
.harness-diff-kind { padding:1px 6px; border-radius:4px; font-size:10px; font-weight:600;
  background:rgba(140,126,171,.18); color:#5d4f7c; flex:0 0 auto; }
.harness-diff-kind.danger { background:rgba(211,75,102,.15); color:#b03b54; }
.harness-diff-path { border:none; background:none; padding:0; color:var(--text-normal,#2f2b35); font-weight:600;
  font-size:11.5px; text-align:left; cursor:pointer; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-diff-path:hover { color:#6d5e8d; text-decoration:underline; }
.harness-diff-meta { display:flex; align-items:center; gap:6px; flex:0 0 auto; font-size:10.5px; }
.harness-diff-stats { color:var(--text-muted,#827b87); font-family:monospace; }
.harness-diff-badge { padding:1px 6px; border-radius:999px; font-size:10px; font-weight:600; }
.harness-diff-badge.pending { background:rgba(208,145,56,.16); color:#9c6514; }
.harness-diff-badge.applied { background:rgba(63,166,117,.16); color:#277b52; }
.harness-diff-badge.rejected { background:rgba(130,123,135,.16); color:#68626f; }
.harness-diff-badge.undone { background:rgba(104,132,184,.16); color:#426198; }
.harness-diff-reason { padding:5px 9px; color:var(--text-muted,#6f6878); font-size:11px;
  border-bottom:1px solid var(--background-modifier-border,#eeeaf1); }
.harness-diff-err { padding:6px 9px; background:rgba(211,75,102,.08); color:#b03b54; font-size:11px;
  border-bottom:1px solid rgba(211,75,102,.2); white-space:pre-wrap; }
.harness-diff-body { max-height:220px; overflow:auto; font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
  font-size:11px; line-height:1.45; background:var(--background-primary,#fff); }
.harness-diff-hunk-head { padding:2px 9px; background:var(--background-secondary-alt,#f3f1f6);
  color:var(--text-faint,#8c8596); font-size:10px; border-top:1px solid var(--background-modifier-border,#eeeaf1); }
.harness-diff-line { display:flex; gap:6px; padding:1px 9px; white-space:pre-wrap; word-break:break-word; }
.harness-diff-line.add { background:rgba(63,166,117,.12); color:#1d6a43; }
.harness-diff-line.remove { background:rgba(211,75,102,.12); color:#a3334b; }
.harness-diff-line.context { color:var(--text-muted,#6e6778); }
.harness-diff-ln { width:26px; flex:0 0 auto; text-align:right; color:var(--text-faint,#a59eb0); user-select:none; }
.harness-diff-sign { width:10px; flex:0 0 auto; font-weight:700; user-select:none; }
.harness-diff-txt { flex:1 1 auto; min-width:0; }
.harness-diff-foot { display:flex; align-items:center; justify-content:space-between; gap:6px; padding:6px 9px;
  border-top:1px solid var(--background-modifier-border,#e5e0ec); background:var(--background-secondary,#faf9fc); }
.harness-diff-btns { display:flex; align-items:center; gap:6px; flex-wrap:wrap; }
.harness-btn.danger { background:#c7445d; border-color:#c7445d; color:#fff; }
.harness-picker-list { max-height:260px; overflow-y:auto; border:1px solid var(--background-modifier-border,#e1dce6);
  border-radius:7px; margin:8px 0; }
.harness-picker-row { display:flex; align-items:center; gap:8px; padding:6px 9px; font-size:12px; cursor:pointer;
  border-bottom:1px solid var(--background-modifier-border,#f1edf6); }
.harness-picker-row:last-child { border-bottom:none; }
.harness-picker-row:hover { background:var(--background-secondary,#f5f2f8); }
.harness-diff-note, .harness-picker-hint { font-size:11px; color:var(--text-muted,#827b87); line-height:1.45; }
.harness-picker-copy { display:flex; flex-direction:column; min-width:0; flex:1; }
.harness-picker-name { font-weight:600; color:var(--text-normal,#2f2b35); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.harness-picker-path { font-size:10.5px; color:var(--text-muted,#827b87); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
`;

const SCOPE_ITEMS = [
  { id: SCOPE_ACTIVE, label: '当前笔记' },
  { id: SCOPE_SELECTION, label: '选中内容' },
  { id: SCOPE_NOTES, label: '指定笔记' }
];

const STATUS_BADGE = {
  pending: { text: '待确认', cls: 'pending' },
  applied: { text: '已写入', cls: 'applied' },
  rejected: { text: '已拒绝', cls: 'rejected' },
  undone: { text: '已撤销', cls: 'undone' }
};

function el(tag, className, textValue) {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (textValue !== undefined && textValue !== null) {
    node.textContent = String(textValue);
  }
  return node;
}

function btn(label, className, onClick, disabled) {
  const node = el('button', className || 'harness-btn', label);
  node.type = 'button';
  node.disabled = Boolean(disabled);
  if (onClick) {
    node.addEventListener('click', onClick);
  }
  return node;
}

/** Renders the 3-scope selector bar above the Harness composer input. */
function renderScopeBar(options) {
  const scope = options.scope || SCOPE_ACTIVE;
  const resolved = options.resolved || null;
  const selectedIds = Array.isArray(options.selectedIds) ? options.selectedIds : [];
  const bar = el('div', 'harness-scope-bar');

  const top = el('div', 'harness-scope-top');
  const tabs = el('div', 'harness-scope-tabs');
  for (let i = 0; i < SCOPE_ITEMS.length; i += 1) {
    const item = SCOPE_ITEMS[i];
    const isActive = scope === item.id;
    const label = item.id === SCOPE_NOTES && selectedIds.length > 0
      ? `${item.label}(${selectedIds.length})`
      : item.label;
    const tab = btn(
      label,
      `harness-scope-tab${isActive ? ' active' : ''}`,
      () => options.onSwitchScope(item.id),
      options.busy
    );
    tab.setAttribute('data-scope', item.id);
    tabs.appendChild(tab);
  }
  top.appendChild(tabs);

  const actions = el('div', 'harness-scope-actions');
  if (scope === SCOPE_NOTES) {
    actions.appendChild(btn('选择笔记', 'harness-scope-mini', options.onOpenPicker, options.busy));
  }
  actions.appendChild(btn('刷新', 'harness-scope-mini', options.onRefresh, options.busy));
  top.appendChild(actions);
  bar.appendChild(top);

  let statusText = '正在检测上下文...';
  let statusCls = 'harness-scope-status';
  if (resolved) {
    if (resolved.ok) {
      statusText = `${resolved.label}：${resolved.summary}`;
    } else if (resolved.code === 'E_PERMISSION_DENIED') {
      statusText = resolved.message || '缺少宿主对应读取权限';
      statusCls += ' denied';
    } else {
      statusText = resolved.message || resolved.summary || '上下文未就绪';
      statusCls += ' warn';
    }
  }
  const statusEl = el('div', statusCls, statusText);
  statusEl.setAttribute('title', statusText);
  bar.appendChild(statusEl);
  return bar;
}

/** Renders compact context tag attached to a sent user message bubble. */
function renderMessageContextTag(contextMeta, onOpenCitation) {
  if (!contextMeta || !contextMeta.scope) {
    return null;
  }
  const label = contextMeta.summary
    ? `${contextMeta.label || '上下文'} · ${contextMeta.summary}`
    : (contextMeta.label || '上下文');
  const pill = el('div', 'harness-msg-ctx', label);
  const refs = Array.isArray(contextMeta.refs) ? contextMeta.refs : [];
  if (refs.length === 1 && refs[0].path && typeof onOpenCitation === 'function') {
    pill.style.cursor = 'pointer';
    pill.addEventListener('click', () => onOpenCitation(refs[0]));
  }
  return pill;
}

/** Renders verified clickable note citation pills beneath an assistant reply. */
function renderCitationsBar(citations, onOpenCitation) {
  if (!Array.isArray(citations) || citations.length === 0) {
    return null;
  }
  const row = el('div', 'harness-citations');
  const hasExplicit = citations.some((c) => c.source === 'cited');
  row.appendChild(el('span', 'harness-citations-label', hasExplicit ? '引用笔记：' : '参考来源：'));

  for (let i = 0; i < citations.length; i += 1) {
    const item = citations[i];
    const displayName = item.name || item.path;
    const fragSuffix = item.fragment ? ` #${item.fragment}` : '';
    const pill = btn(
      `${displayName}${fragSuffix}`,
      'harness-cite-pill',
      () => onOpenCitation(item),
      false
    );
    pill.setAttribute('title', `${item.path}${item.fragment ? `#${item.fragment}` : ''}`);
    row.appendChild(pill);
  }
  return row;
}

/** Renders an interactive Diff Proposal card with Confirm / Reject / Undo actions. */
function renderProposalCard(proposal, options) {
  if (!proposal) {
    return null;
  }
  const info = describeProposal(proposal);
  const card = el('div', 'harness-diff-card');
  card.setAttribute('data-proposal-id', proposal.id);

  const head = el('div', 'harness-diff-head');
  const titleRow = el('div', 'harness-diff-title-row');
  const isDanger = proposal.kind === 'delete_note';
  titleRow.appendChild(el('span', `harness-diff-kind${isDanger ? ' danger' : ''}`, info.title));

  const pathBtn = btn(
    info.targetLabel,
    'harness-diff-path',
    () => {
      if (typeof options.onOpenNote === 'function') {
        options.onOpenNote({ id: proposal.afterFileId || proposal.fileId, path: proposal.newPath || proposal.path });
      }
    },
    false
  );
  pathBtn.setAttribute('title', info.targetLabel);
  titleRow.appendChild(pathBtn);
  head.appendChild(titleRow);

  const meta = el('div', 'harness-diff-meta');
  meta.appendChild(el('span', 'harness-diff-stats', info.statsLabel));
  const badgeSpec = STATUS_BADGE[proposal.status] || STATUS_BADGE.pending;
  meta.appendChild(el('span', `harness-diff-badge ${badgeSpec.cls}`, badgeSpec.text));
  head.appendChild(meta);
  card.appendChild(head);

  if (proposal.reason) {
    card.appendChild(el('div', 'harness-diff-reason', `说明：${proposal.reason}`));
  }
  if (proposal.lastError) {
    card.appendChild(el('div', 'harness-diff-err', proposal.lastError));
  }

  const expandedMap = options.expandedMap || new Map();
  const isExpanded = expandedMap.has(proposal.id)
    ? expandedMap.get(proposal.id)
    : proposal.status === 'pending';

  if (isExpanded && info.diff && info.diff.hunks.length > 0) {
    const body = el('div', 'harness-diff-body');
    for (let h = 0; h < info.diff.hunks.length; h += 1) {
      const hunk = info.diff.hunks[h];
      body.appendChild(el('div', 'harness-diff-hunk-head', `@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@`));
      for (let l = 0; l < hunk.lines.length; l += 1) {
        const line = hunk.lines[l];
        const row = el('div', `harness-diff-line ${line.type}`);
        const ln = line.type === 'remove' ? line.oldLine : line.newLine;
        const sign = line.type === 'add' ? '+' : line.type === 'remove' ? '-' : ' ';
        row.appendChild(el('span', 'harness-diff-ln', ln ? String(ln) : ''));
        row.appendChild(el('span', 'harness-diff-sign', sign));
        row.appendChild(el('span', 'harness-diff-txt', line.text));
        body.appendChild(row);
      }
    }
    if (info.diff.truncated) {
      body.appendChild(el('div', 'harness-diff-hunk-head', '... 内容较多，仅预览前 140 行差异'));
    }
    card.appendChild(body);
  } else if (isExpanded && proposal.kind === 'rename_note') {
    const body = el('div', 'harness-diff-body');
    const rem = el('div', 'harness-diff-line remove');
    rem.appendChild(el('span', 'harness-diff-sign', '-'));
    rem.appendChild(el('span', 'harness-diff-txt', proposal.oldPath));
    const add = el('div', 'harness-diff-line add');
    add.appendChild(el('span', 'harness-diff-sign', '+'));
    add.appendChild(el('span', 'harness-diff-txt', proposal.newPath));
    body.appendChild(rem);
    body.appendChild(add);
    card.appendChild(body);
  }

  const foot = el('div', 'harness-diff-foot');
  const toggleBtn = btn(
    isExpanded ? '收起差异' : '查看差异',
    'harness-scope-mini',
    () => options.onToggleExpand(proposal.id, !isExpanded),
    false
  );
  foot.appendChild(toggleBtn);

  const btns = el('div', 'harness-diff-btns');
  const isBusy = options.busyId === proposal.id;
  if (proposal.status === 'pending') {
    btns.appendChild(btn('拒绝', 'harness-btn harness-diff-reject', () => options.onReject(proposal.id), isBusy));
    btns.appendChild(btn(
      isBusy ? '写入中...' : (isDanger ? '确认删除' : '确认写入'),
      `harness-btn ${isDanger ? 'danger' : 'primary'} harness-diff-confirm`,
      () => options.onConfirm(proposal.id),
      isBusy
    ));
  } else if (proposal.status === 'applied') {
    btns.appendChild(btn(
      isBusy ? '撤销中...' : '撤销本次写入',
      'harness-btn harness-diff-undo',
      () => options.onUndo(proposal.id),
      isBusy
    ));
  } else if (proposal.status === 'rejected') {
    btns.appendChild(el('span', 'harness-diff-note', '原文未改动'));
  } else if (proposal.status === 'undone') {
    btns.appendChild(el('span', 'harness-diff-note', '已恢复修改前内容'));
  }
  foot.appendChild(btns);
  card.appendChild(foot);
  return card;
}

/** Renders multi-note picker modal with in-place search & toggle updates (no focus loss). */
function renderNotePickerModal(options) {
  const files = Array.isArray(options.files) ? options.files : [];
  const selectedIds = new Set(Array.isArray(options.selectedIds) ? options.selectedIds : []);
  let currentQuery = text(options.query);

  const box = el('div', 'harness-picker-box');
  const search = document.createElement('input');
  search.type = 'text';
  search.className = 'harness-input';
  search.style.minHeight = '32px';
  search.placeholder = '搜索笔记名称或路径...';
  search.value = currentQuery;

  const counter = el('div', 'harness-picker-hint');
  counter.style.marginTop = '6px';
  const list = el('div', 'harness-picker-list');

  function updateCounter() {
    counter.textContent = `已选择 ${selectedIds.size} / ${MAX_SELECTED_NOTES} 篇（单篇及总字数会自动裁剪适配上下文窗口）`;
  }

  function renderList() {
    list.replaceChildren();
    const q = currentQuery.trim().toLowerCase();
    const filtered = q
      ? files.filter((f) => text(f.path).toLowerCase().includes(q) || text(f.name).toLowerCase().includes(q))
      : files;
    if (filtered.length === 0) {
      const empty = el('div', 'harness-picker-hint', '没有匹配的 Markdown 笔记');
      empty.style.padding = '12px';
      list.appendChild(empty);
      return;
    }
    const limit = Math.min(filtered.length, 150);
    for (let i = 0; i < limit; i += 1) {
      const file = filtered[i];
      const row = el('label', 'harness-picker-row');
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = selectedIds.has(file.id);
      cb.addEventListener('change', () => {
        if (cb.checked) {
          if (selectedIds.size >= MAX_SELECTED_NOTES) {
            cb.checked = false;
            return;
          }
          selectedIds.add(file.id);
        } else {
          selectedIds.delete(file.id);
        }
        updateCounter();
        if (typeof options.onToggleId === 'function') {
          options.onToggleId(file.id, cb.checked, Array.from(selectedIds));
        }
      });
      row.appendChild(cb);

      const copy = el('span', 'harness-picker-copy');
      copy.appendChild(el('span', 'harness-picker-name', clip(text(file.name) || text(file.path), 40)));
      copy.appendChild(el('span', 'harness-picker-path', file.path));
      row.appendChild(copy);
      list.appendChild(row);
    }
  }

  search.addEventListener('input', () => {
    currentQuery = search.value;
    if (typeof options.onQueryChange === 'function') {
      options.onQueryChange(currentQuery);
    }
    renderList();
  });

  updateCounter();
  renderList();
  box.appendChild(search);
  box.appendChild(counter);
  box.appendChild(list);

  const footer = el('div', 'harness-diff-btns');
  footer.style.justifyContent = 'space-between';
  footer.appendChild(btn('清空选择', 'harness-btn', () => {
    selectedIds.clear();
    updateCounter();
    renderList();
    if (typeof options.onClear === 'function') {
      options.onClear();
    }
  }, false));
  const right = el('div', 'harness-diff-btns');
  right.appendChild(btn('取消', 'harness-btn', options.onCancel, false));
  right.appendChild(btn('确定使用', 'harness-btn primary', () => {
    options.onApply(Array.from(selectedIds));
  }, false));
  footer.appendChild(right);
  box.appendChild(footer);
  return { box, searchInput: search };
}

module.exports = {
  CONTEXT_DIFF_STYLE,
  renderScopeBar,
  renderMessageContextTag,
  renderCitationsBar,
  renderProposalCard,
  renderNotePickerModal
};
