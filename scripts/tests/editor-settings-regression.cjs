const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/core/LexiEditorSettings.ets', 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const saved = new Map();
const state = new Map();
let fail = false;
const storage = {
  settingsOwner: () => 'test-workspace',
  getSetting: async (key, fallback) => saved.has(key) ? saved.get(key) : fallback,
  setSetting: async (key, value) => { if (fail) throw Error('write failed'); saved.set(key, value); }
};
const mod = { exports: {} };
vm.runInNewContext(js, {
  exports: mod.exports,
  require: () => ({ LexiStorageService: storage }),
  AppStorage: { setOrCreate: (key, value) => state.set(key, value) }
});
const settings = mod.exports.LexiEditorSettings;
(async () => {
  await settings.load();
  assert.equal(state.get('lexiEditorDefaultView'), 'edit');
  assert.equal(state.get('lexiEditorDefaultMode'), 'live');
  assert.equal(state.get('lexiEditorShowTitle'), true);
  await Promise.all([
    settings.setString('editorDefaultView', 'lexiEditorDefaultView', 'preview'),
    settings.setString('editorDefaultMode', 'lexiEditorDefaultMode', 'source'),
    settings.setBool('editorShowTitle', 'lexiEditorShowTitle', false),
    settings.setBool('editorLimitWidth', 'lexiEditorLimitWidth', false),
    settings.setBool('editorViewStatus', 'lexiEditorViewStatus', false)
  ]);
  state.clear();
  await settings.load();
  assert.equal(state.get('lexiEditorDefaultView'), 'preview');
  assert.equal(state.get('lexiEditorDefaultMode'), 'source');
  assert.equal(state.get('lexiEditorShowTitle'), false);
  assert.equal(state.get('lexiEditorLimitWidth'), false);
  assert.equal(state.get('lexiEditorViewStatus'), false);
  fail = true;
  await assert.rejects(settings.setBool('editorShowTitle', 'lexiEditorShowTitle', true));
  await settings.flush();
  assert.equal(state.get('lexiEditorShowTitle'), false);
  fail = false;
  await settings.setBool('editorShowTitle', 'lexiEditorShowTitle', true);
  assert.equal(state.get('lexiEditorShowTitle'), true);
  saved.set('editorDefaultView', 'invalid');
  saved.set('editorDefaultMode', 'invalid');
  await settings.load();
  assert.equal(state.get('lexiEditorDefaultView'), 'edit');
  assert.equal(state.get('lexiEditorDefaultMode'), 'live');
  console.log('PASS editor preference persistence, concurrent updates, invalid values, and failure recovery');
})().catch(err => { console.error(err); process.exitCode = 1; });
