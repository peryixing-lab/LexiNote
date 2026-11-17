import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const require = createRequire(import.meta.url);
const esbuild = require('esbuild');

const tmpWork = mkdtempSync(path.join(os.tmpdir(), 'lexinote-win-discovery-'));

async function compileModule(entryRel, outName) {
  const outfile = path.join(tmpWork, outName);
  await esbuild.build({
    entryPoints: [path.join(rootDir, entryRel)],
    outfile,
    bundle: true,
    platform: 'node',
    format: 'esm',
    target: 'node20',
    external: ['electron']
  });
  return import(pathToFileURL(outfile).href);
}

function makeNote(id, title, content, opts = {}) {
  return {
    id,
    vaultId: opts.vaultId || 'vault-1',
    projectId: '',
    title,
    notebook: opts.notebook || '默认',
    content,
    noteType: 'markdown',
    editorLevel: 'pro',
    tags: opts.tags ? [...opts.tags] : [],
    properties: [],
    pinned: Boolean(opts.pinned),
    favorite: false,
    trashedAt: opts.trashedAt ?? 0,
    createdAt: opts.createdAt ?? 1000,
    updatedAt: opts.updatedAt ?? 2000,
    ...(opts.lastOpenedAt ? { lastOpenedAt: opts.lastOpenedAt } : {}),
    path: ''
  };
}

function makeState(notes, noteAccessedAt) {
  return {
    version: 2,
    vaults: [{ id: 'vault-1', name: '主知识库', description: '', createdAt: 1000, archived: false, favorite: false, folderUri: '', openMode: 'ask' }],
    projects: [],
    notes,
    maps: [],
    canvases: [],
    settings: {
      theme: 'system',
      accent: '#6E44D9',
      paletteMode: 'original',
      language: 'zh-Hans',
      fontSize: 16,
      showRibbon: true,
      sidebarWidth: 260,
      rightSidebarWidth: 280,
      showTabHeaders: true,
      editorLimitWidth: true,
      editorShowTitle: true,
      editorViewStatus: true,
      editorDefaultView: 'live',
      editorDefaultMode: 'live',
      zoom: 100,
      workspacePromptSuppressed: false,
      workspaceDefaultOpenMode: 'current',
      settingsUpdatedAt: 1000,
      lastVaultId: 'vault-1',
      lastNoteId: '',
      hotkeys: {}
    },
    ...(noteAccessedAt ? { noteAccessedAt } : {})
  };
}

try {
  const search = await compileModule('src/renderer/core/search.ts', 'search.mjs');
  const md = await compileModule('src/renderer/core/markdown.ts', 'markdown.mjs');
  const hist = await compileModule('src/main/historyStore.ts', 'historyStore.mjs');
  const ws = await compileModule('src/main/workspaceFs.ts', 'workspaceFs.mjs');

  // 1. Highlight term extraction, multi-term segments, and access/updated/created/title sorting
  const terms = search.extractHighlightTerms('tag:#课程 type:study "线性 矩阵" -排除 -tag:旧 特征值 线性');
  assert.deepEqual(terms, ['线性 矩阵', '特征值', '课程', '线性']);
  const hits = search
    .highlightSegments('复习 特征值 与 线性 矩阵 分解', 'tag:#课程 "线性 矩阵" 特征值')
    .filter((s) => s.hit)
    .map((s) => s.text);
  assert.deepEqual(hits, ['特征值', '线性 矩阵']);

  const nA = makeNote('a', 'Alpha', 'alpha', { createdAt: 100, updatedAt: 500, lastOpenedAt: 900 });
  const nB = makeNote('b', 'Beta', 'beta', { createdAt: 300, updatedAt: 800, lastOpenedAt: 0 });
  const nC = makeNote('c', 'Gamma', 'gamma', { createdAt: 200, updatedAt: 400, lastOpenedAt: 1200 });
  assert.deepEqual(search.sortNotes([nA, nB, nC], 'accessed').map((n) => n.id), ['c', 'a', 'b']);
  assert.deepEqual(search.sortNotes([nA, nB, nC], 'updated').map((n) => n.id), ['b', 'a', 'c']);
  assert.deepEqual(search.sortNotes([nA, nB, nC], 'created').map((n) => n.id), ['b', 'c', 'a']);
  assert.deepEqual(search.sortNotes([nC, nA, nB], 'title').map((n) => n.id), ['a', 'b', 'c']);
  console.log('PASS Windows search highlightTerms/highlightSegments and accessed/updated/created/title sort');

  // 2. Query-anchored snippet extraction and anchor-aware link target preview
  const longNote = makeNote(
    'long',
    '深度学习笔记',
    `${'前置背景资料 '.repeat(36)}\n\n核心锚点：反向传播链式法则与梯度裁剪。`,
    { notebook: 'AI', tags: ['深度学习'], updatedAt: 5000, lastOpenedAt: 6200 }
  );
  const anchoredSnippet = md.extractSnippet(longNote, 'type:study 核心锚点');
  assert.ok(anchoredSnippet.includes('核心锚点'));

  const targetNote = makeNote(
    'target-1',
    '向量空间',
    '# 引言\n基础公理\n\n## 正交投影\n正交基与投影矩阵定义在这里。\n\n## 特征分解\n更多细节。\n\n参考 [[深度学习笔记]]',
    { notebook: '数学', tags: ['线代'], updatedAt: 7000, lastOpenedAt: 8800 }
  );
  const isolatedMention = makeNote('iso-1', '奇异值分解', '建议对照 向量空间 理解左奇异向量。', { tags: ['线代'] });
  const isolatedUnresolved = makeNote('iso-2', '孤立草稿', '未创建链接 [[尚未建立]]', { tags: ['随笔'] });
  const trashedNote = makeNote('trash-1', '回收站笔记', '内容', { trashedAt: 999 });
  const allNotes = [longNote, targetNote, isolatedMention, isolatedUnresolved, trashedNote];
  const links = md.buildNoteLinks(allNotes);

  const preview = md.resolveLinkTargetPreview('向量空间#正交投影', allNotes, links, 'vault-1');
  assert.equal(preview.exists, true);
  assert.equal(preview.noteId, 'target-1');
  assert.equal(preview.anchor, '正交投影');
  assert.ok(preview.snippet.includes('正交基'));
  assert.equal(preview.outgoingCount, 1);
  assert.equal(preview.lastOpenedAt, 8800);

  const missing = md.resolveLinkTargetPreview('尚未建立', allNotes, links, 'vault-1');
  assert.equal(missing.exists, false);
  assert.equal(missing.title, '尚未建立');
  assert.ok(missing.snippet.includes('尚未创建'));
  console.log('PASS Windows snippet anchoring and anchor-aware link target preview (existing + missing)');

  // 3. Unconnected notes detection & candidate suggestions
  const unconnected = md.findUnconnectedNotes(allNotes, links, 'vault-1');
  assert.deepEqual(unconnected.map((n) => n.id), ['iso-1', 'iso-2']);
  assert.equal(md.isNoteUnconnected('iso-1', links), true);
  assert.equal(md.isNoteUnconnected('target-1', links), false);
  const cands = md.suggestLinkCandidatesForNote(isolatedMention, allNotes, links, 4);
  assert.ok(cands.length >= 1);
  assert.equal(cands[0].noteId, 'target-1');
  assert.ok(!cands.some((c) => c.noteId === 'trash-1'));
  console.log('PASS Windows unconnected note detection & link candidate suggestions');

  // 4. Access timestamps merge out-of-band without dirtying note snapshots or .md serialization
  const master = makeState([targetNote, isolatedMention], { 'target-1': 5000 });
  const incoming = makeState([targetNote, isolatedMention], { 'target-1': 9000, 'iso-1': 7500, 'deleted-id': 1111 });
  const mergeRes = hist.mergeWithConflictDetection(
    master,
    incoming,
    true,
    undefined,
    (m) => m,
    (m) => m
  );
  assert.equal(mergeRes.conflicts.length, 0);
  assert.equal(mergeRes.replacedMasterNotes.length, 0);
  assert.deepEqual(mergeRes.merged.noteAccessedAt, { 'target-1': 9000, 'iso-1': 7500 });
  const mdText = ws.serializeNoteMarkdown(targetNote);
  assert.ok(!mdText.includes('lastOpenedAt') && !mdText.includes('noteAccessedAt'));
  console.log('PASS Windows access timestamps merge without note conflicts, history churn, or .md changes');

  // 5. Structural UI integration checks
  const required = [
    ['src/renderer/components/HighlightText.tsx', ['highlightSegments', 'search-hit']],
    ['src/renderer/components/LinkPreviewPopover.tsx', ['resolveLinkTargetPreview', 'link-preview-popover']],
    ['src/renderer/components/Sidebar.tsx', ['HighlightText', 'sidebarSort', 'unconnectedOnly', 'unconnected-dot-badge']],
    ['src/renderer/components/LibraryView.tsx', ['HighlightText', 'setLibrarySort', 'unconnectedOnly', "'accessed'"]],
    ['src/renderer/components/CommandPalette.tsx', ['HighlightText', 'matchesSearch', "'accessed'"]],
    ['src/renderer/components/MarkdownView.tsx', ['LinkPreviewPopover', 'wiki-link missing']],
    ['src/renderer/components/RightSidebar.tsx', ['LinkPreviewPopover', 'suggestLinkCandidatesForNote', 'insertWikiLink']],
    ['src/renderer/components/GraphView.tsx', ['LinkPreviewPopover', 'showUnconnectedOnly', 'unconnectedNotes', 'insertWikiLink']]
  ];
  for (const [rel, needles] of required) {
    const content = readFileSync(path.join(rootDir, rel), 'utf8');
    for (const needle of needles) {
      assert.ok(content.includes(needle), `${rel} should include ${needle}`);
    }
  }
  console.log('PASS Windows UI integration checks');
  console.log('5 Windows discovery-features regression groups passed.');
} finally {
  rmSync(tmpWork, { recursive: true, force: true });
}
