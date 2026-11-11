const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

function startSession(disk, failWrite = () => false) {
  const memory = new Map();
  const storage = {
    settingsOwner: () => 'test-workspace',
    async getSetting(key, fallback) { return disk.has(key) ? disk.get(key) : fallback; },
    async setSetting(key, value) {
      if (failWrite(key, value)) throw new Error('write failed');
      disk.set(key, value);
    }
  };
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/core/LexiAppearanceSettings.ets'), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const module = { exports: {} };
  const context = {
    module, exports: module.exports,
    require: () => ({ LexiStorageService: storage }),
    AppStorage: { setOrCreate: (key, value) => memory.set(key, value), get: key => memory.get(key) }
  };
  vm.runInNewContext(js, context);
  return { appearance: module.exports.LexiAppearanceSettings, memory };
}

test('appearance values and CSS snippet state survive a fresh app session', async () => {
  const disk = new Map();
  const first = startSession(disk);
  await first.appearance.load();
  await first.appearance.setAccent('#124ABC');
  await first.appearance.setFontSize(22);
  await first.appearance.setQuickZoom(true);
  await first.appearance.setSnippets([
    { id: 'one', name: '标题', css: 'h1 { color: red; }', enabled: true },
    { id: 'two', name: '间距', css: 'p { line-height: 2; }', enabled: false }
  ]);
  const restarted = startSession(disk);
  await restarted.appearance.load();
  assert.equal(restarted.memory.get('lexiAccent'), '#124ABC');
  assert.equal(restarted.memory.get('lexiFontSize'), 22);
  assert.equal(restarted.memory.get('lexiQuickZoom'), true);
  assert.deepEqual(JSON.parse(restarted.memory.get('lexiCssSnippets')), [
    { id: 'one', name: '标题', css: 'h1 { color: red; }', enabled: true },
    { id: 'two', name: '间距', css: 'p { line-height: 2; }', enabled: false }
  ]);
});

test('failed font save restores the last committed size', async () => {
  const disk = new Map([['appearanceFontSize', '18']]);
  const session = startSession(disk, key => key === 'appearanceFontSize');
  await session.appearance.load();
  await assert.rejects(session.appearance.setFontSize(25), /write failed/);
  assert.equal(session.memory.get('lexiFontSize'), 18);
  const restarted = startSession(disk);
  await restarted.appearance.load();
  assert.equal(restarted.memory.get('lexiFontSize'), 18);
});

test('rapid font updates persist in the same order as the preview', async () => {
  const disk = new Map();
  const session = startSession(disk);
  await session.appearance.load();
  await Promise.all([session.appearance.setFontSize(20), session.appearance.setFontSize(21), session.appearance.setFontSize(22)]);
  const restarted = startSession(disk);
  await restarted.appearance.load();
  assert.equal(restarted.memory.get('lexiFontSize'), 22);
});
