'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');
const box = createSandbox();
box.reset();
const { PluginKeyboardFocus: focus } = box.load('plugin/core/PluginKeyboardFocus');
const owner = {};
const oldOwner = {};
focus.attach(oldOwner, true);
focus.setFocused(oldOwner, true);
assert.equal(focus.active(), true);
focus.attach(owner, true);
focus.setFocused(owner, true);
focus.detach(oldOwner);
assert.equal(focus.active(), true, 'a stale Web teardown cannot clear the current focus');

const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
for (const file of ['pages/Index.ets', 'components/LexiDesktopWorkspace.ets']) {
  const source = fs.readFileSync('entry/src/main/ets/' + file, 'utf8');
  assert.ok(!source.includes('.onKeyEventDispatch('), file + ': no parent dispatch override diverts keys from the Web');
  const match = source.match(/\.onKeyPreIme\(\(event: KeyEvent\): boolean => \{([\s\S]*?)\n\s*\}\)/);
  assert.ok(match, file + ': real root key handler found');
  const script = ts.transpileModule('exports.handle = function(event: KeyEvent): boolean {' + match[1] + '\n}',
    { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText;
  let commands = 0;
  const context = {
    exports: {}, PluginKeyboardFocus: focus, KeyType: { Down: 0, Up: 1 },
    LexiAppearanceSettings: { trackModifierKey() {} },
    LexiHotkeyRecorder: { active: () => 'stale-recorder', handle: async () => { commands++; } },
    LexiHotkeySettings: { fromEvent: () => 'Ctrl+1', commandFor: () => 'tab-1' },
    LexiShortcutRouter: { dispatch() { commands++; return true; } },
    AppStorage: { get: () => '[]' }
  };
  vm.runInNewContext(script, context);
  const page = { routeActive: false, showPalette: false, showWelcome: false, showSettingsWindow: false,
    desktopRouteActive: false, executeCommand() { commands++; } };
  for (const keyCode of [...Array.from({ length: 10 }, (_, i) => 2000 + i), 2055, 2044, 2062, 2064]) {
    assert.equal(context.exports.handle.call(page, { type: 0, keyCode }), false, file + ': Web retains digits and URL editing');
  }
  assert.equal(commands, 0, file + ': neither notebook commands nor a stale recorder can consume Web input');
  focus.setFocused(owner, false);
  assert.equal(context.exports.handle.call(page, { type: 0, keyCode: 2001 }), true, file + ': normal workspace shortcuts resume');
  assert.equal(commands, 1);
  focus.setFocused(owner, true);
}
focus.setVisible(owner, false);
assert.equal(focus.active(), false, 'hiding the sidebar releases the keyboard');
focus.setVisible(owner, true);
assert.equal(focus.active(), false, 'showing it again does not steal the keyboard');
focus.setFocused(owner, true);
focus.detach(owner);
assert.equal(focus.active(), false, 'destroying the Web releases the keyboard');
console.log('PASS native page and workspace dispatch preserve Web digits/editing, recorder isolation, focus lifecycle and normal shortcuts');
