const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

const coreDir = path.resolve(__dirname, '../../entry/src/main/ets/core');
const etsRoot = path.resolve(__dirname, '../../entry/src/main/ets');

let noteRows, contentRows, linkRows, nativeLocks;
let files, values, handles, directories, symlinks, persistentGrants, prefs;
let appStorage, fixedUuids;

global.AppStorage = {
  get: (key) => appStorage.get(key),
  setOrCreate(key, value) { appStorage.set(key, value); }
};
global.canIUse = () => true;

const fakePicker = {
  DocumentSelectMode: { FOLDER: 1 },
  DocumentSelectOptions: class {},
  DocumentPickerMode: { DOWNLOAD: 1 },
  DocumentSaveOptions: class {},
  DocumentViewPicker: class { async select() { return []; } async save() { return []; } }
};

function fileStat(p) {
  if (!files.has(p) && !directories.has(p) && !symlinks.has(p)) {
    throw Object.assign(new Error('ENOENT ' + p), { code: 'ENOENT' });
  }
  return {
    size: Buffer.byteLength(files.get(p) || ''),
    mtime: Math.floor(Date.now() / 1000),
    isDirectory: () => directories.has(p),
    isFile: () => files.has(p) && !symlinks.has(p),
    isSymbolicLink: () => symlinks.has(p)
  };
}

class FakeFileUri {
  constructor(uri) { this.path = uri.startsWith('file:') ? decodeURIComponent(new URL(uri).pathname) : uri; }
}

const fakeFileShare = {
  OperationMode: { READ_MODE: 1, WRITE_MODE: 2, CREATE_MODE: 4, DELETE_MODE: 8, RENAME_MODE: 16 },
  async persistPermission(policies) { for (const p of policies) persistentGrants.add(p.uri); },
  async activatePermission() {}
};

const fakeFs = {
  accessSync: (p) => files.has(p) || directories.has(p) || symlinks.has(p),
  mkdirSync(p) {
    const parts = p.split('/');
    for (let i = 1; i <= parts.length; i++) directories.add(parts.slice(0, i).join('/') || '/');
  },
  async mkdir(p) { fakeFs.mkdirSync(p); },
  stat: async (p) => fileStat(p),
  lstat: async (p) => fileStat(p),
  statSync: fileStat,
  lstatSync: fileStat,
  readText: async (p) => files.get(p),
  async listFile(p) {
    return [...new Set([...files.keys(), ...directories, ...symlinks.keys()]
      .filter((x) => x.startsWith(p + '/') && x !== p)
      .map((x) => x.slice(p.length + 1).split('/')[0]))];
  },
  openSync(p) {
    const fd = handles.size + 1;
    handles.set(fd, p);
    if (!p.endsWith('/lexinote-mutation.lock')) files.set(p, '');
    return {
      fd,
      tryLock() {
        if (nativeLocks.has(p)) throw Object.assign(new Error('busy'), { code: 13900034 });
        nativeLocks.set(p, fd);
      },
      unlock() {
        assert.equal(nativeLocks.get(p), fd);
        nativeLocks.delete(p);
      }
    };
  },
  writeSync(fd, text) {
    const p = handles.get(fd);
    files.set(p, text);
    return Buffer.byteLength(text);
  },
  fsyncSync() {},
  closeSync(file) {
    const p = handles.get(file.fd);
    if (nativeLocks.get(p) === file.fd) nativeLocks.delete(p);
  },
  readTextSync: (p) => files.get(p),
  renameSync(from, to) {
    files.set(to, files.get(from));
    files.delete(from);
  },
  unlinkSync(p) { files.delete(p); },
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4, READ_WRITE: 8 }
};

const db = {
  async querySql(sql, args = []) {
    let data = [];
    if (sql.includes('FROM notes_meta')) {
      data = [...noteRows.values()]
        .filter((row) => sql.includes('notes_meta.id = ?') ? row.id === args[0] : sql.includes('vault_id = ?') ? row.vault_id === args[0] : true)
        .map((row) => [row.metadata_json, contentRows.get(row.id)?.content || '']);
    } else {
      const val = values.get(args[0]);
      if (val !== undefined) data = [[val]];
    }
    let cursor = -1;
    return {
      goToFirstRow: () => { cursor = 0; return data.length > 0; },
      goToNextRow: () => ++cursor < data.length,
      getString: (i) => data[cursor][i],
      close() {}
    };
  },
  async insert(table, row) {
    if (table === 'kv_store') values.set(row.key, row.value);
    else if (table === 'notes_meta') noteRows.set(row.id, structuredClone(row));
    else if (table === 'notes_content') contentRows.set(row.id, structuredClone(row));
    else if (table === 'link_index') linkRows.push(structuredClone(row));
  },
  async executeSql(sql, args = []) {
    if (sql === 'DELETE FROM notes_meta') noteRows.clear();
    else if (sql === 'DELETE FROM notes_content') contentRows.clear();
    else if (sql === 'DELETE FROM link_index') linkRows = [];
    else if (sql === 'DELETE FROM link_index WHERE source_id = ?') linkRows = linkRows.filter((r) => r.source_id !== args[0]);
    else if (sql === 'DELETE FROM kv_store WHERE key = ?') values.delete(args[0]);
  },
  async beginTransaction() {},
  async commit() {},
  async rollBack() {}
};

const cache = new Map();
function load(name, memo = cache) {
  if (memo.has(name)) return memo.get(name);
  const filename = path.join(coreDir, name + '.ets');
  const source = fs.readFileSync(filename, 'utf8').replace(/^@Concurrent\s*$/gm, '');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const mod = { exports: {} };
  memo.set(name, mod.exports);
  const req = (spec) => {
    if (spec.startsWith('./')) return load(spec.slice(2), memo);
    if (spec === '@kit.CoreFileKit') {
      return {
        fileIo: fakeFs,
        picker: fakePicker,
        fileShare: fakeFileShare,
        Environment: { getUserDocumentDir: () => '/user/Documents' },
        fileUri: { FileUri: FakeFileUri, getUriFromPath: (p) => 'file://docs' + p }
      };
    }
    if (spec === '@kit.ArkData') {
      return {
        relationalStore: { ConflictResolution: { ON_CONFLICT_REPLACE: 1 }, SecurityLevel: { S2: 2 }, getRdbStore: async () => db },
        preferences: { removePreferencesFromCacheSync() {}, getPreferences: async () => S.settings }
      };
    }
    if (spec === '@kit.ArkTS') return { taskpool: {}, util: { generateRandomUUID: () => (fixedUuids.length ? fixedUuids.shift() : crypto.randomUUID()) } };
    if (spec === '@kit.AbilityKit') return {};
    if (spec === '@kit.BasicServicesKit') return { pasteboard: {}, deviceInfo: { get deviceType() { return '2in1'; } } };
    if (spec === '@kit.FormKit') return { formBindingData: { createFormBindingData: (d) => d }, formProvider: { getPublishedRunningFormInfos: async () => [] } };
    if (spec === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {}, info() {}, error() {} } };
    throw new Error('Unexpected import: ' + spec);
  };
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename })(req, mod, mod.exports);
  return mod.exports;
}

const { NoteItem, NoteLink } = load('LexiModels');
const { LexiSearch } = load('LexiSearch');
const { MarkdownEngine } = load('MarkdownEngine');
const { LexiRelations } = load('LexiRelations');
const { LexiStorageService: S } = load('LexiStorageService');

const context = { filesDir: '/sandbox/files', getApplicationContext() { return this; } };

function resetStorage() {
  nativeLocks = new Map();
  noteRows = new Map();
  contentRows = new Map();
  linkRows = [];
  files = new Map();
  values = new Map();
  handles = new Map();
  directories = new Set();
  symlinks = new Set();
  persistentGrants = new Set();
  prefs = new Map();
  appStorage = new Map();
  fixedUuids = [];
  S.initPromise = undefined;
  S.notesIndexReady = false;
  S.store = db;
  S.writeQueue = Promise.resolve();
  S.mutationQueue = Promise.resolve();
  S.templateQueue = Promise.resolve();
  S.appContext = context;
  S.settings = {
    get: async (k, fb) => (prefs.has(k) ? prefs.get(k) : fb),
    put: async (k, v) => prefs.set(k, v),
    flush: async () => {}
  };
}

function makeNote(id, title, content, opts = {}) {
  const n = new NoteItem();
  n.id = id;
  n.vaultId = opts.vaultId || 'default-vault';
  n.title = title;
  n.content = content;
  n.notebook = opts.notebook || '默认笔记本';
  n.tags = opts.tags || [];
  n.createdAt = opts.createdAt ?? 1000;
  n.updatedAt = opts.updatedAt ?? 2000;
  n.lastOpenedAt = opts.lastOpenedAt ?? 0;
  n.trashedAt = opts.trashedAt ?? 0;
  return n;
}

function makeLink(sourceId, targetId, targetTitle = '') {
  const l = new NoteLink();
  l.sourceId = sourceId;
  l.targetId = targetId;
  l.targetTitle = targetTitle;
  return l;
}

(async () => {
  // 1. Search highlight terms, segments, and sorting including recently accessed
  const terms = LexiSearch.highlightTerms('tag:#课程 type:study "线性 矩阵" -排除 -tag:旧 特征值 线性');
  assert.deepEqual(terms, ['线性 矩阵', '特征值', '课程', '线性']);
  assert.ok(!terms.includes('study') && !terms.includes('排除') && !terms.includes('旧'));
  const segs = LexiSearch.highlightSegments('复习 特征值 与 线性 矩阵 分解', 'tag:#课程 "线性 矩阵" 特征值');
  const hits = segs.filter((s) => s.hit).map((s) => s.text);
  assert.deepEqual(hits, ['特征值', '线性 矩阵']);

  const nA = makeNote('a', 'Alpha', 'alpha body', { createdAt: 100, updatedAt: 500, lastOpenedAt: 900 });
  const nB = makeNote('b', 'Beta', 'beta body', { createdAt: 300, updatedAt: 800, lastOpenedAt: 0 });
  const nC = makeNote('c', 'Gamma', 'gamma body', { createdAt: 200, updatedAt: 400, lastOpenedAt: 1200 });
  assert.deepEqual(LexiSearch.sortNotes([nA, nB, nC], 'accessed').map((n) => n.id), ['c', 'a', 'b']);
  assert.deepEqual(LexiSearch.sortNotes([nA, nB, nC], 'updated').map((n) => n.id), ['b', 'a', 'c']);
  assert.deepEqual(LexiSearch.sortNotes([nA, nB, nC], 'created').map((n) => n.id), ['b', 'c', 'a']);
  assert.deepEqual(LexiSearch.sortNotes([nC, nA, nB], 'title').map((n) => n.id), ['a', 'b', 'c']);
  console.log('PASS search highlightTerms/highlightSegments and accessed/updated/created/title sorting');

  // 2. Markdown snippet anchoring + highlighting & anchor-aware link target preview
  const longContent = '前置导论 '.repeat(40) + '\n这里记录了 核心锚点 的推导与反向传播细节，便于检索定位。';
  const longNote = makeNote('long', '深度学习笔记', longContent, {
    notebook: 'AI/研究',
    tags: ['深度学习', '梯度'],
    updatedAt: 5000,
    lastOpenedAt: 6500
  });
  const spans = MarkdownEngine.previewSpans(longNote, 'type:study 核心锚点');
  const snippetText = spans.map((s) => s.text).join('');
  assert.ok(snippetText.includes('核心锚点'));
  assert.ok(spans.some((s) => s.searchMatch && s.text.includes('核心锚点')));

  const anchoredTarget = makeNote('target-1', '向量空间', '# 引言\n基础公理\n\n## 正交投影\n正交基与投影矩阵定义在这里。\n\n## 特征分解\n更多细节', {
    notebook: '数学',
    tags: ['线代'],
    updatedAt: 7000,
    lastOpenedAt: 8200
  });
  const previewLinks = [
    makeLink('target-1', 'long', '深度学习笔记'),
    makeLink('long', 'target-1', '向量空间'),
    makeLink('other', 'target-1', '向量空间')
  ];
  const hitPreview = MarkdownEngine.linkTargetPreview('向量空间#正交投影', [longNote, anchoredTarget], previewLinks, 'default-vault');
  assert.equal(hitPreview.exists, true);
  assert.equal(hitPreview.noteId, 'target-1');
  assert.equal(hitPreview.anchor, '正交投影');
  assert.ok(hitPreview.snippet.includes('正交基'));
  assert.equal(hitPreview.outgoingCount, 1);
  assert.equal(hitPreview.backlinkCount, 2);
  assert.equal(hitPreview.lastOpenedAt, 8200);

  const missingPreview = MarkdownEngine.linkTargetPreview('尚未建立的笔记', [longNote, anchoredTarget], previewLinks, 'default-vault');
  assert.equal(missingPreview.exists, false);
  assert.equal(missingPreview.title, '尚未建立的笔记');
  assert.ok(missingPreview.snippet.includes('尚未创建'));
  console.log('PASS snippet anchoring/highlighting and anchor-aware link target preview (existing + uncreated)');

  // 3. Unconnected notes detection & candidate link suggestions
  const isolatedMention = makeNote('iso-1', '奇异值分解', '前置阅读建议参考 向量空间 中的正交基。', { tags: ['线代'] });
  const isolatedSharedTag = makeNote('iso-2', '张量记号', '与矩阵乘法相关的记号汇总。', { tags: ['线代'] });
  const isolatedUnresolved = makeNote('iso-3', '孤立草稿', '包含 [[不存在笔记]] 但没有解析成功的关联。', { tags: ['随笔'] });
  const trashedNote = makeNote('trash-1', '回收站笔记', '内容', { trashedAt: 999 });
  const allNotes = [anchoredTarget, longNote, isolatedMention, isolatedSharedTag, isolatedUnresolved, trashedNote];
  const allLinks = [
    makeLink('anchoredTarget-dummy', ''), // ignored unresolved without targetId
    makeLink('iso-3', '', '不存在笔记'),
    makeLink('target-1', 'long', '深度学习笔记')
  ];
  const unconnected = LexiRelations.unconnectedNotes(allNotes, allLinks);
  assert.deepEqual(unconnected.map((n) => n.id), ['iso-1', 'iso-2', 'iso-3']);
  assert.equal(LexiRelations.isNoteUnconnected('iso-1', allLinks), true);
  assert.equal(LexiRelations.isNoteUnconnected('target-1', allLinks), false);

  const candidates = LexiRelations.suggestLinkCandidates(isolatedMention, allNotes, allLinks, 4);
  assert.ok(candidates.length >= 2);
  assert.equal(candidates[0].noteId, 'target-1');
  assert.ok(candidates[0].reason.includes('提及'));
  assert.ok(!candidates.some((c) => c.noteId === 'trash-1'));
  console.log('PASS unconnected note detection (excluding trashed & unresolved links) and candidate ranking');

  // 4. Access timestamp recorded out-of-band without changing .md files or updatedAt
  resetStorage();
  await S.init(context);
  const original = makeNote('open-1', '访问时间隔离测试', '正文内容保持不变', { updatedAt: 42000, createdAt: 10000 });
  await S.saveNote(context, original);
  const storedBefore = (await S.getNoteById('open-1')).updatedAt;
  const filesSnapshotBefore = new Map(files);
  const historyBefore = values.get('note_history_index') || '';

  await S.recordNoteOpened(context, 'open-1', 987654321);
  const reloaded = await S.getNotes();
  const targetAfter = reloaded.find((n) => n.id === 'open-1');
  assert.equal(targetAfter.lastOpenedAt, 987654321);
  assert.equal(targetAfter.updatedAt, storedBefore);
  assert.equal(values.get('note_history_index') || '', historyBefore);
  const accessMap = JSON.parse(values.get('note_access_times') || '{}');
  assert.equal(accessMap['open-1'], 987654321);
  assert.deepEqual([...files.entries()].filter(([k]) => k.endsWith('.md')), [...filesSnapshotBefore.entries()].filter(([k]) => k.endsWith('.md')));
  console.log('PASS recordNoteOpened persists access timestamps without mutating updatedAt, .md files, or version history');

  // 5. UI components wire the 4 features cleanly
  const requiredSnippets = [
    ['components/LexiLinkPreviewCard.ets', ['LexiHighlightText', 'LexiLinkPreviewPopupCard', 'LexiLinkPreviewButton']],
    ['components/LexiNoteCard.ets', ['LexiHighlightText', 'showAccessTime', 'isUnconnected']],
    ['components/LexiVaultTab.ets', ["'accessed'", 'unconnected', 'this.query']],
    ['components/LexiHomeTab.ets', ["'accessed'", 'showAccessTime']],
    ['components/LexiDesktopWorkspace.ets', ["'accessed'", 'unconnectedOnly', 'recordNoteOpened']],
    ['components/LexiCommandPalette.ets', ['lastOpenedAt', 'LexiHighlightText']],
    ['components/LexiExploreTab.ets', ['unconnectedList', 'LexiRelations.unconnectedNotes', 'LexiLinkPreviewPopupCard']],
    ['components/LexiEditorPanels.ets', ['LexiLinkPreviewButton', 'availableNotes']],
    ['components/LexiWorkspaceRightSidebar.ets', ['isUnconnected', 'candidates', 'onInsertWikiLink']],
    ['pages/NoteEditorPage.ets', ['recordNoteOpened', 'suggestLinkCandidates', 'LexiLinkPreviewButton']]
  ];
  for (const [rel, needles] of requiredSnippets) {
    const src = fs.readFileSync(path.join(etsRoot, rel), 'utf8');
    for (const needle of needles) {
      assert.ok(src.includes(needle), `${rel} should reference ${needle}`);
    }
  }
  console.log('PASS HarmonyOS UI files integrate highlight, access sort, link preview, and unconnected notes prompts');
  console.log('5 HarmonyOS discovery-features regression groups passed.');
})().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
