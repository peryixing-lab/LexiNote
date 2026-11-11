// Execute the real localization service with persistent, workspace-owned language choices.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const root = path.resolve(__dirname, '../..');
let preferred = 'default';
let system = 'en-US';
let rejectSelection = false;
let storage = new Map();
let workspace = 'first';
const preferences = new Map();
const workspaceStorage = {
  getSetting: async (key, fallback) => preferences.get(`${workspace}:${key}`) ?? fallback,
  async setSetting(key, value) {
    if (rejectSelection) throw new Error('write failed');
    preferences.set(`${workspace}:${key}`, value);
  }
};
const platform = { System: {
  getAppPreferredLanguage: () => preferred,
  getSystemLanguage: () => system,
  setAppPreferredLanguage(language) {
    if (rejectSelection) throw new Error('platform rejected language');
    preferred = language;
  }
} };
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const filename = path.join(root, 'entry/src/main/ets/core', name + '.ets');
  const source = fs.readFileSync(filename, 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021
  }}).outputText;
  const module = { exports: {} };
  vm.runInNewContext(compiled, {
    exports: module.exports,
    require: spec => spec === '@kit.LocalizationKit' ? { i18n: platform } :
      spec === './LexiStorageService' ? { LexiStorageService: workspaceStorage } : load(spec.replace('./', '')),
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) }
  }, { filename });
  cache.set(name, module.exports);
  return module.exports;
}
const { LexiI18n } = load('LexiI18n');
const { LEXI_ENGLISH } = load('LexiEnglish');
(async () => {
LexiI18n.initialize();
assert.equal(LexiI18n.language(), 'en');
assert.equal(LexiI18n.text('设置'), 'Settings');
assert.equal(LexiI18n.text('笔记 ({0})', '', ['12']), 'Notes (12)');
assert.equal(LexiI18n.text('新建「{0}」', 'en', ['$& 中文 {user}']), 'Create “$& 中文 {user}”');
assert.equal(LexiI18n.text('Unknown plugin label'), 'Unknown plugin label');
await LexiI18n.select('zh-Hans');
assert.equal(preferred, 'default', 'workspace language must not change the platform app language');
assert.equal(storage.get('lexiLanguage'), 'zh-Hans');
assert.equal(LexiI18n.text('设置'), '设置');
// Restart: no in-process state remains; the workspace restores the choice.
storage = new Map(); system = 'en-GB';
LexiI18n.initialize();
await LexiI18n.load();
assert.equal(LexiI18n.language(), 'zh-Hans');
workspace = 'second';await LexiI18n.load();
assert.equal(LexiI18n.language(), 'en');
await LexiI18n.select('en');
assert.equal(LexiI18n.text('设置'), 'Settings');
rejectSelection = true;
await assert.rejects(LexiI18n.select('zh-Hans'));
assert.equal(storage.get('lexiLanguage'), 'en', 'a failed persistence must not publish a new UI language');
rejectSelection = false;
await LexiI18n.select('invalid');
assert.equal(storage.get('lexiLanguage'), 'en');
workspace = 'first';await LexiI18n.load();assert.equal(LexiI18n.language(), 'zh-Hans');
console.log('PASS workspace language selection, restart, isolation, and persistence failure recovery');
// Unknown system languages use the complete Chinese baseline.
storage = new Map(); preferred = 'default'; system = 'fr-FR';
assert.equal(LexiI18n.language(), 'zh-Hans');
for (const [source, translation] of Object.entries(LEXI_ENGLISH)) {
  const placeholders = text => [...text.matchAll(/\{\d+\}/g)].map(match => match[0]).sort();
  assert.deepEqual(placeholders(source), placeholders(translation), `placeholder mismatch: ${source}`);
  assert.ok(translation.trim(), `empty translation: ${source}`);
}
const { LEXI_COMMANDS } = load('LexiCommands');
for (const command of LEXI_COMMANDS) {
  assert.notEqual(LexiI18n.text(command.title, 'en'), command.title,
    `built-in command is missing its English search/display title: ${command.id}`);
}
// Every native resource has a matching English resource without renaming platform keys.
for (const resource of ['string', 'lexi_native_strings', 'lexi_form_strings']) {
  const names = locale => JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources', locale, 'element', resource + '.json'))).string.map(item => item.name).sort();
  assert.deepEqual(names('en'), names('base'));
}
console.log(`PASS language selection, restart, persistence failure, source fallback, literal interpolation, ${Object.keys(LEXI_ENGLISH).length} translation entries, and native resource parity`);
})().catch(error => { console.error(error); process.exitCode = 1; });
