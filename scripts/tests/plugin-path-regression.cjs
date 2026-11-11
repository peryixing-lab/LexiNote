// P02 · path registry regression.
// Executes the real LexiPathRegistry.ets against the real LexiStorageService with a
// simulated file system and RDB. Internal and bound-folder vaults must resolve to the
// same stable note id while never exposing NoteItem.path.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { NoteItem, LexiProject, VaultItem } = box.load('core/LexiModels');
const { LexiPathRegistry } = box.load('plugin/adapters/LexiPathRegistry');
const S = box.prepareStorage();
const context = box.contexts;

let assertions = 0;
function ok(value, message) { assertions++; assert.ok(value, message); }
function eq(actual, expected, message) { assertions++; assert.deepEqual(actual, expected, message); }
function fails(fn, code, message) {
  assertions++;
  assert.throws(fn, (error) => String(error.message).startsWith(code), message);
}

function note(id, title, extra = {}) {
  const item = new NoteItem();
  item.id = id; item.title = title; item.vaultId = extra.vaultId || 'default-vault';
  item.projectId = extra.projectId || ''; item.content = extra.content || `正文 ${title}`;
  item.createdAt = extra.createdAt || 1; item.updatedAt = extra.updatedAt || 1;
  item.trashedAt = extra.trashedAt || 0; item.sourceMissing = !!extra.sourceMissing;
  return item;
}

(async () => {
  // 1. Strict path validation.
  for (const bad of ['../secret.md', '/absolute.md', 'a//b.md', 'a/./b.md', 'file:///x.md',
    'C:/x.md', '\\\\server\\a.md', 'a/b\\c.md', 'a/', '', 'a\u0001b.md', 'a/b/../c.md']) {
    fails(() => LexiPathRegistry.normalize(bad), 'E_INVALID_PATH', `must reject ${JSON.stringify(bad)}`);
  }
  fails(() => LexiPathRegistry.normalize('a/'.repeat(9) + 'x.md'), 'E_INVALID_PATH', 'must reject deep paths');
  fails(() => LexiPathRegistry.normalize('x'.repeat(600) + '.md'), 'E_INVALID_PATH', 'must reject over-long paths');
  eq(LexiPathRegistry.normalize('课程/算法 设计.md'), '课程/算法 设计.md', 'accepts unicode relative paths');
  eq(LexiPathRegistry.normalize('a/🦋.md'), 'a/🦋.md', 'accepts emoji paths');
  ok(LexiPathRegistry.isValidPath('笔记/一.md'), 'isValidPath accepts good input');
  ok(!LexiPathRegistry.isValidPath('../x.md'), 'isValidPath rejects traversal');
  eq(LexiPathRegistry.folderOf('课程/算法.md'), '课程', 'folderOf');
  eq(LexiPathRegistry.folderOf('算法.md'), '', 'folderOf at root');
  fails(() => LexiPathRegistry.markdownPath('a.txt'), 'E_INVALID_PATH', 'only markdown is inventable');
  console.log('PASS path normalization rejects traversal, absolute paths, duplicated separators and depth/length abuse');

  // 2. UTF-8 sizes are real byte counts, not UTF-16 code units.
  eq(LexiPathRegistry.byteLength('abc'), 3, 'ascii bytes');
  eq(LexiPathRegistry.byteLength('中文'), 6, 'CJK bytes');
  eq(LexiPathRegistry.byteLength('🦋'), 4, 'astral bytes');
  console.log('PASS byteLength reports UTF-8 size for ascii, CJK and astral characters');

  // 3. Deterministic logical paths inside one vault.
  LexiPathRegistry.reset();
  const early = note('n1', '算法笔记', { createdAt: 1, vaultId: 'v1' });
  const late = note('n2', '算法笔记', { createdAt: 2, vaultId: 'v1' });
  const trashed = note('n3', '算法笔记', { createdAt: 3, vaultId: 'v1', trashedAt: 5 });
  const missing = note('n4', '算法笔记', { createdAt: 4, vaultId: 'v1', sourceMissing: true });
  LexiPathRegistry.applyNotes('v1', [late, trashed, early, missing], [], false);
  eq(LexiPathRegistry.entry('v1', 'n1').logicalPath, '算法笔记.md', 'earliest note keeps the plain name');
  eq(LexiPathRegistry.entry('v1', 'n2').logicalPath, '算法笔记-2.md', 'collision gets a deterministic suffix');
  eq(LexiPathRegistry.entry('v1', 'n3'), undefined, 'trashed notes are not listed');
  eq(LexiPathRegistry.entry('v1', 'n4'), undefined, 'sourceMissing notes are not listed');
  eq(LexiPathRegistry.noteIdForPath('v1', '算法笔记-2.md'), 'n2', 'path resolves back to the note id');
  eq(LexiPathRegistry.noteIdForPath('v1', '算法笔记-2.MD'), 'n2', 'lookup is case-insensitive inside one vault');
  console.log('PASS duplicate titles get deterministic suffixes and trashed/sourceMissing notes stay invisible');

  // 4. Two vaults may hold the same title without leaking across.
  const a = note('a1', '同名', { vaultId: 'vault-a', createdAt: 1 });
  const b = note('b1', '同名', { vaultId: 'vault-b', createdAt: 1 });
  LexiPathRegistry.applyNotes('vault-a', [a], [], false);
  LexiPathRegistry.applyNotes('vault-b', [b], [], false);
  eq(LexiPathRegistry.noteIdForPath('vault-a', '同名.md'), 'a1', 'vault A resolves to its own note');
  eq(LexiPathRegistry.noteIdForPath('vault-b', '同名.md'), 'b1', 'vault B resolves to its own note');
  eq(LexiPathRegistry.entriesForVault('vault-a').length, 1, 'vault scoped listing');
  console.log('PASS identical titles in two vaults never cross-resolve');

  // 5. Projects become folder segments; names are sanitized and de-duplicated.
  const projects = [
    { id: 'p1', vaultId: 'v2', name: '课程/笔记', createdAt: 1 },
    { id: 'p2', vaultId: 'v2', name: '课程_笔记', createdAt: 2 }
  ];
  const inP1 = note('p-1', '第一课', { vaultId: 'v2', projectId: 'p1', createdAt: 1 });
  const inP2 = note('p-2', '第一课', { vaultId: 'v2', projectId: 'p2', createdAt: 2 });
  const forged = Object.assign(new LexiProject(), {});
  LexiPathRegistry.applyNotes('v2', [inP1, inP2], [
    Object.assign(forged, { id: 'p1', vaultId: 'v2', name: '课程/笔记', createdAt: 1 }),
    Object.assign(new LexiProject(), { id: 'p2', vaultId: 'v2', name: '课程_笔记', createdAt: 2 })
  ], false);
  eq(LexiPathRegistry.entry('v2', 'p-1').logicalPath, '课程_笔记/第一课.md', 'project name is sanitized into a folder');
  eq(LexiPathRegistry.entry('v2', 'p-2').logicalPath, '课程_笔记-2/第一课.md', 'equal folder names are differentiated');
  console.log('PASS project folders are sanitized and de-duplicated deterministically');

  // 6. Rename keeps the old path resolvable as an alias.
  LexiPathRegistry.reset();
  const original = note('r1', '旧标题', { createdAt: 1, vaultId: 'v3' });
  LexiPathRegistry.applyNotes('v3', [original], [], false);
  eq(LexiPathRegistry.entry('v3', 'r1').logicalPath, '旧标题.md', 'initial path');
  const renamed = note('r1', '新标题', { createdAt: 1, updatedAt: 9, vaultId: 'v3' });
  const entry = LexiPathRegistry.applySaved('v3', renamed, '新标题');
  eq(entry.logicalPath, '新标题.md', 'rename updates the logical path');
  eq(LexiPathRegistry.noteIdForPath('v3', '新标题.md'), 'r1', 'new path resolves');
  eq(LexiPathRegistry.noteIdForPath('v3', '旧标题.md'), 'r1', 'old path stays resolvable as an alias');
  console.log('PASS a rename moves the path and keeps the previous path as a resolvable alias');

  // 7. Real storage, internal mode: logical path never equals the sandbox path.
  box.reset(); LexiPathRegistry.reset();
  const storage = box.prepareStorage();
  const internal = new NoteItem();
  internal.id = 'note-internal'; internal.title = '私有笔记'; internal.vaultId = 'default-vault';
  internal.content = '# 私有笔记\n正文';
  await storage.saveNote(context, internal);
  const stored = await storage.getNoteById('note-internal');
  ok(stored.path.startsWith('/sandbox/files/'), 'sandbox path is internal');
  await LexiPathRegistry.refresh('default-vault');
  const view = LexiPathRegistry.entry('default-vault', 'note-internal');
  eq(view.logicalPath, '私有笔记.md', 'internal mode maps to a logical path');
  eq(LexiPathRegistry.fileRef(view).path, '私有笔记.md', 'FileRef exposes the logical path only');
  ok(!JSON.stringify(LexiPathRegistry.fileRef(view)).includes('/sandbox/files'), 'no absolute path leaks through FileRef');
  eq(view.physicalMode, 'private', 'internal vault reports private mode');
  console.log('PASS internal storage exposes a logical path and never leaks NoteItem.path');

  // 8. Real storage, bound folder: physical file name differs, note id is stable.
  const root = '/user/work';
  box.fakeFs.mkdirSync(root);
  box.state.persistentGrants.add('file://docs' + root);
  const vault = await storage.createFolderWorkspace('文件工作区', 'file://docs' + root, false);
  const external = new NoteItem();
  external.id = 'note-external'; external.title = '外部笔记'; external.vaultId = vault.id;
  external.content = '# 外部笔记\n正文';
  await storage.saveNote(context, external);
  const savedExternal = await storage.getNoteById('note-external');
  ok(savedExternal.path.startsWith(root + '/'), 'bound folder writes outside the sandbox');
  ok(savedExternal.path !== '/sandbox/files/x', 'physical path differs from the logical path');
  await LexiPathRegistry.refresh(vault.id);
  const externalView = LexiPathRegistry.entry(vault.id, 'note-external');
  eq(externalView.logicalPath, '外部笔记.md', 'external mode maps to the same style of logical path');
  eq(externalView.physicalMode, 'bound-folder', 'bound vault reports bound-folder mode');
  eq(LexiPathRegistry.noteIdForPath(vault.id, '外部笔记.md'), 'note-external', 'external path resolves by note id');
  const physicalName = savedExternal.path.substring(root.length + 1);
  ok(physicalName !== externalView.logicalPath, 'physical file name and logical path are intentionally different');
  console.log('PASS bound-folder storage resolves to the same note id while the physical name stays hidden');

  // 9. forger cannot reach another vault's entry through a fabricated vault id.
  eq(LexiPathRegistry.entry(vault.id, 'note-internal'), undefined, 'entries are vault scoped');
  eq(LexiPathRegistry.noteIdForPath(vault.id, '私有笔记.md'), '', 'cross-vault path lookup returns nothing');
  console.log('PASS cross-vault path lookups return nothing');

  console.log(`\nplugin-path-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
