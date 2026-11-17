'use strict';

const assert = require('node:assert/strict');
const { computeLineDiff, buildDiffHunks, summarizeDiffStats, formatDiffText } = require('../src/diff');
const { extractCitations, mergeCitationsWithContext, resolveCitationHref } = require('../src/citations');
const {
  SCOPE_ACTIVE,
  SCOPE_SELECTION,
  SCOPE_NOTES,
  resolveContextScope,
  toContextMeta,
  formatContextForModel,
  lineRangeForOffsets
} = require('../src/context');
const {
  loadChanges,
  getProposal,
  stageProposal,
  confirmProposal,
  rejectProposal,
  undoProposal,
  describeProposal
} = require('../src/changes');
const { executeTool } = require('../src/tools');
const { runTurn } = require('../src/agent');
const { createSession, loadSession } = require('../src/session');
const { normalizePath } = require('../src/util');

function makeEnv(initialFiles = {}, initialEditor = null, initialCaps = null) {
  let seq = 10;
  let ts = 10000;
  const files = new Map();
  const storage = new Map();
  const caps = new Set(initialCaps || [
    'vault.read',
    'vault.write',
    'editor.read',
    'editor.write',
    'workspace.views',
    'ai.inference',
    'ui.commands',
    'ui.views',
    'plugin.storage'
  ]);
  const calls = [];
  const replies = [];
  const aiRequests = [];

  for (const [p, content] of Object.entries(initialFiles)) {
    const norm = normalizePath(p);
    seq += 1;
    ts += 10;
    const id = `n-${seq}`;
    files.set(id, { id, path: norm, name: norm.split('/').pop(), content: String(content), mtime: ts });
  }

  let activeFileId = files.size > 0 ? Array.from(files.keys())[0] : '';
  let editor = initialEditor ? { ...initialEditor } : null;

  function findByPath(rawPath) {
    const norm = normalizePath(rawPath);
    for (const item of files.values()) {
      if (item.path === norm) {
        return item;
      }
    }
    return null;
  }

  function toRef(item) {
    return item
      ? { id: item.id, path: item.path, name: item.name, mtime: item.mtime, updatedAt: item.mtime, size: item.content.length }
      : null;
  }

  function requireCap(cap) {
    if (!caps.has(cap)) {
      const err = new Error(`E_PERMISSION_DENIED: 缺少能力 ${cap}`);
      err.code = 'E_PERMISSION_DENIED';
      throw err;
    }
  }

  function clone(v) {
    return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
  }

  const ctx = {
    vaultId: 'test-vault',
    log() {},
    capabilities: {
      has(cap) { return caps.has(cap); }
    },
    storage: {
      async get(k) { return storage.has(k) ? clone(storage.get(k)) : null; },
      async set(k, v) { storage.set(k, clone(v)); },
      async remove(k) { storage.delete(k); }
    },
    vault: {
      async listMarkdown() {
        requireCap('vault.read');
        return Array.from(files.values()).map(toRef);
      },
      async get(path) {
        requireCap('vault.read');
        return toRef(findByPath(path));
      },
      async read(ref) {
        requireCap('vault.read');
        const id = typeof ref === 'string' ? ref : (ref && ref.id);
        const entry = files.get(id) || findByPath(ref && ref.path);
        if (!entry) { throw new Error(`E_NOT_FOUND: ${id}`); }
        return entry.content;
      },
      async create(path, content) {
        requireCap('vault.write');
        const norm = normalizePath(path);
        if (findByPath(norm)) { throw new Error(`E_PATH_EXISTS: ${norm}`); }
        seq += 1;
        ts += 10;
        const item = { id: `n-${seq}`, path: norm, name: norm.split('/').pop(), content: String(content), mtime: ts };
        files.set(item.id, item);
        return toRef(item);
      },
      async write(ref, content) {
        requireCap('vault.write');
        const entry = files.get(ref && ref.id);
        if (!entry) { throw new Error('E_NOT_FOUND'); }
        ts += 10;
        entry.content = String(content);
        entry.mtime = ts;
        return toRef(entry);
      },
      async rename(ref, newPath) {
        requireCap('vault.write');
        const entry = files.get(ref && ref.id);
        if (!entry) { throw new Error('E_NOT_FOUND'); }
        const norm = normalizePath(newPath);
        if (findByPath(norm)) { throw new Error(`E_PATH_EXISTS: ${norm}`); }
        ts += 10;
        entry.path = norm;
        entry.name = norm.split('/').pop();
        entry.mtime = ts;
        return toRef(entry);
      },
      async delete(ref) {
        requireCap('vault.write');
        const entry = files.get(ref && ref.id);
        if (!entry) { throw new Error('E_NOT_FOUND'); }
        if (activeFileId === entry.id) { activeFileId = ''; }
        files.delete(entry.id);
      }
    },
    workspace: {
      async activeFile() {
        requireCap('workspace.views');
        return toRef(files.get(activeFileId));
      },
      async openFile(ref) {
        requireCap('workspace.views');
        calls.push({ method: 'workspace.openFile', path: ref.path, id: ref.id });
        activeFileId = ref.id;
      }
    },
    editor: {
      async active() {
        requireCap('editor.read');
        return editor ? { ...editor, selection: editor.selection ? { ...editor.selection } : { from: 0, to: 0 } } : null;
      },
      async replaceAll(content, expectedRevision) {
        requireCap('editor.write');
        if (!editor) { throw new Error('E_EDITOR_READONLY: 无活动编辑器'); }
        if (editor.readOnly) { throw new Error('E_EDITOR_READONLY: 当前处于只读模式'); }
        if (typeof expectedRevision === 'number' && expectedRevision !== editor.revision) {
          throw new Error('E_CONFLICT: 编辑器版本已变化');
        }
        editor = {
          ...editor,
          content: String(content),
          revision: (editor.revision || 0) + 1,
          dirty: true
        };
        return { ...editor };
      }
    },
    ai: {
      async chat(req) {
        requireCap('ai.inference');
        aiRequests.push(clone(req));
        return replies.shift() || { text: '', reasoning: '', toolCalls: [] };
      }
    },
    mindmap: {
      _items: [],
      async list() {
        requireCap('vault.read');
        return clone(this._items);
      },
      async get(q) {
        requireCap('vault.read');
        const id = q && q.id;
        const title = q && q.title;
        return clone(this._items.find((m) => (id && m.id === id) || (title && m.title === title)) || null);
      },
      async create(opts) {
        requireCap('vault.write');
        const doc = {
          id: `mm-${this._items.length + 1}`,
          title: opts.title || '新建思维导图',
          layoutKind: opts.layoutKind || 'right',
          nodes: Array.isArray(opts.nodes) && opts.nodes.length > 0
            ? clone(opts.nodes)
            : [{ id: 'root', parentId: '', text: opts.title || '核心主题' }, { id: 'n1', parentId: 'root', text: '分支 1' }]
        };
        this._items.push(doc);
        return clone(doc);
      },
      async update(opts) {
        requireCap('vault.write');
        const doc = this._items.find((m) => m.id === opts.id);
        if (!doc) { throw new Error('E_NOT_FOUND'); }
        if (opts.title) { doc.title = opts.title; }
        if (opts.layoutKind) { doc.layoutKind = opts.layoutKind; }
        if (Array.isArray(opts.nodes)) { doc.nodes = clone(opts.nodes); }
        return clone(doc);
      },
      async delete(id) {
        requireCap('vault.write');
        this._items = this._items.filter((m) => m.id !== id);
        return true;
      },
      async open(id) {
        requireCap('workspace.views');
        calls.push({ method: 'mindmap.open', id });
        return true;
      }
    },
    canvas: {
      _items: [],
      async list() {
        requireCap('vault.read');
        return clone(this._items);
      },
      async get(q) {
        requireCap('vault.read');
        const id = q && q.id;
        const title = q && q.title;
        return clone(this._items.find((c) => (id && c.id === id) || (title && c.title === title)) || null);
      },
      async create(opts) {
        requireCap('vault.write');
        const board = {
          id: `cv-${this._items.length + 1}`,
          title: opts.title || '新建自由白板',
          cards: Array.isArray(opts.cards) ? clone(opts.cards) : [],
          edges: Array.isArray(opts.edges) ? clone(opts.edges) : []
        };
        this._items.push(board);
        return clone(board);
      },
      async update(opts) {
        requireCap('vault.write');
        const board = this._items.find((c) => c.id === opts.id);
        if (!board) { throw new Error('E_NOT_FOUND'); }
        if (opts.title) { board.title = opts.title; }
        if (Array.isArray(opts.cards)) { board.cards = clone(opts.cards); }
        if (Array.isArray(opts.edges)) { board.edges = clone(opts.edges); }
        return clone(board);
      },
      async delete(id) {
        requireCap('vault.write');
        this._items = this._items.filter((c) => c.id !== id);
        return true;
      },
      async open(id) {
        requireCap('workspace.views');
        calls.push({ method: 'canvas.open', id });
        return true;
      }
    },
    appSettings: {
      _state: {
        theme: 'system',
        language: 'zh-Hans',
        defaultTier: 'simple',
        vaultViewMode: 'list',
        graphShowTags: false,
        workspaceOpenMode: 'ask',
        appearance: { accent: '#6C5CE7', fontSize: 16, quickZoom: false },
        editor: { defaultView: 'edit', defaultMode: 'live', showTitle: true, limitWidth: true, viewStatus: true, spellcheck: false },
        interface: { tabHeaders: true, showRibbon: true, zoom: 100, sidebarWidth: 244, rightSidebarWidth: 280 }
      },
      async get() {
        return clone(this._state);
      },
      async set(patch) {
        requireCap('ui.commands');
        if (patch.theme) { this._state.theme = patch.theme; }
        if (patch.language) { this._state.language = patch.language; }
        if (patch.accent) { this._state.appearance.accent = patch.accent; }
        if (typeof patch.fontSize === 'number') { this._state.appearance.fontSize = patch.fontSize; }
        if (typeof patch.editorLimitWidth === 'boolean') { this._state.editor.limitWidth = patch.editorLimitWidth; }
        if (typeof patch.interfaceZoom === 'number') { this._state.interface.zoom = patch.interfaceZoom; }
        return clone(this._state);
      }
    },
    commands: {
      async listHost() {
        return [{ id: 'daily', title: '打开今日笔记' }, { id: 'dark', title: '使用深色外观' }];
      },
      async executeHost(payload) {
        requireCap('ui.commands');
        calls.push({ method: 'commands.executeHost', id: payload.id, title: payload.title });
        return { ok: true, id: payload.id, title: payload.title || payload.id };
      }
    }
  };

  return {
    ctx,
    caps,
    calls,
    replies,
    aiRequests,
    getFile: (p) => findByPath(p),
    setEditor: (next) => { editor = next; },
    setActivePath: (p) => { const f = findByPath(p); activeFileId = f ? f.id : ''; },
    getEditor: () => editor
  };
}

async function testDiffModule() {
  const ops = computeLineDiff('第一行\n旧第二行\n第三行', '第一行\n新第二行\n追加行\n第三行');
  assert.equal(ops.some((o) => o.type === 'remove' && o.text === '旧第二行'), true);
  assert.equal(ops.some((o) => o.type === 'add' && o.text === '新第二行'), true);
  assert.equal(ops.some((o) => o.type === 'add' && o.text === '追加行'), true);

  const stats = summarizeDiffStats('a\nb', 'a\nc\nd');
  assert.deepEqual(stats, { changed: true, added: 2, removed: 1 });
  assert.deepEqual(summarizeDiffStats('same', 'same'), { changed: false, added: 0, removed: 0 });

  const hunks = buildDiffHunks('L1\nL2\nL3', 'L1\nL2-edit\nL3');
  assert.equal(hunks.changed, true);
  assert.equal(hunks.hunks.length, 1);
  const formatted = formatDiffText('L1\nL2', 'L1\nL2-edit');
  assert.ok(formatted.includes('-L2'));
  assert.ok(formatted.includes('+L2-edit'));
}

async function testCitationsModule() {
  const workspaceFiles = [
    { id: '1', path: '课程/矩阵.md', name: '矩阵.md' },
    { id: '2', path: '待办/本周计划.md', name: '本周计划.md' },
    { id: '3', path: 'A/同名.md', name: '同名.md' },
    { id: '4', path: 'B/同名.md', name: '同名.md' }
  ];
  const answer = [
    '根据 [矩阵](课程/矩阵.md#L2-L5) 与 [[本周计划|本周待办]] 的记录，',
    '忽略虚构的 [不存在](ghost/missing.md) 和歧义双链 [[同名]]，精确路径 [B同名](B/同名.md) 保留。'
  ].join('');
  const cited = extractCitations(answer, [{ id: '1', path: '课程/矩阵.md', name: '矩阵' }], workspaceFiles);
  assert.equal(cited.length, 3);
  assert.deepEqual(cited.map((c) => c.path), ['课程/矩阵.md', 'B/同名.md', '待办/本周计划.md']);
  assert.equal(cited[0].fragment, 'L2-L5');
  assert.equal(cited[0].inContext, true);
  assert.equal(cited[2].source, 'cited');

  const resolved = resolveCitationHref('wiki:本周计划', [], workspaceFiles);
  assert.equal(resolved.note.path, '待办/本周计划.md');
  assert.equal(resolveCitationHref('https://example.com', [], workspaceFiles), null);

  const fallback = mergeCitationsWithContext([], [{ id: '1', path: '课程/矩阵.md', name: '矩阵', fragment: 'L1-L2' }]);
  assert.equal(fallback.length, 1);
  assert.equal(fallback[0].source, 'context');
}

async function testContextScopes() {
  const env = makeEnv({
    'notes/alpha.md': '# Alpha\n第一行\n😀高亮词 结束\n最后一行',
    'notes/beta.md': '# Beta\n关联内容'
  });
  const alpha = env.getFile('notes/alpha.md');
  const beta = env.getFile('notes/beta.md');
  env.setActivePath('notes/alpha.md');

  // 1. Active scope prefers unsaved live editor content over disk
  env.setEditor({
    noteId: alpha.id,
    content: '# Alpha\n第一行（未保存编辑）\n😀高亮词 结束\n最后一行',
    revision: 3,
    dirty: true,
    readOnly: false,
    selection: { from: 0, to: 0 }
  });
  const activeCtx = await resolveContextScope(env.ctx, { scope: SCOPE_ACTIVE });
  assert.equal(activeCtx.ok, true);
  assert.equal(activeCtx.notes[0].dirty, true);
  assert.ok(activeCtx.notes[0].content.includes('未保存编辑'));
  assert.ok(formatContextForModel(activeCtx).includes('[上下文范围: 当前笔记]'));

  // 2. Selection scope computes exact UTF-16 slice (with emoji) and 1-based line numbers
  const liveContent = env.getEditor().content;
  const startOffset = liveContent.indexOf('😀高亮词');
  const endOffset = startOffset + '😀高亮词'.length;
  env.setEditor({
    noteId: alpha.id,
    content: liveContent,
    revision: 4,
    dirty: true,
    readOnly: false,
    selection: { from: startOffset, to: endOffset }
  });
  const selCtx = await resolveContextScope(env.ctx, { scope: SCOPE_SELECTION });
  assert.equal(selCtx.ok, true);
  assert.equal(selCtx.notes[0].selectedText, '😀高亮词');
  assert.equal(selCtx.notes[0].startLine, 3);
  assert.equal(selCtx.notes[0].endLine, 3);
  assert.equal(selCtx.notes[0].fragment, 'L3');
  const lrMulti = lineRangeForOffsets('a\nb\nc\nd', 2, 5);
  assert.deepEqual(lrMulti, { startLine: 2, endLine: 3 });
  assert.ok(formatContextForModel(selCtx).includes('replace_selection'));

  // Empty selection refuses cleanly
  env.setEditor({ noteId: alpha.id, content: liveContent, revision: 4, selection: { from: 2, to: 2 } });
  const emptySel = await resolveContextScope(env.ctx, { scope: SCOPE_SELECTION });
  assert.equal(emptySel.ok, false);
  assert.equal(emptySel.code, 'EMPTY_SELECTION');

  // Revoked editor.read produces E_PERMISSION_DENIED
  env.caps.delete('editor.read');
  const deniedSel = await resolveContextScope(env.ctx, { scope: SCOPE_SELECTION });
  assert.equal(deniedSel.ok, false);
  assert.equal(deniedSel.code, 'E_PERMISSION_DENIED');
  env.caps.add('editor.read');

  // 3. Notes collection scope gathers multi-note content + compact toContextMeta
  const colCtx = await resolveContextScope(env.ctx, {
    scope: SCOPE_NOTES,
    selectedNoteIds: [alpha.id, beta.id]
  });
  assert.equal(colCtx.ok, true);
  assert.equal(colCtx.notes.length, 2);
  assert.ok(formatContextForModel(colCtx).includes('notes/alpha.md'));
  assert.ok(formatContextForModel(colCtx).includes('notes/beta.md'));
  const meta = toContextMeta(colCtx);
  assert.equal(meta.scope, SCOPE_NOTES);
  assert.equal(meta.refs.length, 2);
  assert.equal('content' in meta.refs[0], false);
}

async function testAllSevenProposalsLifecycleAndConflicts() {
  const originalDoc = '第一行：引言\n第二行：旧表述\n第三行：结论';
  const env = makeEnv({ 'docs/guide.md': originalDoc, 'docs/old.md': '# 待改名' });
  const guide = env.getFile('docs/guide.md');
  env.setActivePath('docs/guide.md');
  env.setEditor({
    noteId: guide.id,
    content: originalDoc,
    revision: 10,
    dirty: false,
    readOnly: false,
    selection: {
      from: originalDoc.indexOf('旧表述'),
      to: originalDoc.indexOf('旧表述') + '旧表述'.length
    }
  });

  const store = await loadChanges(env.ctx);
  const staged = [];
  const toolHooks = {
    stageOnly: true,
    changesStore: store,
    recordNote() {},
    onProposal: (p) => staged.push(p)
  };
  const session = createSession();

  // Stage all 7 mutation tools via executeTool and assert ZERO writes happened yet
  const rCreate = await executeTool(env.ctx, session, 'create_note', { path: 'docs/new.md', content: '# 新笔记\n正文' }, toolHooks);
  assert.equal(rCreate.isError, false);
  assert.equal(env.getFile('docs/new.md'), null, 'create_note must not write before confirmation');

  const rUpdate = await executeTool(env.ctx, session, 'update_note', { path: 'docs/guide.md', find: '旧表述', replace: '新表述' }, toolHooks);
  assert.equal(rUpdate.isError, false);
  assert.equal(env.getFile('docs/guide.md').content, originalDoc, 'update_note must not overwrite before confirmation');

  const rAppend = await executeTool(env.ctx, session, 'append_to_note', { path: 'docs/guide.md', markdown: '- 新增条目' }, toolHooks);
  assert.equal(rAppend.isError, false);
  assert.equal(env.getFile('docs/guide.md').content, originalDoc);

  const rRename = await executeTool(env.ctx, session, 'rename_note', { path: 'docs/old.md', newPath: 'docs/renamed.md' }, toolHooks);
  assert.equal(rRename.isError, false);
  assert.ok(env.getFile('docs/old.md'));
  assert.equal(env.getFile('docs/renamed.md'), null);

  const rDelete = await executeTool(env.ctx, session, 'delete_note', { path: 'docs/old.md', reason: '清理示例' }, toolHooks);
  assert.equal(rDelete.isError, false);
  assert.ok(env.getFile('docs/old.md'));

  const rSel = await executeTool(env.ctx, session, 'replace_selection', { content: '精准新选区' }, toolHooks);
  assert.equal(rSel.isError, false);
  assert.equal(env.getEditor().content, originalDoc, 'replace_selection must not mutate editor before confirmation');

  const rFullEd = await executeTool(env.ctx, session, 'replace_active_editor', { text: '# 全文改写\n全新内容' }, toolHooks);
  assert.equal(rFullEd.isError, false);
  assert.equal(env.getEditor().content, originalDoc);

  assert.equal(staged.length, 7);
  const [pCreate, pUpdate, pAppend, pRename, pDelete, pSel, pFullEd] = staged;
  assert.equal(describeProposal(pSel).statsLabel.includes('L2-L2'), true);

  // Confirm & Undo: create_note
  await confirmProposal(env.ctx, store, pCreate.id);
  assert.equal(env.getFile('docs/new.md').content, '# 新笔记\n正文');
  await undoProposal(env.ctx, store, pCreate.id);
  assert.equal(env.getFile('docs/new.md'), null);

  // Confirm & Undo: update_note (note: pAppend has stale beforeUpdatedAt because we haven't confirmed update yet)
  await confirmProposal(env.ctx, store, pUpdate.id);
  assert.ok(env.getFile('docs/guide.md').content.includes('新表述'));

  // Stale proposal pAppend sees updated mtime -> confirm conflict must fail without overwriting!
  await assert.rejects(confirmProposal(env.ctx, store, pAppend.id), /写入冲突/);
  assert.equal(getProposal(store, pAppend.id).status, 'pending');
  assert.ok(env.getFile('docs/guide.md').content.includes('新表述'));

  // Post-confirm edit causes undo conflict on pUpdate
  await env.ctx.vault.write(guide, `${env.getFile('docs/guide.md').content}\n手动补充`);
  await assert.rejects(undoProposal(env.ctx, store, pUpdate.id), /撤销冲突/);
  await rejectProposal(env.ctx, store, pAppend.id);
  assert.equal(getProposal(store, pAppend.id).status, 'rejected');

  // Fresh append_to_note confirm & clean undo
  const freshAppend = await stageProposal(env.ctx, store, { kind: 'append_to_note', path: 'docs/guide.md', content: '尾部补充' });
  const beforeAppend = env.getFile('docs/guide.md').content;
  await confirmProposal(env.ctx, store, freshAppend.id);
  assert.ok(env.getFile('docs/guide.md').content.endsWith('尾部补充'));
  await undoProposal(env.ctx, store, freshAppend.id);
  assert.equal(env.getFile('docs/guide.md').content, beforeAppend);

  // Rename confirm & undo
  await confirmProposal(env.ctx, store, pRename.id);
  assert.ok(env.getFile('docs/renamed.md'));
  assert.equal(env.getFile('docs/old.md'), null);
  await undoProposal(env.ctx, store, pRename.id);
  assert.ok(env.getFile('docs/old.md'));

  // Delete confirm & undo (after rename undone, file still has original fileId/mtime!)
  await confirmProposal(env.ctx, store, pDelete.id);
  assert.equal(env.getFile('docs/old.md'), null);
  await undoProposal(env.ctx, store, pDelete.id);
  assert.equal(env.getFile('docs/old.md').content, '# 待改名');

  // Selection replace confirm & undo
  await confirmProposal(env.ctx, store, pSel.id);
  assert.equal(env.getEditor().content, '第一行：引言\n第二行：精准新选区\n第三行：结论');
  // Conflict check on pFullEd (staged against rev 10, now editor is rev 11)
  await assert.rejects(confirmProposal(env.ctx, store, pFullEd.id), /写入冲突/);
  await undoProposal(env.ctx, store, pSel.id);
  assert.equal(env.getEditor().content, originalDoc);

  // Permission boundary: host revoking vault.write / editor.write stops both stage and late confirm
  const lateStage = await stageProposal(env.ctx, store, { kind: 'update_note', path: 'docs/old.md', content: '# 越权修改' });
  env.caps.delete('vault.write');
  const blockedTool = await executeTool(env.ctx, session, 'update_note', { path: 'docs/old.md', content: 'blocked' }, toolHooks);
  assert.equal(blockedTool.isError, true);
  assert.ok(blockedTool.text.includes('E_PERMISSION_DENIED'));
  await assert.rejects(confirmProposal(env.ctx, store, lateStage.id), /E_PERMISSION_DENIED/);
  assert.equal(env.getFile('docs/old.md').content, '# 待改名');
  env.caps.add('vault.write');

  env.caps.delete('editor.write');
  const blockedEdTool = await executeTool(env.ctx, session, 'replace_selection', { content: 'blocked' }, toolHooks);
  assert.equal(blockedEdTool.isError, true);
  assert.ok(blockedEdTool.text.includes('E_PERMISSION_DENIED'));
}

async function testAgentTurnWithContextAndCitations() {
  const original = '# 知识库总览\n\n这里有旧内容。';
  const env = makeEnv({ 'overview.md': original });
  const file = env.getFile('overview.md');
  env.setActivePath('overview.md');
  const contextResult = await resolveContextScope(env.ctx, { scope: SCOPE_ACTIVE });
  const store = await loadChanges(env.ctx);
  const session = createSession();

  env.replies.push({
    text: '',
    reasoning: '准备建议修改 overview.md',
    toolCalls: [
      { id: 'c1', name: 'update_note', arguments: JSON.stringify({ path: 'overview.md', find: '旧内容', replace: '重构后的内容' }) }
    ]
  });
  env.replies.push({
    text: '我已阅读 [知识库总览](overview.md#L1-L3)，请确认下方的 Diff 修改卡片。',
    reasoning: '',
    toolCalls: []
  });

  await runTurn(env.ctx, session, '请优化这篇笔记的措辞', {
    contextResult,
    changesStore: store
  });

  // 1. Note is directly updated by runTurn and recorded as an undoable proposal
  assert.ok(env.getFile('overview.md').content.includes('重构后的内容'));
  // 2. Model request carried formatted scoped context, persisted session kept lightweight contextMeta only
  const firstUserSent = env.aiRequests[0].messages.find((m) => m.role === 'user').content;
  assert.ok(firstUserSent.includes('[上下文范围: 当前笔记]'));
  const reloaded = await loadSession(env.ctx);
  const persistedUser = reloaded.messages.find((m) => m.role === 'user');
  assert.equal(persistedUser.content, '请优化这篇笔记的措辞');
  assert.equal(persistedUser.contextMeta.scope, SCOPE_ACTIVE);
  assert.equal(persistedUser.contextMeta.refs[0].path, 'overview.md');
  // 3. Assistant carries verified citation and proposalId
  const lastAssistant = reloaded.messages.filter((m) => m.role === 'assistant').pop();
  assert.equal(lastAssistant.citations.length, 1);
  assert.equal(lastAssistant.citations[0].path, 'overview.md');
  assert.equal(lastAssistant.citations[0].fragment, 'L1-L3');
  assert.equal(lastAssistant.proposalIds.length, 1);

  // Undo via store after reload restores original content
  const pid = lastAssistant.proposalIds[0];
  assert.equal(getProposal(store, pid).status, 'applied');
  await undoProposal(env.ctx, store, pid);
  assert.equal(env.getFile('overview.md').content, original);
}

async function testFullSoftwareCapabilitiesTools() {
  const env = makeEnv({});
  const session = createSession();

  // 1. Direct note creation & opening
  const cNote = await executeTool(env.ctx, session, 'create_note', { path: '工作/今日计划', content: '# 今日计划\n- 完成插件升级' });
  assert.equal(cNote.isError, false);
  assert.equal(env.getFile('工作/今日计划.md').content, '# 今日计划\n- 完成插件升级');

  // 2. Mind map creation, listing, reading, updating, opening, deleting
  const cMap = await executeTool(env.ctx, session, 'create_mindmap', {
    title: '系统架构导图',
    layoutKind: 'both',
    markdown: '# 系统架构\n## 插件层\n## 宿主层'
  });
  assert.equal(cMap.isError, false);
  assert.ok(cMap.text.includes('系统架构导图'));

  const lMap = await executeTool(env.ctx, session, 'list_mindmaps', {});
  assert.equal(lMap.isError, false);
  assert.ok(lMap.text.includes('系统架构导图'));

  const uMap = await executeTool(env.ctx, session, 'update_mindmap', {
    title: '系统架构导图',
    newTitle: '知萤架构全景图',
    layoutKind: 'down'
  });
  assert.equal(uMap.isError, false);
  assert.ok(uMap.text.includes('知萤架构全景图'));

  const oMap = await executeTool(env.ctx, session, 'open_mindmap', { title: '知萤架构全景图' });
  assert.equal(oMap.isError, false);
  assert.ok(env.calls.some((c) => c.method === 'mindmap.open'));

  const dMap = await executeTool(env.ctx, session, 'delete_mindmap', { title: '知萤架构全景图' });
  assert.equal(dMap.isError, false);

  // 3. Canvas creation, reading, updating, opening, deleting
  const cCanvas = await executeTool(env.ctx, session, 'create_canvas', {
    title: '头脑风暴白板',
    cards: [{ id: 'c1', title: '目标', body: '全能力调用' }, { id: 'c2', title: '落地方案', body: 'RPC 扩展' }],
    edges: [{ fromCardId: 'c1', toCardId: 'c2', label: '推演' }]
  });
  assert.equal(cCanvas.isError, false);
  assert.ok(cCanvas.text.includes('头脑风暴白板'));

  const rCanvas = await executeTool(env.ctx, session, 'read_canvas', { title: '头脑风暴白板' });
  assert.equal(rCanvas.isError, false);
  assert.ok(rCanvas.text.includes('全能力调用'));

  // 4. App settings reading & updating + host commands
  const gSet = await executeTool(env.ctx, session, 'get_app_settings', {});
  assert.equal(gSet.isError, false);
  assert.ok(gSet.text.includes('system'));

  const uSet = await executeTool(env.ctx, session, 'update_app_settings', {
    theme: '深色',
    fontSize: 20,
    interfaceZoom: 115,
    editorLimitWidth: false
  });
  assert.equal(uSet.isError, false);
  assert.equal(env.ctx.appSettings._state.theme, 'dark');
  assert.equal(env.ctx.appSettings._state.appearance.fontSize, 20);
  assert.equal(env.ctx.appSettings._state.interface.zoom, 115);
  assert.equal(env.ctx.appSettings._state.editor.limitWidth, false);

  const rCmd = await executeTool(env.ctx, session, 'run_app_command', { id: 'daily' });
  assert.equal(rCmd.isError, false);
  assert.ok(env.calls.some((c) => c.method === 'commands.executeHost' && c.id === 'daily'));
}

(async () => {
  await testDiffModule();
  await testCitationsModule();
  await testContextScopes();
  await testAllSevenProposalsLifecycleAndConflicts();
  await testAgentTurnWithContextAndCitations();
  await testFullSoftwareCapabilitiesTools();
  console.log('PASS diff-changes: diff hunks, citations, context scopes, direct & staged tools, mindmap/canvas/settings/commands and capability boundaries');
})();
