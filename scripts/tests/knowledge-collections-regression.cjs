const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const values = new Map(); let fail = false;
const exported = {};
const storage = { getRawValue: async (key, fallback) => values.get(key) ?? fallback,
  setRawValue: async (key, value) => { if (fail) throw Error('disk full'); values.set(key, value); } };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/LexiKnowledgeCollections.ets', 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText,
  { exports: exported, require: () => ({ LexiStorageService: storage }) });
const { LexiKnowledgeCollections: store, LexiBookmark: Bookmark, LexiDatabaseCollection: Database, LexiDatabaseRecord: Record } = exported;
(async () => {
  const a = new Bookmark(); a.id = 'a'; a.noteId = 'note-a';
  const b = new Bookmark(); b.id = 'b'; b.query = 'tag:#work';
  await Promise.all([store.changeBookmarks('vault-a', rows => rows.concat([a])), store.changeBookmarks('vault-a', rows => rows.concat([b]))]);
  assert.equal((await store.bookmarks('vault-a')).length, 2);
  assert.equal((await store.bookmarks('vault-b')).length, 0);
  const database = new Database(); database.id = 'db'; database.columns = ['Name', 'Notes'];
  const record = new Record(); record.id = 'r'; record.cells = ['a|b', 'line\nbreak']; database.records = [record];
  await store.saveDatabase('vault-a', database); database.records[0].cells[0] = 'mutated';
  const restored = (await store.databases('vault-a'))[0];
  assert.equal(restored.records[0].cells[0], 'a|b');
  assert.match(store.markdown(restored), /a\\\|b/);
  assert.match(store.markdown(restored), /line<br>break/);
  fail = true; await assert.rejects(store.changeBookmarks('vault-a', () => []));
  assert.equal((await store.bookmarks('vault-a')).length, 2);
  values.set('databases:broken', '{}'); await assert.rejects(store.databases('broken'));
  console.log('PASS bookmark concurrency and vault isolation, database reload, Markdown escaping, snapshot ownership and failed persistence');
})().catch(error => { console.error(error); process.exitCode = 1; });
