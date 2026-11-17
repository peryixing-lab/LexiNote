const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

const core = path.resolve(__dirname, '../../entry/src/main/ets/core');
let noteRows, contentRows, linkRows, nativeLocks;
let files, values, handles, failRename, failWrite, failInsert, dbSnapshot, directories, symlinks, persistentGrants, prefs;
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
  async activatePermission(policies) { for (const p of policies) if (!persistentGrants.has(p.uri)) throw new Error('authorization revoked'); }
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
    if (failWrite && failWrite(p, text)) {
      const err = new Error('No space left on device (ENOSPC)');
      err.code = 13900025;
      throw err;
    }
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
    if (failRename && failRename(to)) {
      const err = new Error('No space left on device (ENOSPC)');
      err.code = 13900025;
      throw err;
    }
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
    if (failInsert && failInsert(table, row)) {
      const err = new Error('ENOSPC disk full');
      err.code = 13900025;
      throw err;
    }
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
  async beginTransaction() {
    dbSnapshot = { values: new Map(values), noteRows: new Map(noteRows), contentRows: new Map(contentRows), linkRows: structuredClone(linkRows) };
  },
  async commit() { dbSnapshot = undefined; },
  async rollBack() {
    values = new Map(dbSnapshot.values);
    noteRows = new Map(dbSnapshot.noteRows);
    contentRows = new Map(dbSnapshot.contentRows);
    linkRows = structuredClone(dbSnapshot.linkRows);
    dbSnapshot = undefined;
  }
};

const cache = new Map();
function load(name, memo = cache) {
  if (memo.has(name)) return memo.get(name);
  const filename = path.join(core, name + '.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const module = { exports: {} };
  memo.set(name, module.exports);
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
    if (spec === '@kit.ArkTS') return { util: { generateRandomUUID: () => (fixedUuids.length ? fixedUuids.shift() : crypto.randomUUID()) } };
    if (spec === '@kit.AbilityKit') return {};
    if (spec === '@kit.BasicServicesKit') return { pasteboard: {}, deviceInfo: { get deviceType() { return '2in1'; } } };
    if (spec === '@kit.FormKit') return { formBindingData: { createFormBindingData: (d) => d }, formProvider: { getPublishedRunningFormInfos: async () => [] } };
    if (spec === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {}, info() {}, error() {} } };
    throw new Error('Unexpected import: ' + spec);
  };
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename })(req, module, module.exports);
  return module.exports;
}

const { LexiStorageService: S } = load('LexiStorageService');
const { NoteItem, NoteRevision } = load('LexiModels');
const { LexiNoteHistory, LexiHistoryRetentionPolicy, LexiHistoryNoteEntry, LexiDraftWalEntry } = load('LexiNoteHistory');
const context = { filesDir: '/sandbox/files', getApplicationContext() { return this; } };

function reset() {
  nativeLocks = new Map();
  noteRows = new Map();
  contentRows = new Map();
  linkRows = [];
  dbSnapshot = undefined;
  files = new Map();
  values = new Map();
  handles = new Map();
  directories = new Set();
  symlinks = new Set();
  persistentGrants = new Set();
  prefs = new Map();
  failRename = undefined;
  failWrite = undefined;
  failInsert = undefined;
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

function makeNote(id, title, content, tags = [], updatedAt = 1000) {
  const n = new NoteItem();
  n.id = id;
  n.vaultId = 'default-vault';
  n.title = title;
  n.content = content;
  n.tags = tags.slice();
  n.updatedAt = updatedAt;
  return n;
}

const tests = [
  ['1. snapshot deduplication, line diff accuracy, and huge-file linear fallback', () => {
    const a = makeNote('n1', '旧标题', '第一行\n保持不变\n待删除行\n结尾', ['tag1'], 1000);
    const b = makeNote('n1', '新标题', '第一行\n保持不变\n新增行\n结尾', ['tag1', 'tag2'], 2000);
    const diff = LexiNoteHistory.diffVersions(a.title, a.content, b.title, b.content, a.tags, b.tags);
    assert.equal(diff.titleChanged, true);
    assert.equal(diff.tagsChanged, true);
    assert.equal(diff.addedCount, 1);
    assert.equal(diff.removedCount, 1);
    assert.equal(diff.unchangedCount, 3);
    assert.ok(diff.lines.some((l) => l.kind === 'remove' && l.text === '待删除行'));
    assert.ok(diff.lines.some((l) => l.kind === 'add' && l.text === '新增行'));

    // Deduplication: identical consecutive revision upgrades reason instead of bloating history.
    const policy = LexiNoteHistory.defaultPolicy();
    const r1 = LexiNoteHistory.buildRevision('r1', a, 1000, 'autosave');
    const rDup = LexiNoteHistory.buildRevision('r2', a, 2000, 'manual');
    const pruned = LexiNoteHistory.appendAndPrune([r1], rDup, policy, 3000, false);
    assert.equal(pruned.length, 1);
    assert.equal(pruned[0].reason, 'manual');

    // Huge-file diff fallback must finish without throwing or exploding memory.
    const bigA = makeNote('big', 'T', Array.from({ length: 1200 }, (_, i) => 'line-' + i).join('\n'));
    const bigB = makeNote('big', 'T', Array.from({ length: 1200 }, (_, i) => (i === 500 ? 'changed-500' : 'line-' + i)).join('\n'));
    const bigDiff = LexiNoteHistory.diffVersions(bigA.title, bigA.content, bigB.title, bigB.content, bigA.tags, bigB.tags);
    assert.ok(bigDiff.addedCount >= 1 && bigDiff.removedCount >= 1);
  }],

  ['2. restore automatically preserves BOTH DB current version AND unsaved live editor draft', async () => {
    await S.init(context);
    const n1 = makeNote('note-restore', 'V1 标题', 'V1 内容', ['v1']);
    await S.saveNote(context, n1);

    const n2 = await S.getNoteById('note-restore');
    n2.title = 'V2 标题';
    n2.content = 'V2 已保存内容';
    n2.tags = ['v2'];
    n2.updatedAt = Date.now() + 10;
    await S.saveNote(context, n2);

    const historyBeforeRestore = await S.getNoteHistory('note-restore');
    const revV1 = historyBeforeRestore.find((r) => r.snapshot.content.includes('V1 内容') && !r.snapshot.content.includes('V2'));
    assert.ok(revV1, 'V1 revision should exist in history before restore');

    // Restore V1 while editor has unsaved V3 draft!
    const restored = await S.restoreNoteRevision(context, 'note-restore', revV1.id, 'V3 草稿标题', 'V3 未保存草稿内容');
    assert.equal(restored.title, 'V1 标题');
    assert.ok(restored.content.includes('V1 内容'));
    assert.deepEqual(restored.tags, ['v1']);

    const historyAfterRestore = await S.getNoteHistory('note-restore');
    assert.ok(historyAfterRestore.some((r) => r.snapshot.content.includes('V3 未保存草稿内容') && r.reason === 'restore-backup'), 'live draft must be backed up before restore');
    assert.ok(historyAfterRestore.some((r) => r.snapshot.content.includes('V2 已保存内容') && r.reason === 'restore-backup'), 'DB current version must be backed up before restore');
  }],

  ['3. bounded retention cleanup by age, per-note count/bytes, and global storage limit', () => {
    const now = 100 * 24 * 60 * 60 * 1000;
    const policy = new LexiHistoryRetentionPolicy();
    policy.maxAgeDays = 7;
    policy.maxCountPerNote = 3;
    policy.maxBytesPerNote = 256 * 1024;
    policy.maxTotalBytes = 1024 * 1024; // 1 MB floor when clamped

    // Time expiry + per-note count cap.
    const oldRev = LexiNoteHistory.buildRevision('old', makeNote('nA', 'Old', 'expired'), now - 10 * 24 * 60 * 60 * 1000, 'autosave');
    const r1 = LexiNoteHistory.buildRevision('r1', makeNote('nA', 'T1', 'c1'), now - 5 * 60 * 1000, 'autosave');
    const r2 = LexiNoteHistory.buildRevision('r2', makeNote('nA', 'T2', 'c2'), now - 4 * 60 * 1000, 'autosave');
    const r3 = LexiNoteHistory.buildRevision('r3', makeNote('nA', 'T3', 'c3'), now - 3 * 60 * 1000, 'autosave');
    const r4 = LexiNoteHistory.buildRevision('r4', makeNote('nA', 'T4', 'c4'), now - 2 * 60 * 1000, 'autosave');
    const pruned = LexiNoteHistory.pruneRevisions([oldRev, r1, r2, r3, r4], policy, now);
    assert.equal(pruned.length, 3);
    assert.deepEqual(pruned.map((r) => r.id), ['r4', 'r3', 'r2']);

    // Global storage cap (> 1 MB across two notes).
    const bigBody = 'X'.repeat(600 * 1024);
    const bigOld = LexiNoteHistory.buildRevision('b-old', makeNote('n1', 'A', bigBody), now - 60000, 'autosave');
    const bigNew = LexiNoteHistory.buildRevision('b-new', makeNote('n2', 'B', bigBody), now - 10000, 'autosave');
    const globalPruned = LexiNoteHistory.pruneAllEntries([
      new LexiHistoryNoteEntry('n1', [bigOld]),
      new LexiHistoryNoteEntry('n2', [bigNew])
    ], policy, now);
    assert.ok(globalPruned.totalBytes <= 1024 * 1024);
    assert.equal(globalPruned.removedCount, 1);
    assert.equal(globalPruned.entries[0].noteId, 'n2');
  }],

  ['4. disk full cleans temp files, preserves original note, and compacts history instead of blocking save', async () => {
    await S.init(context);
    const n1 = makeNote('note-diskfull', '安全笔记', '原始已落盘内容');
    const saved = await S.saveNote(context, n1);
    const originalBody = files.get(saved.path);

    // 4a. Primary Markdown write hits ENOSPC on temp write -> temp cleaned, original untouched, error thrown clearly.
    failWrite = (p) => p.includes('.tmp');
    const attempt = makeNote('note-diskfull', '安全笔记', '写满时的未落盘新内容');
    attempt.path = saved.path;
    await assert.rejects(S.saveNote(context, attempt), (err) => {
      assert.equal(S.isDiskFullError(err), true);
      assert.match(S.friendlySaveError(err), /存储空间已满/);
      return true;
    });
    const leftoverTmp = [...files.keys()].filter((k) => k.endsWith('.tmp') || k.endsWith('.lexinote-tmp'));
    assert.equal(leftoverTmp.length, 0, 'temp file must be removed on write failure');
    assert.equal(files.get(saved.path), originalBody, 'primary markdown file must remain intact');
    failWrite = undefined;

    // 4b. Pre-seed bulky history, then simulate kv_store failure ONLY when writing full history -> saveNoteSnapshot compacts/skips optional history and still saves the note!
    const v2 = makeNote('note-diskfull', '安全笔记', '第二次保存内容');
    v2.path = saved.path;
    await S.saveNote(context, v2);
    assert.ok((await S.getNoteHistory('note-diskfull')).length >= 1);

    failInsert = (table, row) => table === 'kv_store' && typeof row.key === 'string' && row.key.startsWith('history:') && row.value.length > 4;
    const v3 = makeNote('note-diskfull', '安全笔记', '磁盘紧张时的第三次保存');
    v3.path = saved.path;
    const savedV3 = await S.saveNote(context, v3);
    assert.equal(savedV3.content, '磁盘紧张时的第三次保存');
    failInsert = undefined;
  }],

  ['5. unexpected crash WAL draft recovery for both brand-new orphan drafts and modified existing notes', async () => {
    await S.init(context);
    const existing = makeNote('note-existing', '线上标题', '线上内容');
    await S.saveNote(context, existing);

    // Simulate editing an existing note & a brand-new unsaved note, written synchronously to crash WAL without saveNote().
    const walExisting = new LexiDraftWalEntry();
    walExisting.noteId = 'note-existing';
    walExisting.vaultId = existing.vaultId;
    walExisting.title = '线上标题';
    walExisting.content = '断电前最后一秒的未保存编辑';
    walExisting.baseTitle = '线上标题';
    walExisting.baseContent = '线上内容';
    walExisting.updatedAt = Date.now();
    LexiStorageService_writeWal(walExisting);

    const walOrphan = new LexiDraftWalEntry();
    walOrphan.noteId = 'orphan-new-note';
    walOrphan.vaultId = 'default-vault';
    walOrphan.title = '闪退前新建笔记';
    walOrphan.content = '尚未点击保存的珍贵内容';
    walOrphan.updatedAt = Date.now();
    LexiStorageService_writeWal(walOrphan);

    // Restart: run startup crash recovery.
    const recoveredNotes = await S.recoverCrashDrafts(context);
    assert.ok(recoveredNotes.some((n) => n.id === 'orphan-new-note' && n.content === '尚未点击保存的珍贵内容'), 'brand-new crash draft must be recovered into notes');
    const existingHist = await S.getNoteHistory('note-existing');
    assert.ok(existingHist.some((r) => r.reason === 'crash-recovery' && r.snapshot.content === '断电前最后一秒的未保存编辑'), 'modified note crash draft must be preserved in history');
    const pending = LexiStorageService_pendingCrash('note-existing');
    assert.ok(pending && pending.content === '断电前最后一秒的未保存编辑', 'pending recovery prompt should be available when reopening note');
  }],

  ['6. multi-window concurrent editing detects divergence and resolves conflict with zero silent loss', async () => {
    await S.init(context);
    const initial = makeNote('shared-note', '协作笔记', '共同起点');
    const v1 = await S.saveNote(context, initial);

    // Window B saves update V2 first.
    const fromWinB = makeNote('shared-note', '协作笔记', '窗口 B 的修改');
    fromWinB.path = v1.path;
    const v2 = await S.saveNoteIfCurrent(context, fromWinB, v1.title, v1.content);
    assert.ok(v2.content.includes('窗口 B 的修改'));

    // Window A holds stale base v1 and tries to save -> MUST reject instead of silent overwrite!
    const fromWinA = makeNote('shared-note', '协作笔记', '窗口 A 的修改');
    fromWinA.path = v1.path;
    await assert.rejects(
      S.saveNoteIfCurrent(context, fromWinA, v1.title, v1.content),
      /DOCUMENT_CHANGED_ELSEWHERE/
    );

    // Resolve choosing mine & backing up theirs to history -> primary becomes Window A, Window B preserved in history!
    const chosenMine = await S.saveNoteResolvingConflict(context, fromWinA, 'use-mine-backup-theirs');
    assert.ok(chosenMine.content.includes('窗口 A 的修改'));
    const histAfterMine = await S.getNoteHistory('shared-note');
    assert.ok(histAfterMine.some((r) => r.snapshot.content.includes('窗口 B 的修改') && r.reason === 'conflict-backup'));

    // Also test resolving choosing theirs & backing up mine to history.
    const staleOther = makeNote('shared-note', '协作笔记', '另一窗口的竞争草稿');
    staleOther.path = chosenMine.path;
    const chosenTheirs = await S.saveNoteResolvingConflict(context, staleOther, 'use-theirs-backup-mine');
    assert.ok(chosenTheirs.content.includes('窗口 A 的修改'));
    const histAfterTheirs = await S.getNoteHistory('shared-note');
    assert.ok(histAfterTheirs.some((r) => r.snapshot.content.includes('另一窗口的竞争草稿') && r.reason === 'conflict-backup'));
  }]
];

function LexiStorageService_writeWal(entry) {
  S.writeDraftWalSync(context, entry);
}

function LexiStorageService_pendingCrash(noteId) {
  return S.getPendingCrashDraftSync(context, noteId);
}

(async () => {
  for (const [name, fn] of tests) {
    reset();
    await fn();
    console.log('PASS ' + name);
  }
  console.log(`${tests.length} version-history & safety regression groups passed.`);
})().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
