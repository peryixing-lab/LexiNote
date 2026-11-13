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
  assert.equal(state.get('lexiSidebarWidth'), 244);
  assert.equal(state.get('lexiRightSidebarWidth'), 280);
  assert.deepEqual(densities.pop(), [2, true]);
  await settings.setTabHeaders(false);
  await settings.setRibbon(false);
  await Promise.all([settings.setCommandVisible('vault', false), settings.setCommandVisible('plugin:p:r', false)]);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'vault'), false);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'plugin:p:r'), false);
  await settings.setCommandVisible('vault', true);
  await settings.setZoom(76);
  await settings.setSidebarWidth(360);
  assert.equal(preferences.get('interfaceSidebarWidth'), '360');
  await Promise.all([settings.setRightSidebarWidth(340), settings.setRightSidebarWidth(420)]);
  assert.equal(preferences.get('interfaceRightSidebarWidth'), '420');
  assert.equal(state.get('lexiSidebarWidth'), 360, 'right resizing must preserve the left preference');
  assert.deepEqual(densities.pop(), [1.52, true]);
  state.clear();
  await settings.load();
  assert.equal(state.get('lexiTabHeaders'), false);
  assert.equal(state.get('lexiShowRibbon'), false);
  assert.equal(state.get('lexiInterfaceZoom'), 76);
  assert.equal(state.get('lexiSidebarWidth'), 360);
  assert.equal(state.get('lexiRightSidebarWidth'), 420);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'vault'), true);
  assert.equal(settings.isVisible(state.get('lexiHiddenRibbonCommands'), 'plugin:p:r'), false);
  reject = true;
  await assert.rejects(settings.setRibbon(true));
  assert.equal(state.get('lexiShowRibbon'), false);
  assert.equal(settings.clampZoom(NaN), 100);
  assert.equal(settings.clampZoom(500), 150);
  assert.equal(settings.clampSidebarWidth(NaN), 244);
  assert.equal(settings.clampSidebarWidth(-10), 200);
  assert.equal(settings.clampSidebarWidth(900), 480);
  assert.equal(settings.clampRightSidebarWidth(NaN), 280);
  assert.equal(settings.clampRightSidebarWidth(-10), 232);
  assert.equal(settings.clampRightSidebarWidth(900), 560);
  for (const workspace of [840, 1000, 1200, 1920]) {
    for (const ribbon of [0, 56]) {
      for (const inspector of [0, 232, 280]) {
        for (const preferred of [200, 244, 360, 480]) {
          const width = settings.sidebarWidthForWindow(preferred, workspace, ribbon, inspector);
          assert.ok(width >= 200 && width <= preferred);
          if (workspace - ribbon - inspector >= 620) {
            assert.ok(workspace - ribbon - inspector - width >= 420, 'reserve editor space');
          }
        }
      }
    }
  }
  assert.equal(settings.sidebarWidthForWindow(480, 840, 56, 0), 364);
  assert.equal(state.get('lexiSidebarWidth'), 360, 'window constraints must not overwrite the saved preference');
  for (const workspace of [840, 1000, 1200, 1920]) {
    for (const ribbon of [0, 56]) {
      for (const leftPreference of [200, 360, 480]) {
        for (const rightPreference of [232, 280, 420, 560]) {
          for (let leftOpen of [false, true]) {
            let right = settings.rightSidebarWidthForWindow(rightPreference, workspace, ribbon, leftOpen);
            let left = leftOpen ? settings.sidebarWidthForWindow(leftPreference, workspace, ribbon, right) : 0;
            if (workspace - ribbon - left - right < 420) {
              leftOpen = false;
              right = settings.rightSidebarWidthForWindow(rightPreference, workspace, ribbon, leftOpen);
              left = 0;
            }
            assert.ok(right >= 232 && right <= rightPreference);
            assert.ok(!leftOpen || left >= 200 && left <= leftPreference);
            assert.ok(workspace - ribbon - left - right >= 420, 'both sidebars must reserve editor space');
          }
        }
      }
    }
  }
  assert.equal(state.get('lexiRightSidebarWidth'), 420, 'window constraints must preserve the right preference');
  preferences.set('interfaceSidebarWidth', 'invalid');
  preferences.set('interfaceRightSidebarWidth', 'invalid');
  await settings.load();
  assert.equal(state.get('lexiSidebarWidth'), 244, 'invalid persisted widths restore the default');
  assert.equal(state.get('lexiRightSidebarWidth'), 280, 'invalid right widths restore the default');
  console.log('PASS independent sidebar widths, joint window limits, concurrent persistence, restore, zoom, and failed persistence');
})().catch(err => { console.error(err); process.exitCode = 1; });
