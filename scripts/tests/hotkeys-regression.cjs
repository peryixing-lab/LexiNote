const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/core/LexiHotkeySettings.ets', 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const preferences = new Map();
const state = new Map();
let reject = false;
const storage = {
  settingsOwner: () => 'test-workspace',
  getSetting: async (key, fallback) => preferences.has(key) ? preferences.get(key) : fallback,
  setSetting: async (key, value) => { if (reject) throw Error('write failed'); preferences.set(key, value); }
};
const moduleObj = { exports: {} };
const commandExports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/LexiCommands.ets', 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { exports: commandExports });
vm.runInNewContext(js, { exports: moduleObj.exports, require: spec => spec.endsWith('LexiCommands') ? commandExports : ({ LexiStorageService: storage }),
  AppStorage: { get: key => state.get(key), setOrCreate: (key, value) => state.set(key, value) } });
const hotkeys = moduleObj.exports.LexiHotkeySettings;
const event = (keyCode, modifiers = [], metaKey = 0) => ({ keyCode, metaKey,
  getModifierKeyState: keys => keys.every(key => modifiers.includes(key)) });
(async () => {
  await hotkeys.load();
  assert.equal(new Set(commandExports.LEXI_COMMANDS.map(command => command.id)).size, commandExports.LEXI_COMMANDS.length);
  assert.equal(hotkeys.commandFor('[]', 'Ctrl+F'), 'find');
  assert.equal(hotkeys.fromEvent(event(2031, ['Ctrl'])), 'Ctrl+O');
  assert.equal(hotkeys.fromEvent(event(2049, ['Ctrl', 'Shift'])), 'Ctrl+Shift+TAB');
  assert.equal(hotkeys.fromEvent(event(2014, ['Alt'], 1)), 'Meta+Alt+ARROWLEFT');
  assert.equal(hotkeys.fromEvent(event(2090)), 'F1');
  assert.equal(hotkeys.fromEvent(event(2017)), '');
  assert.deepEqual(Array.from(hotkeys.bindings('[]', 'switcher', hotkeys.defaults('switcher'))), ['Ctrl+O']);
  await Promise.all([hotkeys.set('switcher', []), hotkeys.set('plugin:action', ['Ctrl+Shift+P'])]);
  assert.equal(hotkeys.bindings(state.get('lexiHotkeyOverrides'), 'switcher', ['Ctrl+O']).length, 0);
  state.clear(); await hotkeys.load();
  assert.equal(hotkeys.bindings(state.get('lexiHotkeyOverrides'), 'plugin:action', []).join(), 'Ctrl+Shift+P');
  await hotkeys.set('switcher', null);
  assert.equal(hotkeys.bindings(state.get('lexiHotkeyOverrides'), 'switcher', ['Ctrl+O']).join(), 'Ctrl+O');
  const before = state.get('lexiHotkeyOverrides'); reject = true;
  await assert.rejects(hotkeys.set('switcher', ['Ctrl+K']));
  assert.equal(state.get('lexiHotkeyOverrides'), before);
  console.log('PASS hotkey normalization, plugin defaults, removal, reset, persistence, concurrency and failed writes');
})().catch(error => { console.error(error); process.exitCode = 1; });
