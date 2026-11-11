const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');

const CTRL_LEFT = 2072;
const CTRL_RIGHT = 2073;

function startSession(quickZoom = 'true') {
  const disk = new Map([['appearanceQuickZoom', quickZoom], ['appearanceFontSize', '16']]);
  const memory = new Map();
  const storage = {
    settingsOwner: () => 'test-workspace',
    async getSetting(key, fallback) { return disk.has(key) ? disk.get(key) : fallback; },
    async setSetting(key, value) { disk.set(key, value); }
  };
  const source = fs.readFileSync(
    path.join(__dirname, '../../entry/src/main/ets/core/LexiAppearanceSettings.ets'), 'utf8');
  const js = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const module = { exports: {} };
  const context = {
    module,
    exports: module.exports,
    require: () => ({
      LexiStorageService: storage,
      KeyCode: { KEYCODE_CTRL_LEFT: CTRL_LEFT, KEYCODE_CTRL_RIGHT: CTRL_RIGHT }
    }),
    AppStorage: {
      setOrCreate: (key, value) => memory.set(key, value),
      get: key => memory.get(key)
    },
    KeyType: { Down: 0, Up: 1 },
    Date,
    JSON,
    setTimeout,
    clearTimeout
  };
  vm.runInNewContext(js, context);
  return { appearance: module.exports.LexiAppearanceSettings, memory };
}

function key(type, keyCode = CTRL_LEFT) {
  return { type, keyCode };
}

function wheel(delta, ctrl = true) {
  return {
    getModifierKeyState: (keys) => ctrl && keys.indexOf('Ctrl') >= 0,
    getVerticalAxisValue: () => delta
  };
}

const settle = (ms = 60) => new Promise(resolve => setTimeout(resolve, ms));

test('holding Ctrl stops the note scroller from following the wheel before the first tick', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  assert.equal(memory.get('lexiWheelZoomLock'), false);
  appearance.trackModifierKey(key(0));
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  appearance.trackModifierKey(key(1));
  assert.equal(memory.get('lexiWheelZoomLock'), false);
});

test('Ctrl plus wheel zooms the note and never leaves the scroller unlocked mid-gesture', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  appearance.trackModifierKey(key(0));
  assert.equal(appearance.handleAxis(wheel(1)), true);
  await settle();
  assert.equal(memory.get('lexiFontSize'), 15);
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  appearance.trackModifierKey(key(1));
  // The gesture burst outlives the key-up so the last wheel tick cannot scroll either.
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  await new Promise(resolve => setTimeout(resolve, 450));
  assert.equal(memory.get('lexiWheelZoomLock'), false);
});

test('a wheel event seen without a key event still blocks the following ticks', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  assert.equal(appearance.handleAxis(wheel(-1)), true);
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  assert.equal(memory.get('lexiFontSize'), 17);
  await new Promise(resolve => setTimeout(resolve, 450));
  assert.equal(memory.get('lexiWheelZoomLock'), false);
});

test('plain scrolling stays untouched while quick zoom is enabled', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  assert.equal(appearance.handleAxis(wheel(-1, false)), false);
  assert.equal(memory.get('lexiWheelZoomLock'), false);
  assert.equal(memory.get('lexiFontSize'), 16);
});

test('quick zoom disabled leaves both the wheel and the scroller alone', async () => {
  const { appearance, memory } = startSession('false');
  await appearance.load();
  appearance.trackModifierKey(key(0));
  assert.equal(memory.get('lexiWheelZoomLock'), false);
  assert.equal(appearance.handleAxis(wheel(1)), false);
  assert.equal(memory.get('lexiFontSize'), 16);
});

test('turning quick zoom off releases a lock left behind by an interrupted gesture', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  appearance.trackModifierKey(key(0));
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  await appearance.setQuickZoom(false);
  assert.equal(memory.get('lexiWheelZoomLock'), false);
  assert.equal(memory.get('lexiQuickZoom'), false);
});

test('a plain wheel right after zooming restores scrolling without waiting for the hold', async () => {
  const { appearance, memory } = startSession();
  await appearance.load();
  appearance.trackModifierKey(key(0));
  assert.equal(appearance.handleAxis(wheel(1)), true);
  appearance.trackModifierKey(key(1));
  assert.equal(memory.get('lexiWheelZoomLock'), true);
  assert.equal(appearance.handleAxis(wheel(1, false)), false);
  assert.equal(memory.get('lexiWheelZoomLock'), false);
});
