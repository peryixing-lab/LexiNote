const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const { loadTheme } = require('./lib/theme-harness.cjs');

function startSession(disk, failWrite = () => false, beforeWrite = async () => {}) {
  const memory = new Map();
  const { LexiTheme } = loadTheme(memory);
  const storage = {
    settingsOwner: () => 'test-workspace',
    async getSetting(key, fallback) { return disk.has(key) ? disk.get(key) : fallback; },
    async setSetting(key, value) {
      await beforeWrite(key, value);
      if (failWrite(key, value)) throw new Error('write failed');
      disk.set(key, value);
    }
  };
  const source = fs.readFileSync(path.join(__dirname, '../../entry/src/main/ets/core/LexiAppearanceSettings.ets'), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
  const module = { exports: {} };
  const context = {
    module, exports: module.exports,
    require: () => ({ LexiStorageService: storage, LexiTheme }),
    AppStorage: { setOrCreate: (key, value) => memory.set(key, value), get: key => memory.get(key) }
  };
  vm.runInNewContext(js, context);
  return { appearance: module.exports.LexiAppearanceSettings, memory, storage };
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

test('rapid accent selections cannot let a slow earlier write replace the last choice', async () => {
  const disk = new Map();
  const session = startSession(disk, () => false, async (key, value) => {
    if (key === 'appearanceThemeColors' && JSON.parse(value).accent === '#D94B73') await new Promise(resolve => setTimeout(resolve, 30));
  });
  await session.appearance.load();
  await Promise.all([session.appearance.setAccent('#D94B73'), session.appearance.setAccent('#308F70')]);
  assert.equal(session.memory.get('lexiAccent'), '#308F70');
  const restarted = startSession(disk);
  await restarted.appearance.load();
  assert.equal(restarted.memory.get('lexiAccent'), '#308F70');
  assert.equal(restarted.memory.get('lexiThemePalette').background, session.memory.get('lexiThemePalette').background);
});

test('invalid colors and failed accent writes leave the committed palette intact', async () => {
  const session = startSession(new Map(), key => key === 'appearanceThemeColors');
  await session.appearance.load();
  const original = session.memory.get('lexiThemePalette');
  await session.appearance.setAccent('red');
  await assert.rejects(session.appearance.setAccent('#3688CD'), /write failed/);
  assert.equal(session.memory.get('lexiAccent'), '#6E44D9');
  assert.equal(session.memory.get('lexiThemePalette'), original);
});

test('an accent save finishing after a workspace switch cannot recolor the new workspace', async () => {
  let finishWrite;
  const blocked = new Promise(resolve => { finishWrite = resolve; });
  const session = startSession(new Map(), () => false, () => blocked);
  await session.appearance.load();
  const original = session.memory.get('lexiThemePalette');
  const save = session.appearance.setAccent('#3688CD');
  session.storage.settingsOwner = () => 'another-workspace';
  finishWrite();
  await save;
  assert.equal(session.memory.get('lexiThemePalette'), original);
  assert.equal(session.memory.get('lexiAccent'), '#6E44D9');
});

test('three custom fields merge concurrent changes and survive restart as one saved palette', async () => {
  const disk = new Map([['appearanceAccent', '#308F70']]);
  const session = startSession(disk);
  await session.appearance.load();
  await Promise.all([
    session.appearance.setCustomColor('background', '#FFFFFF'),
    session.appearance.setCustomColor('foreground', '#1A1C1F'),
    session.appearance.setCustomColor('accent', '#FF7A59')
  ]);
  assert.deepEqual(JSON.parse(disk.get('appearanceThemeColors')), {
    mode: 'custom', accent: '#FF7A59', background: '#FFFFFF', foreground: '#1A1C1F'
  });
  const restarted = startSession(disk);
  await restarted.appearance.load();
  assert.equal(restarted.memory.get('lexiThemePalette').background, '#FFFFFF');
  assert.equal(restarted.memory.get('lexiThemePalette').text_primary, '#1A1C1F');
  assert.equal(restarted.memory.get('lexiAccent'), '#FF7A59');
  await restarted.appearance.setOriginalColors();
  const original = startSession(disk);
  await original.appearance.load();
  assert.equal(JSON.parse(original.memory.get('lexiThemeColors')).mode, 'original');
  assert.equal(original.memory.get('lexiThemePalette').background, '#F6F4FB');
  assert.equal(original.memory.get('lexiThemePalette').workspace_selection, '#E4D8FA');
});

test('invalid or unreadable custom colors leave the saved and displayed palette intact', async () => {
  const disk = new Map();
  const session = startSession(disk);
  await session.appearance.load();
  const palette = session.memory.get('lexiThemePalette');
  await assert.rejects(session.appearance.setCustomColor('background', 'white'));
  await assert.rejects(session.appearance.setCustomColor('foreground', '#FFFFFF'), /对比度/);
  assert.equal(session.memory.get('lexiThemePalette'), palette);
  assert.equal(disk.has('appearanceThemeColors'), false);
  await session.appearance.setCustomColor('background', '#FFFFFF');
  assert.equal(session.memory.get('lexiThemePalette').background, '#FFFFFF', 'later valid changes recover after rejection');
});
