'use strict';

const { buildDiffHunks, summarizeDiffStats } = require('./diff');
const { lineRangeForOffsets } = require('./context');
const { isObject, text, normalizePath, basename, errorText } = require('./util');

const CHANGES_STORAGE_KEY = 'harness.changes.v1';
const CHANGES_CHAR_BUDGET = 48000;
const MAX_PROPOSALS = 15;

const KIND_LABELS = {
  create_note: '新增笔记',
  update_note: '修改笔记',
  append_to_note: '追加内容',
  rename_note: '重命名笔记',
  delete_note: '删除笔记',
  replace_selection: '修改选区',
  replace_active_editor: '替换编辑器内容'
};

function makeProposalId() {
  return `chg-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

function emptyStore() {
  return { version: 1, proposals: [] };
}

function normalizeProposal(raw) {
  if (!isObject(raw) || !text(raw.id) || !text(raw.kind)) {
    return null;
  }
  const status = raw.status === 'applied' || raw.status === 'rejected' || raw.status === 'undone'
    ? raw.status
    : 'pending';
  const beforeContent = typeof raw.beforeContent === 'string' ? raw.beforeContent : '';
  const afterContent = typeof raw.afterContent === 'string' ? raw.afterContent : '';
  const selectionRange = isObject(raw.selectionRange)
    ? {
        from: Math.max(0, Math.floor(Number(raw.selectionRange.from) || 0)),
        to: Math.max(0, Math.floor(Number(raw.selectionRange.to) || 0)),
        startLine: Math.max(0, Math.floor(Number(raw.selectionRange.startLine) || 0)),
        endLine: Math.max(0, Math.floor(Number(raw.selectionRange.endLine) || 0))
      }
    : null;
  const stats = isObject(raw.stats)
    ? {
        added: Number(raw.stats.added) || 0,
        removed: Number(raw.stats.removed) || 0,
        changed: raw.stats.changed !== false
      }
    : summarizeDiffStats(beforeContent, afterContent);

  return {
    id: text(raw.id),
    kind: text(raw.kind),
    status,
    path: normalizePath(text(raw.path)),
    oldPath: normalizePath(text(raw.oldPath)),
    newPath: normalizePath(text(raw.newPath)),
    fileId: text(raw.fileId),
    afterFileId: text(raw.afterFileId),
    beforeUpdatedAt: Number(raw.beforeUpdatedAt) || 0,
    afterUpdatedAt: Number(raw.afterUpdatedAt) || 0,
    beforeRevision: Number(raw.beforeRevision) || 0,
    selectionRange,
    reason: text(raw.reason),
    beforeContent,
    afterContent,
    stats,
    createdAt: Number(raw.createdAt) || Date.now(),
    appliedAt: Number(raw.appliedAt) || 0,
    rejectedAt: Number(raw.rejectedAt) || 0,
    undoneAt: Number(raw.undoneAt) || 0,
    lastError: text(raw.lastError)
  };
}

function parseStored(raw) {
  if (!raw) {
    return emptyStore();
  }
  let parsed = raw;
  if (typeof raw === 'string') {
    try {
      parsed = JSON.parse(raw);
    } catch (_error) {
      return emptyStore();
    }
  }
  if (!isObject(parsed) || !Array.isArray(parsed.proposals)) {
    return emptyStore();
  }
  const proposals = [];
  for (let i = 0; i < parsed.proposals.length; i += 1) {
    const item = normalizeProposal(parsed.proposals[i]);
    if (item) {
      proposals.push(item);
    }
  }
  return { version: 1, proposals: proposals.slice(-MAX_PROPOSALS) };
}

function fitBudget(store) {
  const list = store.proposals.slice(-MAX_PROPOSALS);
  let serialized = JSON.stringify({ version: 1, proposals: list });
  if (serialized.length <= CHANGES_CHAR_BUDGET) {
    return { version: 1, proposals: list };
  }

  const dropOrder = ['rejected', 'undone', 'applied'];
  for (let phase = 0; phase < dropOrder.length && serialized.length > CHANGES_CHAR_BUDGET; phase += 1) {
    const targetStatus = dropOrder[phase];
    let idx = list.findIndex((item) => item.status === targetStatus);
    while (idx >= 0 && serialized.length > CHANGES_CHAR_BUDGET) {
      list.splice(idx, 1);
      serialized = JSON.stringify({ version: 1, proposals: list });
      idx = list.findIndex((item) => item.status === targetStatus);
    }
  }

  while (list.length > 2 && serialized.length > CHANGES_CHAR_BUDGET) {
    list.shift();
    serialized = JSON.stringify({ version: 1, proposals: list });
  }
  return { version: 1, proposals: list };
}

async function loadChanges(ctx) {
  if (!ctx || !ctx.storage || typeof ctx.storage.get !== 'function') {
    return emptyStore();
  }
  try {
    return parseStored(await ctx.storage.get(CHANGES_STORAGE_KEY));
  } catch (_error) {
    return emptyStore();
  }
}

async function saveChanges(ctx, store) {
  if (!ctx || !ctx.storage || typeof ctx.storage.set !== 'function') {
    return store;
  }
  const fitted = fitBudget(store);
  store.proposals = fitted.proposals;
  await ctx.storage.set(CHANGES_STORAGE_KEY, fitted);
  return fitted;
}

function getProposal(store, id) {
  if (!store || !Array.isArray(store.proposals) || !id) {
    return null;
  }
  return store.proposals.find((item) => item.id === id) || null;
}

function upsertProposal(store, proposal) {
  const index = store.proposals.findIndex((item) => item.id === proposal.id);
  if (index >= 0) {
    store.proposals[index] = proposal;
  } else {
    store.proposals.push(proposal);
  }
  if (store.proposals.length > MAX_PROPOSALS) {
    store.proposals = store.proposals.slice(-MAX_PROPOSALS);
  }
  return proposal;
}

async function lookupByPath(ctx, vaultPath) {
  const norm = normalizePath(vaultPath);
  if (!norm || !ctx.vault || typeof ctx.vault.get !== 'function') {
    return null;
  }
  return ctx.vault.get(norm);
}

async function lookupByIdOrPath(ctx, fileId, fallbackPath) {
  if (fallbackPath) {
    const byPath = await lookupByPath(ctx, fallbackPath);
    if (byPath && (!fileId || byPath.id === fileId)) {
      return byPath;
    }
  }
  if (fileId && ctx.vault && typeof ctx.vault.listMarkdown === 'function') {
    const all = await ctx.vault.listMarkdown();
    const byId = all.find((item) => item.id === fileId);
    if (byId) {
      return byId;
    }
    if (fallbackPath) {
      const norm = normalizePath(fallbackPath);
      return all.find((item) => normalizePath(item.path) === norm) || null;
    }
  }
  return null;
}

/** Stages a write or destructive change without mutating vault notes or editors. */
async function stageProposal(ctx, store, input) {
  const kind = text(input && input.kind);
  const reason = text(input && input.reason).slice(0, 300);

  if (kind === 'create_note') {
    const path = normalizePath(text(input.path));
    if (!path) {
      throw new Error('缺少笔记路径');
    }
    const existing = await lookupByPath(ctx, path);
    if (existing) {
      throw new Error(`笔记 ${path} 已存在，请改用 update_note 提交修改差异`);
    }
    const afterContent = typeof input.content === 'string' ? input.content : '';
    const proposal = normalizeProposal({
      id: makeProposalId(),
      kind,
      status: 'pending',
      path,
      reason,
      beforeContent: '',
      afterContent,
      stats: summarizeDiffStats('', afterContent)
    });
    upsertProposal(store, proposal);
    await saveChanges(ctx, store);
    return proposal;
  }

  if (kind === 'update_note' || kind === 'append_to_note') {
    const path = normalizePath(text(input.path));
    if (!path) {
      throw new Error('缺少笔记路径');
    }
    const ref = await lookupByPath(ctx, path);
    if (!ref) {
      throw new Error(`找不到笔记：${path}`);
    }
    let beforeContent = await ctx.vault.read(ref);
    if (ctx && ctx.editor && typeof ctx.editor.active === 'function') {
      try {
        const liveEd = await ctx.editor.active();
        if (liveEd && liveEd.noteId === ref.id && liveEd.dirty && typeof liveEd.content === 'string') {
          beforeContent = liveEd.content;
        }
      } catch (_error) {}
    }
    const rawContent = typeof input.content === 'string' ? input.content : '';
    const afterContent = kind === 'append_to_note'
      ? (beforeContent.length === 0 || beforeContent.endsWith('\n')
        ? beforeContent + rawContent
        : `${beforeContent}\n${rawContent}`)
      : rawContent;

    const proposal = normalizeProposal({
      id: makeProposalId(),
      kind,
      status: 'pending',
      path: ref.path,
      fileId: ref.id,
      beforeUpdatedAt: Number(ref.mtime || ref.updatedAt) || 0,
      reason,
      beforeContent,
      afterContent,
      stats: summarizeDiffStats(beforeContent, afterContent)
    });
    upsertProposal(store, proposal);
    await saveChanges(ctx, store);
    return proposal;
  }

  if (kind === 'rename_note') {
    const oldPath = normalizePath(text(input.path));
    const newPath = normalizePath(text(input.newPath));
    if (!oldPath || !newPath) {
      throw new Error('重命名需要提供原路径与新路径');
    }
    const ref = await lookupByPath(ctx, oldPath);
    if (!ref) {
      throw new Error(`找不到笔记：${oldPath}`);
    }
    const conflict = await lookupByPath(ctx, newPath);
    if (conflict && conflict.id !== ref.id) {
      throw new Error(`目标路径已存在：${newPath}`);
    }
    const proposal = normalizeProposal({
      id: makeProposalId(),
      kind,
      status: 'pending',
      path: ref.path,
      oldPath: ref.path,
      newPath,
      fileId: ref.id,
      beforeUpdatedAt: Number(ref.mtime || ref.updatedAt) || 0,
      reason,
      beforeContent: ref.path,
      afterContent: newPath,
      stats: { added: 1, removed: 1, changed: ref.path !== newPath }
    });
    upsertProposal(store, proposal);
    await saveChanges(ctx, store);
    return proposal;
  }

  if (kind === 'delete_note') {
    const path = normalizePath(text(input.path));
    if (!path) {
      throw new Error('缺少笔记路径');
    }
    const ref = await lookupByPath(ctx, path);
    if (!ref) {
      throw new Error(`找不到笔记：${path}`);
    }
    const beforeContent = await ctx.vault.read(ref);
    const proposal = normalizeProposal({
      id: makeProposalId(),
      kind,
      status: 'pending',
      path: ref.path,
      fileId: ref.id,
      beforeUpdatedAt: Number(ref.mtime || ref.updatedAt) || 0,
      reason,
      beforeContent,
      afterContent: '',
      stats: summarizeDiffStats(beforeContent, '')
    });
    upsertProposal(store, proposal);
    await saveChanges(ctx, store);
    return proposal;
  }

  if (kind === 'replace_selection' || kind === 'replace_active_editor') {
    const snapshot = await ctx.editor.active();
    if (!snapshot) {
      throw new Error('当前没有活动编辑器，无法生成编辑器修改建议');
    }
    if (snapshot.readOnly) {
      throw new Error('当前处于只读视图，请切换到编辑模式后再请求修改');
    }
    const beforeContent = typeof snapshot.content === 'string' ? snapshot.content : '';
    let notePath = normalizePath(text(input.path));
    if (!notePath && snapshot.noteId) {
      try {
        const ref = await lookupByIdOrPath(ctx, snapshot.noteId, '');
        if (ref && ref.path) {
          notePath = normalizePath(ref.path);
        }
      } catch (_error) {
        notePath = '';
      }
    }

    let afterContent = '';
    let selectionRange = null;
    if (kind === 'replace_selection') {
      const fallbackSel = isObject(input.selection) ? input.selection : snapshot.selection;
      const fromRaw = isObject(fallbackSel) ? Number(fallbackSel.from) : 0;
      const toRaw = isObject(fallbackSel) ? Number(fallbackSel.to) : 0;
      const from = Math.max(0, Math.min(beforeContent.length, Math.floor(fromRaw || 0)));
      const to = Math.max(from, Math.min(beforeContent.length, Math.floor(toRaw || from)));
      if (from === to && !input.allowEmptySelection) {
        throw new Error('当前编辑器未选中文本，无法使用 replace_selection；请改用 update_note 或先在编辑器中选中一段内容');
      }
      const lineRange = lineRangeForOffsets(beforeContent, from, to);
      selectionRange = { from, to, startLine: lineRange.startLine, endLine: lineRange.endLine };
      const replacement = typeof input.content === 'string' ? input.content : '';
      afterContent = beforeContent.slice(0, from) + replacement + beforeContent.slice(to);
    } else {
      afterContent = typeof input.content === 'string' ? input.content : '';
    }

    const proposal = normalizeProposal({
      id: makeProposalId(),
      kind,
      status: 'pending',
      path: notePath || '当前活动编辑器',
      fileId: text(snapshot.noteId),
      beforeRevision: Number(snapshot.revision) || 0,
      selectionRange,
      reason,
      beforeContent,
      afterContent,
      stats: summarizeDiffStats(beforeContent, afterContent)
    });
    upsertProposal(store, proposal);
    await saveChanges(ctx, store);
    return proposal;
  }

  throw new Error(`不支持的变更类型：${kind}`);
}

/** Confirms a pending proposal, verifying conflict freedom and delegating writes to the host. */
async function confirmProposal(ctx, store, id) {
  const proposal = getProposal(store, id);
  if (!proposal) {
    throw new Error('找不到对应的修改建议');
  }
  if (proposal.status !== 'pending') {
    throw new Error('该修改建议已处理，不能重复确认');
  }

  try {
    if (proposal.kind === 'create_note') {
      const existing = await lookupByPath(ctx, proposal.path);
      if (existing) {
        throw new Error(`写入冲突：笔记 ${proposal.path} 已存在`);
      }
      const created = await ctx.vault.create(proposal.path, proposal.afterContent);
      proposal.afterFileId = text(created && created.id);
      proposal.afterUpdatedAt = Number(created && (created.mtime || created.updatedAt)) || Date.now();
    } else if (proposal.kind === 'update_note' || proposal.kind === 'append_to_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.fileId, proposal.path);
      if (!currentRef) {
        throw new Error(`找不到目标笔记：${proposal.path}`);
      }
      let liveEd = null;
      if (ctx && ctx.editor && typeof ctx.editor.active === 'function') {
        try { liveEd = await ctx.editor.active(); } catch (_error) { liveEd = null; }
      }
      const useDirtyEditor = Boolean(liveEd && liveEd.noteId === currentRef.id && liveEd.dirty && typeof liveEd.content === 'string');
      const liveText = useDirtyEditor ? liveEd.content : await ctx.vault.read(currentRef);
      if (liveText !== proposal.beforeContent) {
        throw new Error('写入冲突：原笔记内容在生成建议后已被修改，请拒绝并重新分析');
      }
      let updated = null;
      if (useDirtyEditor && ctx.editor && typeof ctx.editor.replaceAll === 'function') {
        await ctx.editor.replaceAll(proposal.afterContent, liveEd.revision);
        try { updated = await ctx.vault.write(currentRef, proposal.afterContent); } catch (_error) {}
      } else {
        try {
          updated = await ctx.vault.write(currentRef, proposal.afterContent);
        } catch (writeErr) {
          if (liveEd && liveEd.noteId === currentRef.id && ctx.editor && typeof ctx.editor.replaceAll === 'function' && /E_EDITOR_CONFLICT/.test(errorText(writeErr))) {
            await ctx.editor.replaceAll(proposal.afterContent, liveEd.revision);
          } else {
            throw writeErr;
          }
        }
      }
      proposal.fileId = currentRef.id;
      proposal.afterUpdatedAt = Number(updated && (updated.mtime || updated.updatedAt)) || Date.now();
    } else if (proposal.kind === 'rename_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.fileId, proposal.oldPath);
      if (!currentRef || normalizePath(currentRef.path) !== proposal.oldPath) {
        throw new Error(`写入冲突：笔记 ${proposal.oldPath} 当前路径已变化`);
      }
      const occupied = await lookupByPath(ctx, proposal.newPath);
      if (occupied && occupied.id !== currentRef.id) {
        throw new Error(`写入冲突：目标路径 ${proposal.newPath} 已被占用`);
      }
      const renamed = await ctx.vault.rename(currentRef, proposal.newPath);
      proposal.fileId = currentRef.id;
      proposal.afterUpdatedAt = Number(renamed && (renamed.mtime || renamed.updatedAt)) || Date.now();
    } else if (proposal.kind === 'delete_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.fileId, proposal.path);
      if (!currentRef) {
        throw new Error(`找不到目标笔记：${proposal.path}`);
      }
      const liveText = await ctx.vault.read(currentRef);
      if (liveText !== proposal.beforeContent) {
        throw new Error('删除冲突：笔记在生成建议后发生变动，已阻止删除');
      }
      await ctx.vault.delete(currentRef);
      proposal.fileId = currentRef.id;
    } else if (proposal.kind === 'replace_selection' || proposal.kind === 'replace_active_editor') {
      const live = await ctx.editor.active();
      if (!live) {
        throw new Error('当前没有活动编辑器，请先打开对应笔记并保持可编辑状态');
      }
      if (live.readOnly) {
        throw new Error('编辑器处于只读状态，请切换到编辑模式后再确认写入');
      }
      if (proposal.fileId && live.noteId && live.noteId !== proposal.fileId) {
        throw new Error('写入冲突：当前打开的笔记与生成建议时不同，请切回原笔记后再试');
      }
      if (live.content !== proposal.beforeContent) {
        throw new Error('写入冲突：编辑器内容已发生手动变动，已阻止覆盖最新内容');
      }
      await ctx.editor.replaceAll(proposal.afterContent, live.revision);
      proposal.fileId = proposal.fileId || text(live.noteId);
    } else {
      throw new Error(`不支持的变更类型：${proposal.kind}`);
    }

    proposal.status = 'applied';
    proposal.appliedAt = Date.now();
    proposal.lastError = '';
    await saveChanges(ctx, store);
    return proposal;
  } catch (error) {
    proposal.lastError = errorText(error);
    await saveChanges(ctx, store).catch(() => {});
    throw error;
  }
}

/** Rejects a pending proposal so original files remain untouched. */
async function rejectProposal(ctx, store, id) {
  const proposal = getProposal(store, id);
  if (!proposal) {
    throw new Error('找不到对应的修改建议');
  }
  if (proposal.status !== 'pending') {
    throw new Error('该修改建议已处理');
  }
  proposal.status = 'rejected';
  proposal.rejectedAt = Date.now();
  proposal.lastError = '';
  await saveChanges(ctx, store);
  return proposal;
}

/** Undoes a previously confirmed write, guarding against intervening manual edits. */
async function undoProposal(ctx, store, id) {
  const proposal = getProposal(store, id);
  if (!proposal) {
    throw new Error('找不到对应的写入记录');
  }
  if (proposal.status !== 'applied') {
    throw new Error('仅支持撤销已确认写入的变更');
  }

  try {
    if (proposal.kind === 'update_note' || proposal.kind === 'append_to_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.fileId, proposal.path);
      if (!currentRef) {
        throw new Error(`找不到目标笔记：${proposal.path}，无法撤销`);
      }
      const liveText = await ctx.vault.read(currentRef);
      if (liveText !== proposal.afterContent) {
        throw new Error('撤销冲突：该笔记在确认写入后又有新的手动改动，已阻止覆盖后续内容');
      }
      await ctx.vault.write(currentRef, proposal.beforeContent);
    } else if (proposal.kind === 'create_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.afterFileId, proposal.path);
      if (!currentRef) {
        throw new Error(`笔记 ${proposal.path} 已不存在，无需撤销`);
      }
      const liveText = await ctx.vault.read(currentRef);
      if (liveText !== proposal.afterContent) {
        throw new Error('撤销冲突：新建笔记内容已被修改，为防丢失改动无法直接删除');
      }
      await ctx.vault.delete(currentRef);
    } else if (proposal.kind === 'rename_note') {
      const currentRef = await lookupByIdOrPath(ctx, proposal.fileId, proposal.newPath);
      if (!currentRef || normalizePath(currentRef.path) !== proposal.newPath) {
        throw new Error('撤销冲突：笔记当前路径已再次变化，无法撤销重命名');
      }
      const occupied = await lookupByPath(ctx, proposal.oldPath);
      if (occupied && occupied.id !== currentRef.id) {
        throw new Error(`撤销冲突：原路径 ${proposal.oldPath} 已存在其他笔记`);
      }
      await ctx.vault.rename(currentRef, proposal.oldPath);
    } else if (proposal.kind === 'delete_note') {
      const occupied = await lookupByPath(ctx, proposal.path);
      if (occupied) {
        throw new Error(`撤销冲突：路径 ${proposal.path} 已存在同名笔记，无法恢复`);
      }
      const recreated = await ctx.vault.create(proposal.path, proposal.beforeContent);
      proposal.afterFileId = text(recreated && recreated.id);
    } else if (proposal.kind === 'replace_selection' || proposal.kind === 'replace_active_editor') {
      const live = await ctx.editor.active();
      if (!live || live.readOnly) {
        throw new Error('请先打开可编辑的原笔记视图再执行撤销');
      }
      if (proposal.fileId && live.noteId && live.noteId !== proposal.fileId) {
        throw new Error('撤销冲突：当前打开的笔记与原变更不同，请切回对应笔记后再试');
      }
      if (live.content !== proposal.afterContent) {
        throw new Error('撤销冲突：编辑器内容已发生后续修改，已阻止覆盖最新输入');
      }
      await ctx.editor.replaceAll(proposal.beforeContent, live.revision);
    } else {
      throw new Error(`不支持撤销类型：${proposal.kind}`);
    }

    proposal.status = 'undone';
    proposal.undoneAt = Date.now();
    proposal.lastError = '';
    await saveChanges(ctx, store);
    return proposal;
  } catch (error) {
    proposal.lastError = errorText(error);
    await saveChanges(ctx, store).catch(() => {});
    throw error;
  }
}

function describeProposal(proposal) {
  if (!proposal) {
    return { title: '', targetLabel: '', statsLabel: '', diff: null };
  }
  const title = KIND_LABELS[proposal.kind] || '修改建议';
  const targetLabel = proposal.kind === 'rename_note'
    ? `${proposal.oldPath} → ${proposal.newPath}`
    : (proposal.path || basename(proposal.oldPath) || '未命名笔记');
  const rangeNote = proposal.selectionRange && proposal.selectionRange.startLine > 0
    ? `L${proposal.selectionRange.startLine}-L${proposal.selectionRange.endLine} · `
    : '';
  const statsLabel = proposal.kind === 'rename_note'
    ? '重命名'
    : `${rangeNote}+${proposal.stats.added} / -${proposal.stats.removed}`;
  const diff = buildDiffHunks(proposal.beforeContent, proposal.afterContent, {
    contextLines: 2,
    maxLines: 140
  });
  return { title, targetLabel, statsLabel, diff };
}

/** Stages and immediately applies a proposal in one step, recording undo history. */
async function applyProposal(ctx, store, input) {
  const proposal = await stageProposal(ctx, store, input);
  return confirmProposal(ctx, store, proposal.id);
}

module.exports = {
  CHANGES_STORAGE_KEY,
  CHANGES_CHAR_BUDGET,
  KIND_LABELS,
  loadChanges,
  saveChanges,
  getProposal,
  stageProposal,
  confirmProposal,
  applyProposal,
  rejectProposal,
  undoProposal,
  describeProposal
};
