const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/core/LexiInterfaceSettings.ets', 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const preferences = new Map();
const state = new Map();
const densities = [];
let reject = false;
const storage = {
  settingsOwner: () => 'test-workspace',
  getSetting: async (key, fallback) => preferences.has(key) ? preferences.get(key) : fallback,
  setSetting: async (key, value) => { if (reject) throw Error('write failed'); preferences.set(key, value); }
};
const moduleObj = { exports: {} };
vm.runInNewContext(js, {
  exports: moduleObj.exports,
  require: spec => spec === '@kit.ArkUI' ? { display: { getDefaultDisplaySync: () => ({ densityPixels: 2 }) } } : { LexiStorageService: storage },
  AppStorage: { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) }
});
const settings = moduleObj.exports.LexiInterfaceSettings;
(async () => {
  settings.attachStage({ setCustomDensity: (density, subwindows) => densities.push([density, subwindows]) });
  await settings.load();
  assert.equal(state.get('lexiShowRibbon'), true);
  assert.deepEqual(densities.pop(), [2, true]);
  await settings.setTabHeaders(false);
  await settings.setRibbon(false);
  await Promise.all([settings.setCommandVisible('vault', false), settings.setCommandVisible('plugin:p:r', false)]);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'vault'), false);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'plugin:p:r'), false);
  await settings.setCommandVisible('vault', true);
  await settings.setZoom(76);
  assert.deepEqual(densities.pop(), [1.52, true]);
  state.clear();
  await settings.load();
  assert.equal(state.get('lexiTabHeaders'), false);
  assert.equal(state.get('lexiShowRibbon'), false);
  assert.equal(state.get('lexiInterfaceZoom'), 76);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'vault'), true);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'plugin:p:r'), false);
  reject = true;
  await assert.rejects(settings.setRibbon(true));
  assert.equal(state.get('lexiShowRibbon'), false);
  assert.equal(settings.clampZoom(NaN), 100);
  assert.equal(settings.clampZoom(500), 150);
  console.log('PASS interface preferences, concurrent command changes, zoom, restore, and failed persistence');
})().catch(err => { console.error(err); process.exitCode = 1; });
