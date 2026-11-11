// P04 · vault write regression: optimistic conflict, drafts, frontmatter, folders.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { NoteItem } = box.load('core/LexiModels');
const { LexiPathRegistry } = box.load('plugin/adapters/LexiPathRegistry');
const { LexiEditorBridge, PluginEditorHandle } = box.load('plugin/adapters/LexiEditorBridge');
const { LexiVaultAdapter: Vault } = box.load('plugin/adapters/LexiVaultAdapter');
const S = box.prepareStorage();
const context = box.contexts;

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };
async function rejects(promise, code, message) {
  assertions++;
  await assert.rejects(promise, (error) => String(error.message).startsWith(code), message);
}

(async () => {
  const vault = await S.createVault(context, '写入测试', '');

  // 1. Create through the real storage layer.
  const created = await Vault.createText(context, vault.id, '第一课.md', '# 第一课\n初始正文');
  ok(created.id.length > 0, 'create returns a stable id');
  eq(created.path, '第一课.md', 'logical path is title based');
  const stored = await S.getNoteById(created.id);
  eq(stored.content, '# 第一课\n初始正文', 'content reaches storage');
  ok(stored.path.startsWith('/sandbox/files/'), 'physical sandbox path is used internally');
  eq(await Vault.readText(vault.id, created.id), '# 第一课\n初始正文', 'read back through the adapter');
  console.log('PASS createText persists through LexiStorageService and returns the logical path');

  // 2. Duplicate creation is refused instead of silently overwriting.
  await rejects(Vault.createText(context, vault.id, '第一课.md', '另一份'), 'E_PATH_EXISTS', 'duplicate create is refused');
  console.log('PASS creating an existing path is refused');

  // 3. Normal conditional write.
  const before = await S.getNoteById(created.id);
  const updated = await Vault.writeText(context, vault.id, created.id, '# 第一课\n更新后的正文', before.updatedAt);
  const after = await S.getNoteById(created.id);
  eq(after.content, '# 第一课\n更新后的正文', 'content updated');
  ok(after.updatedAt >= before.updatedAt, 'timestamp advanced');
  eq(updated.id, created.id, 'id is stable across writes');
  console.log('PASS writeText with a current expectation succeeds and keeps the note id');

  // 4. Stale expectation is a conflict, not a silent overwrite.
  const stale = before.updatedAt;
  await rejects(Vault.writeText(context, vault.id, created.id, '过期写入', stale), 'E_CONFLICT', 'stale expectation is rejected');
  eq((await S.getNoteById(created.id)).content, '# 第一课\n更新后的正文', 'the newer body survived');
  console.log('PASS a stale expectedUpdatedAt produces E_CONFLICT and never overwrites');

  // 5. Two concurrent plugin writes: exactly one wins.
  const current = await S.getNoteById(created.id);
  const results = await Promise.allSettled([
    Vault.writeText(context, vault.id, created.id, '并发 A', current.updatedAt),
    Vault.writeText(context, vault.id, created.id, '并发 B', current.updatedAt)
  ]);
  const fulfilled = results.filter((item) => item.status === 'fulfilled');
  const rejected = results.filter((item) => item.status === 'rejected');
  eq(fulfilled.length, 1, 'exactly one concurrent write commits');
  eq(rejected.length, 1, 'the loser fails loudly');
  ok(String(rejected[0].reason.message).startsWith('E_CONFLICT') || String(rejected[0].reason.message).startsWith('E_EDITOR_CONFLICT'),
    'loser reports a conflict code');
  console.log('PASS two concurrent plugin writes serialise and the loser gets an explicit conflict');

  // 6. A user draft in an editor blocks a plugin write.
  const layered = await S.getNoteById(created.id);
  const handle = new PluginEditorHandle();
  handle.noteId = created.id; handle.vaultId = vault.id; handle.windowId = 'w1';
  handle.isDirty = () => true; handle.isVisible = () => true;
  handle.getContent = () => '用户正在写的草稿'; handle.getBaseContent = () => layered.content;
  handle.getRevision = () => 7;
  LexiEditorBridge.register(handle);
  await rejects(Vault.writeText(context, vault.id, created.id, '插件写入', layered.updatedAt),
    'E_EDITOR_CONFLICT', 'an unsaved user draft must block the plugin');
  eq((await S.getNoteById(created.id)).content, layered.content, 'draft target untouched');
  await rejects(Vault.deleteText(context, vault.id, created.id), 'E_EDITOR_CONFLICT', 'draft blocks deletion too');
  LexiEditorBridge.unregister(handle.editorId);
  console.log('PASS an unsaved editor draft blocks both writes and deletes');

  // 7. Frontmatter survives a body rewrite.
  const fmNote = await Vault.createText(context, vault.id,
    '带属性.md', '---\ntags: ["课程"]\n状态: 进行中\n---\n# 带属性');
  const fmStored = await S.getNoteById(fmNote.id);
  eq(fmStored.tags, ['课程'], 'frontmatter tags are parsed by the existing engine');
  await Vault.writeText(context, vault.id, fmNote.id,
    '---\ntags: ["课程", "复习"]\n状态: 完成\n---\n# 带属性\n新正文', fmStored.updatedAt);
  const fmAfter = await S.getNoteById(fmNote.id);
  eq(fmAfter.tags.sort(), ['复习', '课程'].sort(), 'tags updated from the new header');
  ok(fmAfter.content.includes('新正文'), 'new body stored');
  ok(fmAfter.properties.some((p) => p.key === '状态' && p.propValue === '完成'), 'scalar property kept');
  console.log('PASS frontmatter stays structurally valid across a plugin write');

  // 8. Rename keeps the identity and moves the path.
  const renamed = await Vault.renameText(context, vault.id, fmNote.id, '改过的名字.md');
  eq(renamed.id, fmNote.id, 'rename keeps the note id');
  eq(renamed.path, '改过的名字.md', 'rename changes the logical path');
  eq(await Vault.readText(vault.id, fmNote.id), fmAfter.content, 'body survives the rename');
  const other = await Vault.createText(context, vault.id, '占位.md', '占位');
  await rejects(Vault.renameText(context, vault.id, other.id, '改过的名字.md'), 'E_PATH_EXISTS', 'rename onto an existing path fails');
  console.log('PASS rename keeps the id, moves the path and refuses collisions');

  // 9. Folder segments map to projects; unknown folders are refused, cross-folder moves too.
  await rejects(Vault.createText(context, vault.id, '子目录/深层.md', '深层'), 'E_NOT_FOUND',
    'creating inside an unknown folder is refused');
  const project = await S.createInternalProject(context, vault.id, '课程');
  const nested = await Vault.createText(context, vault.id, '课程/深层.md', '深层');
  eq(nested.path, '课程/深层.md', 'project folder becomes the path prefix');
  eq((await S.getNoteById(nested.id)).projectId, project.id, 'folder resolves to the real project id');
  await rejects(Vault.renameText(context, vault.id, nested.id, '深层.md'), 'E_UNSUPPORTED_API',
    'moving a file out of a folder is explicitly unsupported');
  eq((await S.getNoteById(nested.id)).title, '深层', 'the refused move changed nothing');
  console.log('PASS folder segments map to projects, unknown folders are refused and cross-folder moves are unsupported');

  // 10. Soft delete removes it from the vault view.
  await Vault.deleteText(context, vault.id, nested.id);
  eq((await S.getNoteById(nested.id)).trashedAt > 0, true, 'delete is a soft delete');
  await rejects(Vault.readText(vault.id, nested.id), 'E_NOT_FOUND', 'trashed note is unreadable');
  console.log('PASS deleteText performs the documented soft delete');

  // 11. Bound-folder vaults write through LexiFolderStore.
  const root = '/user/write';
  box.fakeFs.mkdirSync(root);
  box.state.persistentGrants.add('file://docs' + root);
  const bound = await S.createFolderWorkspace('外部文库', 'file://docs' + root, false);
  const external = await Vault.createText(context, bound.id, '外部笔记.md', '# 外部');
  const externalNote = await S.getNoteById(external.id);
  ok(externalNote.path.startsWith(root + '/'), 'bound folder receives the file');
  const externalUpdated = await Vault.writeText(context, bound.id, external.id, '# 外部\n改过', externalNote.updatedAt);
  eq(externalUpdated.path, '外部笔记.md', 'logical path stays stable in bound mode');
  eq(await Vault.readText(bound.id, external.id), '# 外部\n改过', 'bound write round-trips');
  console.log('PASS bound-folder vaults write through the existing folder store');

  console.log(`\nplugin-vault-write-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
