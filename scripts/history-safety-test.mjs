import assert from 'node:assert/strict';
import { mkdtempSync, existsSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const require = createRequire(import.meta.url);
const esbuild = require('esbuild');

const tmpWork = mkdtempSync(path.join(os.tmpdir(), 'lexinote-win-test-'));

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

function makeNote(id, title, content, tags = [], updatedAt = 1000) {
  return {
    id,
    vaultId: 'vault-1',
    projectId: '',
    title,
    notebook: '默认',
    content,
    noteType: 'markdown',
    editorLevel: 'pro',
    tags: [...tags],
    properties: [],
    pinned: false,
    favorite: false,
    trashedAt: 0,
    createdAt: 1000,
    updatedAt,
    path: ''
  };
}

function makeState(notes) {
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
    }
  };
}

try {
  const sharedHist = await compileModule('src/shared/noteHistory.ts', 'noteHistory.mjs');
  const storeMod = await compileModule('src/main/historyStore.ts', 'historyStore.mjs');
  const fsMod = await compileModule('src/main/workspaceFs.ts', 'workspaceFs.mjs');

  const {
    buildRevision,
    appendAndPruneRevisions,
    pruneNoteRevisions,
    pruneGlobalHistoryMap,
    computeSnapshotHash,
    diffNoteVersions,
    DEFAULT_HISTORY_POLICY
  } = sharedHist;
  const { NoteHistoryStore, mergeWithConflictDetection } = storeMod;
  const { atomicWriteTextAsync, atomicWriteTextSync, isDiskFullError, friendlySaveError } = fsMod;

  // 1. Diff accuracy, deduplication, and huge-file fallback
  {
    const a = makeNote('n1', '旧标题', '第一行\n不变行\n要删行\n末尾', ['t1'], 1000);
    const b = makeNote('n1', '新标题', '第一行\n不变行\n新增行\n末尾', ['t1', 't2'], 2000);
    const diff = diffNoteVersions(a, b);
    assert.equal(diff.titleChanged, true);
    assert.equal(diff.tagsChanged, true);
    assert.equal(diff.addedCount, 1);
    assert.equal(diff.removedCount, 1);
    assert.equal(diff.unchangedCount, 3);
    assert.ok(diff.lines.some((l) => l.kind === 'remove' && l.text === '要删行'));
    assert.ok(diff.lines.some((l) => l.kind === 'add' && l.text === '新增行'));

    const r1 = buildRevision('r1', a, 1000, 'autosave');
    const r2 = buildRevision('r2', a, 2000, 'manual');
    const dedup = appendAndPruneRevisions([r1], r2, DEFAULT_HISTORY_POLICY, 3000, false);
    assert.equal(dedup.length, 1);
    assert.equal(dedup[0].reason, 'manual');

    const bigA = makeNote('big', 'Big', Array.from({ length: 1200 }, (_, i) => `L${i}`).join('\n'));
    const bigB = makeNote('big', 'Big', Array.from({ length: 1200 }, (_, i) => (i === 400 ? 'CHANGED' : `L${i}`)).join('\n'));
    const bigDiff = diffNoteVersions(bigA, bigB);
    assert.ok(bigDiff.addedCount >= 1 && bigDiff.removedCount >= 1);
    console.log('PASS 1. diff accuracy, deduplication, and large-file fallback');
  }

  // 2. Restore automatically preserves both saved version and unsaved live draft
  {
    const userDir = path.join(tmpWork, 'case-restore');
    const store = new NoteHistoryStore(userDir);
    const v1 = makeNote('n-restore', 'V1 标题', 'V1 内容', ['tag-a']);
    const r1Res = await store.recordSnapshot(v1, 'manual');
    assert.ok(r1Res.revision);

    const v2 = makeNote('n-restore', 'V2 标题', 'V2 已保存内容', ['tag-b']);
    const liveDraft = { title: 'V3 标题', content: 'V3 未保存草稿', tags: ['tag-c'], properties: [] };
    const { restoredNote, revisions } = await store.restoreRevision(v2, r1Res.revision.id, liveDraft);

    assert.equal(restoredNote.title, 'V1 标题');
    assert.equal(restoredNote.content, 'V1 内容');
    assert.deepEqual(restoredNote.tags, ['tag-a']);
    assert.ok(revisions.some((r) => r.snapshot.content === 'V2 已保存内容' && r.reason === 'restore-backup'));
    assert.ok(revisions.some((r) => r.snapshot.content === 'V3 未保存草稿' && r.reason === 'restore-backup'));
    console.log('PASS 2. restore preserves current saved version and unsaved live draft before overwrite');
  }

  // 3. Time & storage retention cleanup
  {
    const now = 200 * 24 * 60 * 60 * 1000;
    const policy = {
      maxAgeDays: 7,
      maxCountPerNote: 3,
      maxBytesPerNote: 256 * 1024,
      maxTotalBytes: 1024 * 1024
    };
    const oldRev = buildRevision('old', makeNote('nA', 'Old', 'expired'), now - 10 * 24 * 60 * 60 * 1000, 'autosave');
    const recent = [1, 2, 3, 4].map((k) =>
      buildRevision(`r${k}`, makeNote('nA', `T${k}`, `content-${k}`), now - (10 - k) * 60 * 1000, 'autosave')
    );
    const pruned = pruneNoteRevisions([oldRev, ...recent], policy, now);
    assert.deepEqual(pruned.map((r) => r.id), ['r4', 'r3', 'r2']);

    const bigBody = 'Z'.repeat(650 * 1024);
    const map = new Map([
      ['n1', [buildRevision('b1', makeNote('n1', '1', bigBody), now - 60000, 'autosave')]],
      ['n2', [buildRevision('b2', makeNote('n2', '2', bigBody), now - 10000, 'autosave')]]
    ]);
    const global = pruneGlobalHistoryMap(map, policy, now);
    assert.ok(global.totalBytes <= 1024 * 1024);
    assert.equal(global.removedCount, 1);
    assert.equal(global.map.has('n2'), true);
    assert.equal(global.map.has('n1'), false);
    console.log('PASS 3. retention prunes by age, per-note count, and total storage cap');
  }

  // 4. Disk full (ENOSPC) keeps primary files intact, cleans .tmp, and compacts optional history
  {
    const diskDir = path.join(tmpWork, 'case-diskfull');
    const primaryFile = path.join(diskDir, 'lexinote-data.json');
    await atomicWriteTextAsync(primaryFile, '{"safe":true}');
    assert.equal(readFileSync(primaryFile, 'utf8'), '{"safe":true}');

    // Point a file where atomicWriteTextAsync expects a directory, OR simulate ENOSPC via custom IO driver in NoteHistoryStore
    let failOnBigHistory = true;
    const diskFullStore = new NoteHistoryStore(diskDir, {
      writeAtomic: async (filePath, content) => {
        if (failOnBigHistory && content.length > 500) {
          throw Object.assign(new Error('ENOSPC: no space left on device'), { code: 'ENOSPC' });
        }
        return atomicWriteTextAsync(filePath, content);
      }
    });
    const prev = makeNote('n-full', '大笔记', '初始');
    failOnBigHistory = false;
    await diskFullStore.recordSnapshot(prev, 'manual');
    failOnBigHistory = true;
    const largeUpdate = makeNote('n-full', '大笔记', 'A'.repeat(2000));
    const res = await diskFullStore.recordSnapshot(largeUpdate, 'autosave');
    assert.ok(res.warning && res.warning.length > 0, 'ENOSPC during history snapshot must surface warning instead of crashing primary save');
    assert.equal(isDiskFullError(Object.assign(new Error('no space'), { code: 'ENOSPC' })), true);
    assert.match(friendlySaveError(Object.assign(new Error('ENOSPC'), { code: 'ENOSPC' })), /存储空间已满/);

    // Verify atomicWriteTextSync leaves no stale temp files on write/directory failure
    const badPath = path.join(primaryFile, 'cannot-create.json'); // parent is a regular file -> throws ENOTDIR/EEXIST
    assert.throws(() => atomicWriteTextSync(badPath, 'broken'));
    assert.equal(readdirSync(diskDir).some((name) => name.includes('.tmp.')), false);
    console.log('PASS 4. disk-full / write failure preserves existing file, cleans temp, and degrades gracefully');
  }

  // 5. Crash exit WAL draft recovery for brand-new orphan and modified existing note
  {
    const walDir = path.join(tmpWork, 'case-crash');
    const store = new NoteHistoryStore(walDir);
    const existing = makeNote('n-live', '线上笔记', '上次保存内容');
    const initialMaster = makeState([existing]);

    await store.writeDraftWal({
      noteId: 'n-live',
      vaultId: 'vault-1',
      projectId: '',
      title: '线上笔记',
      content: '崩溃前 100ms 编辑的新段落',
      tags: [],
      properties: [],
      baseHash: computeSnapshotHash(existing),
      baseUpdatedAt: existing.updatedAt,
      updatedAt: Date.now()
    });
    await store.writeDraftWal({
      noteId: 'n-orphan',
      vaultId: 'vault-1',
      projectId: '',
      title: '崩前新建草稿',
      content: '还未来得及点击保存的灵感',
      tags: ['recovery'],
      properties: [],
      baseHash: '',
      baseUpdatedAt: 0,
      updatedAt: Date.now()
    });

    const recovered = await store.recoverCrashDrafts(initialMaster);
    assert.equal(recovered.stateChanged, true);
    assert.ok(recovered.nextState.notes.some((n) => n.id === 'n-orphan' && n.content === '还未来得及点击保存的灵感'));
    assert.ok(recovered.recoveredItems.some((item) => item.noteId === 'n-live' && item.draft.content === '崩溃前 100ms 编辑的新段落'));
    const liveHist = await store.getNoteHistory('n-live');
    assert.ok(liveHist.some((r) => r.reason === 'crash-recovery' && r.snapshot.content === '崩溃前 100ms 编辑的新段落'));
    assert.equal((await store.listDraftWal()).length, 0);
    await store.dismissCrashRecovery('n-live');
    assert.equal((await store.getPendingCrashRecoveries()).some((i) => i.noteId === 'n-live'), false);
    console.log('PASS 5. crash WAL recovery recovers orphan notes and preserves modified drafts in history + prompt');
  }

  // 6. Multi-window concurrent edit detection refuses silent overwrite
  {
    const baseNote = makeNote('shared', '共有笔记', '共同起点', [], 1000);
    const baseHash = computeSnapshotHash(baseNote);
    const masterAfterWinB = makeState([{ ...baseNote, content: '窗口 B 已提交修改', updatedAt: 2000 }]);
    const incomingWinA = makeState([{ ...baseNote, content: '窗口 A 并发修改', updatedAt: 3000 }]);

    const mergeRes = mergeWithConflictDetection(
      masterAfterWinB,
      incomingWinA,
      true,
      { shared: baseHash },
      (m, _i, allow) => (allow ? m : m),
      (m) => m
    );
    assert.equal(mergeRes.conflicts.length, 1);
    assert.equal(mergeRes.conflicts[0].noteId, 'shared');
    assert.equal(mergeRes.conflicts[0].remoteNote.content, '窗口 B 已提交修改');
    assert.equal(mergeRes.conflicts[0].localNote.content, '窗口 A 并发修改');
    assert.equal(mergeRes.merged.notes[0].content, '窗口 B 已提交修改', 'committed remote note must not be silently clobbered');
    assert.equal(existsSync(tmpWork), true);
    console.log('PASS 6. multi-window concurrent edit is detected and preserved without silent clobbering');
  }

  console.log('All 6 Windows version-history & data-safety tests passed!');
} finally {
  rmSync(tmpWork, { recursive: true, force: true });
}
