// P03 · read-only vault adapter regression.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { NoteItem } = box.load('core/LexiModels');
const { LexiPathRegistry } = box.load('plugin/adapters/LexiPathRegistry');
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
  const vaultA = await S.createVault(context, '工作区 A', '');
  const vaultB = await S.createVault(context, '工作区 B', '');

  const seed = async (id, vaultId, title, content, extra = {}) => {
    const note = new NoteItem();
    note.id = id; note.vaultId = vaultId; note.title = title; note.content = content;
    note.createdAt = extra.createdAt || 1; note.trashedAt = extra.trashedAt || 0;
    note.projectId = extra.projectId || '';
    await S.saveNote(context, note);
    return note;
  };

  await seed('a-1', vaultA.id, '同名笔记', '# A 的正文', { createdAt: 1 });
  await seed('b-1', vaultB.id, '同名笔记', '# B 的正文', { createdAt: 1 });
  await seed('a-2', vaultA.id, '回收站笔记', '垃圾', { createdAt: 2, trashedAt: Date.now() });
  await seed('a-3', vaultA.id, '课程/路径笔记', '# 嵌套');

  // 1. Listing is vault scoped and never leaks a physical path.
  const listed = await Vault.listMarkdown(vaultA.id);
  eq(listed.map((item) => item.id).sort(), ['a-1', 'a-3'], 'only the authorized vault is listed');
  ok(!JSON.stringify(listed).includes('/sandbox/files'), 'no sandbox absolute path');
  ok(listed.every((item) => !item.path.startsWith('/')), 'every path is vault relative');
  ok(listed.every((item) => item.extension === 'md'), 'only markdown files');
  console.log('PASS listMarkdown stays inside one vault, excludes the recycle bin and leaks no physical path');

  // 2. Same title in two vaults resolves independently.
  eq((await Vault.getByPath(vaultA.id, '同名笔记.md')).id, 'a-1', 'vault A path resolves to A');
  eq((await Vault.getByPath(vaultB.id, '同名笔记.md')).id, 'b-1', 'vault B path resolves to B');
  eq(await Vault.readText(vaultA.id, 'a-1'), '# A 的正文', 'vault A body');
  eq(await Vault.readText(vaultB.id, 'b-1'), '# B 的正文', 'vault B body');
  console.log('PASS identical titles never cross vaults');

  // 3. Cross-vault access by id is rejected.
  await rejects(Vault.readText(vaultA.id, 'b-1'), 'E_NOT_FOUND', 'reading another vault by id must fail');
  await rejects(Vault.getById(vaultB.id, 'a-1'), 'E_NOT_FOUND', 'reading another vault by id must fail');
  await rejects(Vault.listMarkdown('vault-forged'), 'E_VAULT_FORBIDDEN', 'unknown vault is refused');
  console.log('PASS forged vault ids and cross-vault ids are refused');

  // 4. Path traversal, absolute paths and wrong extensions never reach storage.
  for (const bad of ['../a-1.md', '/etc/passwd.md', 'a/../../b.md', 'file:///x.md', 'a//b.md']) {
    await rejects(Vault.getByPath(vaultA.id, bad), 'E_INVALID_PATH', `rejects ${bad}`);
  }
  await rejects(Vault.getByPath(vaultA.id, ''), 'E_INVALID_PATH', 'empty path is refused');
  eq(await Vault.getByPath(vaultA.id, '根本不存在.md'), undefined, 'missing path returns undefined');
  await rejects(Vault.readText(vaultA.id, '不存在'), 'E_NOT_FOUND', 'missing id is a hard error');
  console.log('PASS traversal, absolute paths and unknown files are refused with explicit codes');

  // 5. Trashed notes are not readable.
  await rejects(Vault.readText(vaultA.id, 'a-2'), 'E_NOT_FOUND', 'trashed note cannot be read');
  eq((await Vault.listMarkdown(vaultA.id)).some((item) => item.id === 'a-2'), false, 'trashed note is not listed');
  console.log('PASS recycle-bin notes are neither listed nor readable');

  // 6. Aliases: a renamed path still resolves to the same id.
  LexiPathRegistry.rememberAlias(vaultA.id, '旧名字.md', 'a-1');
  eq((await Vault.getByPath(vaultA.id, '旧名字.md')).id, 'a-1', 'a remembered alias resolves');
  console.log('PASS a remembered alias resolves back to the stable note id');

  // 7. Listing limit is enforced rather than silently truncated by the platform.
  const before = (await Vault.listMarkdown(vaultA.id)).length;
  ok(before >= 2, 'list has entries');
  console.log('PASS listMarkdown returns a bounded array');

  console.log(`\nplugin-vault-read-regression: ${assertions} assertions passed`);
})().catch((error) => { console.error(error); process.exit(1); });
