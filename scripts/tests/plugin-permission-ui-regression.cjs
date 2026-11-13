'use strict';

// Exercise the real settings handlers without rendering ArkUI or granting device access.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { LexiTheme } = require('./lib/theme-harness.cjs').loadTheme();
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');
const box = createSandbox(); box.reset();
const models = box.load('plugin/model/PluginModels');
const { PluginState, PluginCapability } = models;
const records = [
  { id: 'calendar', name: 'Calendar', version: '1', kind: 'obsidian', state: PluginState.FAILED,
    lastError: 'E_PERMISSION_DENIED: plugin.storage', requestedCapabilities: [PluginCapability.PLUGIN_STORAGE, PluginCapability.VAULT_WRITE], grantedCapabilities: [] },
  { id: 'other', name: 'Other', version: '1', kind: 'obsidian', state: PluginState.INSTALLED_DISABLED,
    lastError: '', requestedCapabilities: [PluginCapability.UI_NOTICE], grantedCapabilities: [PluginCapability.UI_NOTICE] }
];
const calls = [];
const manager = {
  records: () => records,
  kindLabel: () => 'Obsidian', runtimeLabel: () => 'ready', diagnosticsOf: () => [],
  async grantAll(id) { calls.push(['grant', id]); const record = records.find(r => r.id === id); record.grantedCapabilities = record.requestedCapabilities.slice(); },
  async revokeAll(id) { calls.push(['revoke', id]); const record = records.find(r => r.id === id); record.grantedCapabilities = []; record.state = PluginState.INSTALLED_DISABLED; },
  async disable(id) { calls.push(['disable', id]); const record = records.find(r => r.id === id); record.state = PluginState.INSTALLED_DISABLED; record.lastError = ''; },
  async enable(id) { calls.push(['enable', id]); records.find(r => r.id === id).state = PluginState.ACTIVE; }
};
const sourcePath = 'entry/src/main/ets/plugin/ui/LexiPluginSettingsPanel.ets';
let source = fs.readFileSync(sourcePath, 'utf8');
source = source.slice(0, source.indexOf('  @Builder')) + '\n}\n';
source = source.replace(/@\w+(?:\([^)]*\))?\s*/g, '').replace('export struct LexiPluginSettingsPanel', 'export class LexiPluginSettingsPanel');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
const exported = {};
vm.runInThisContext('(function(require,module,exports){' + compiled + '\n})', { filename: sourcePath })(
  name => name.endsWith('LexiTheme') ? { LexiTheme } : name.endsWith('PluginModels') ? models : { PluginManager: manager }, { exports: exported }, exported);
global.$r = name => name;
let dialogChoice = 0;
let lastDialog;
const panel = new exported.LexiPluginSettingsPanel();
panel.getUIContext = () => ({ getPromptAction: () => ({
  showDialog: async options => { lastDialog = options; if (dialogChoice === 'dismiss') { throw Error('dismiss'); } return { index: dialogChoice }; },
  showToast: () => {}
}) });

(async () => {
  panel.reload();
  assert.equal(panel.rows[0].allGranted, false);
  assert.equal(panel.rows[1].allGranted, true);
  await panel.toggleAllPermissions(panel.rows[0], true);
  assert.deepEqual(calls, [], 'cancel never grants or starts a plugin');
  assert.equal(panel.rows[0].allGranted, false);
  assert.match(lastDialog.title, /Calendar/);
  assert.match(lastDialog.message, /修改.*删除/);
  assert.match(lastDialog.message, /保存插件私有设置/);
  assert.match(lastDialog.message, /创建\/修改知识库文件/);
  dialogChoice = 'dismiss';
  await panel.toggleAllPermissions(panel.rows[0], true);
  assert.deepEqual(calls, [], 'dismissing the warning also leaves permissions unchanged');
  dialogChoice = 1;
  await panel.toggleAllPermissions(panel.rows[0], true);
  assert.deepEqual(calls, [['grant', 'calendar'], ['disable', 'calendar']]);
  assert.equal(panel.rows[0].allGranted, true);
  assert.equal(panel.rows[0].lastError, '', 'resolved permission errors are cleared');
  assert.equal(panel.rows[1].allGranted, true, 'other plugin retains its independent setting');
  await panel.toggleAllPermissions(panel.rows[0], false);
  assert.deepEqual(calls.at(-1), ['revoke', 'calendar']);
  assert.equal(panel.rows[0].allGranted, false);
  assert.equal(panel.rows[1].allGranted, true);
  panel.toggleExpanded(panel.rows[0]); panel.reload();
  assert.equal(panel.rows[0].expanded, true, 'permission detail remains expanded after refresh');
  records[0].grantedCapabilities = records[0].requestedCapabilities.slice();
  records[0].state = PluginState.FAILED; records[0].lastError = 'E_PERMISSION_DENIED: plugin.storage';
  panel.reload();
  assert.equal(panel.rows[0].permissionReady, true);
  assert.equal(panel.rows[0].stateLabel, '待启用', 'a previously granted plugin shows ready to retry instead of stale permission failure');
  console.log('PASS permission UI: warning, cancel, dismiss, confirm, independent switches and revocation');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => { delete global.$r; });
