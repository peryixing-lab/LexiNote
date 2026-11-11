'use strict';
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');
const box = createSandbox();box.reset();
const S = box.prepareStorage();
const { VaultItem } = box.load('core/LexiModels');
const { PluginRecord, PluginState } = box.load('plugin/model/PluginModels');
const calls = [];
let ready = true;
let failBoot = false;
box.override('plugin/runtime/PluginRuntimeHost', { PluginRuntimeController: {
  isReady: () => ready, state: () => ready ? 'ready' : 'absent',
  async boot(boot, session) {
    calls.push(['boot', session.pluginId, session.vaultId, boot.settingsJson]);
    if (failBoot) throw Error('boot failed');
  },
  async unload() { calls.push(['unload']); },
  async sendEvent() {}, async runCommand() {}, reset() {}
} });
box.override('plugin/runtime/PluginInstallService', { PluginInstallService: {
  readManifestJson: async (_context, record) => JSON.stringify({ id: record.id }),
  readSource: async () => 'module.exports = {};',
  readFileText: () => ''
} });
const { PluginRegistry } = box.load('plugin/core/PluginRegistry');
const { PluginManager } = box.load('plugin/core/PluginManager');
const { PluginDataStore } = box.load('plugin/core/PluginDataStore');

(async () => {
  const a = new VaultItem();a.id = 'workspace-a';a.name = 'A';
  const b = new VaultItem();b.id = 'workspace-b';b.name = 'B';
  await S.setRawValue('vaults', JSON.stringify([a,b]));
  await S.setActiveVaultId(a.id);await PluginManager.init(box.contexts);
  for (const id of ['example.one', 'example.two']) {
    const record = new PluginRecord();record.id = id;record.name = id;
    record.state = PluginState.INSTALLED_DISABLED;record.requestedCapabilities = [];
    await PluginRegistry.upsert(record);
  }
  await PluginDataStore.set('example.one','plugin-data','{"theme":"A"}');
  await PluginManager.enable('example.one');
  assert.equal(PluginManager.activeId(),'example.one');
  assert.deepEqual(JSON.parse(await S.getSetting('enabledPlugins','[]')),['example.one']);
  const catalog = JSON.parse(await S.getRawValue('plugin.records','[]'));
  assert.equal(catalog.find(record=>record.id==='example.one').enabled,false,'shared catalogue carries no workspace enable switch');
  const external = new PluginRecord();external.id = 'example.external';external.name = 'Installed from another window';
  external.state = PluginState.INSTALLED_DISABLED;
  await S.updateInstalledPlugin(external.id, JSON.stringify(external));
  await PluginManager.refreshInstalled();
  assert.equal(PluginManager.activeId(),'example.one','refreshing installations preserves this workspace runtime');
  assert.ok(PluginManager.records().some(record=>record.id===external.id),'a plugin installed in another window becomes visible');
  await PluginManager.suspendWorkspace();
  assert.equal(PluginManager.activeId(),'');
  assert.deepEqual(JSON.parse(await S.getSetting('enabledPlugins','[]')),['example.one'],'leaving a workspace preserves its choice');

  await S.setActiveVaultId(b.id);await PluginManager.changeWorkspace(b.id);
  assert.deepEqual(PluginManager.records().map(record=>record.id).sort(),['example.external','example.one','example.two'],
    'all workspaces see the same installed plugins');
  assert.equal(PluginManager.activeId(),'','B starts with plugins off');
  assert.equal(await PluginDataStore.get('example.one','plugin-data'),'','B does not inherit A plugin data');
  await PluginDataStore.set('example.one','plugin-data','{"theme":"B"}');
  await PluginManager.enable('example.one');await PluginManager.disable('example.one');
  assert.ok(JSON.parse(await S.getRawValue('plugin.records','[]')).some(record=>record.id===external.id),
    'toggling a workspace plugin cannot erase another window installation');
  assert.deepEqual(JSON.parse(await S.getSetting('enabledPlugins','[]')),[]);
  await PluginDataStore.set('example.one','plugin-data','{"theme":"late A"}',a.id);
  assert.equal(await PluginDataStore.get('example.one','plugin-data'),'{"theme":"B"}','late RPC writes retain their original workspace');

  await S.setActiveVaultId(a.id);await PluginManager.changeWorkspace(a.id);
  assert.equal(PluginManager.activeId(),'example.one','returning to A restores its enabled plugin');
  assert.deepEqual(calls.filter(call=>call[0]==='boot').at(-1),['boot','example.one',a.id,'{"theme":"late A"}']);
  await PluginManager.suspendWorkspace();PluginManager.reset();ready = false;
  await PluginManager.init(box.contexts);await PluginManager.restoreWorkspace();
  assert.equal(PluginManager.activeId(),'','restoration waits for the runtime');
  ready = true;await PluginManager.restoreWorkspace();
  assert.equal(PluginManager.activeId(),'example.one','saved switch survives a fresh host');
  await S.setPluginEnabled('example.one',false,a.id);await PluginManager.refreshInstalled();
  assert.equal(PluginManager.activeId(),'','another window can disable the same workspace plugin');
  await PluginManager.enable('example.one');
  await S.updateInstalledPlugin(external.id,'');await PluginManager.refreshInstalled();
  assert.ok(!PluginManager.records().some(record=>record.id===external.id),'uninstalled plugins leave the shared catalogue');

  failBoot = true;
  await assert.rejects(PluginManager.enable('example.two'),/boot failed/);
  assert.equal(PluginManager.activeId(),'');
  assert.ok(!JSON.parse(await S.getSetting('enabledPlugins','[]')).includes('example.two'),'failed boot cannot persist an enabled switch');
  assert.deepEqual(JSON.parse(await S.getSetting('enabledPlugins','[]',b.id)),[],'A lifecycle changes do not change B switches');
  console.log('PASS workspace plugin switches, unload/restore, restart, runtime readiness, scoped plugin data, late RPC and failed boot');
})().catch(error=>{console.error(error);process.exitCode=1;});
