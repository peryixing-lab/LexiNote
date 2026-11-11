// Execute the real Index permission flow after extracting its non-rendering methods.
// File picker and dialog results are injected; system presentation still needs a device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const filename = path.resolve(__dirname, '../../entry/src/main/ets/pages/Index.ets');
const source = fs.readFileSync(filename, 'utf8');
function method(name) {
  const match = new RegExp('^  (?:private )?(?:async )?' + name + '\\(', 'm').exec(source);
  assert.ok(match, 'method exists: ' + name);
  const end = source.indexOf('\n  }', match.index);
  return source.slice(match.index, end + 4);
}
const methods = ['storageAccessChanged', 'requestStorageAfterFirstNote', 'authorizeStorageFolder', 'chooseStorageFolder'].map(method).join('\n');
const js = ts.transpileModule('class Subject {\n' + methods + '\n}; module.exports = Subject;',
  { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText;
let pending, takes, dialogs, picks, migrations, location, dialogResult, pickerResult, statusError, folderSelection;
const storage = {
  async takeStorageAccessPrompt() { takes++; const result = pending; pending = false; return result; },
  async configureLocalRoot(_context, uri) { migrations.push(uri); location = 'external'; },
  async storageLocationStatus() { if (statusError) throw new Error('status unavailable'); return location; }
};
const folders = { canChooseStorageFolder() { return folderSelection; }, async chooseStorageRoot() { picks++; return pickerResult(); } };
const moduleScope = { exports: {} };
vm.runInThisContext('(function(module,LexiStorageService,LexiFolderStore,$r){' + js + '})', { filename })(moduleScope, storage, folders, name => name);
function subject() {
  pending = true; takes = 0; dialogs = []; picks = 0; migrations = []; location = 'internal'; statusError = false;
  folderSelection = true;
  dialogResult = async () => ({ index: 0 }); pickerResult = async () => '';
  const page = new moduleScope.exports();
  Object.assign(page, {
    ready: true, showWelcome: false, storageAccessBusy: false, storageLocation: 'internal',
    showNoteDestination: false, destinationBusy: false, templateBusy: false, handlingNativeLaunch: false,
    toasts: [], refreshes: 0, context: () => ({}), tr: text => text, toast(text) { this.toasts.push(text); },
    async refresh() { this.refreshes++; },
    getUIContext: () => ({ getPromptAction: () => ({ async showDialog(options) { dialogs.push(options); return dialogResult(); } }) })
  });
  return page;
}
const tests = [];
function test(name, run) { tests.push([name, run]); }
test('startup and welcome never consume or present the first-note permission offer', async () => {
  const page = subject(); page.ready = false; await page.requestStorageAfterFirstNote();
  page.ready = true; page.showWelcome = true; await page.requestStorageAfterFirstNote();
  assert.equal(takes, 0); assert.equal(dialogs.length, 0); assert.equal(picks, 0); assert.equal(pending, true);
});
test('note destination, template, and native-launch transitions defer the permission dialog', async () => {
  for (const field of ['showNoteDestination', 'destinationBusy', 'templateBusy', 'handlingNativeLaunch']) {
    const page = subject(); page[field] = true; await page.requestStorageAfterFirstNote();
    assert.equal(takes, 0, field); assert.equal(pending, true, field); assert.equal(dialogs.length, 0, field);
    page[field] = false; await page.requestStorageAfterFirstNote(); assert.equal(dialogs.length, 1, field);
  }
});
test('declining after the first saved note keeps internal storage and does not ask again', async () => {
  const page = subject(); await page.requestStorageAfterFirstNote(); await page.requestStorageAfterFirstNote();
  assert.equal(dialogs.length, 1); assert.equal(picks, 0); assert.equal(migrations.length, 0);
  assert.equal(page.storageLocation, 'internal'); assert.match(page.toasts[0], /应用内部/); assert.match(page.toasts[0], /导出/);
});
test('accepting folder authorization migrates only after a directory was selected', async () => {
  const page = subject(); dialogResult = async () => ({ index: 1 }); pickerResult = async () => 'file://docs/Documents';
  await page.requestStorageAfterFirstNote(); assert.equal(picks, 1); assert.deepEqual(migrations, ['file://docs/Documents']);
  assert.equal(page.storageLocation, 'external'); assert.equal(page.refreshes, 1); assert.equal(page.storageAccessBusy, false);
});
test('cancelling the directory picker leaves the committed note internal and does not repeat', async () => {
  const page = subject(); dialogResult = async () => ({ index: 1 });
  await page.requestStorageAfterFirstNote(); await page.requestStorageAfterFirstNote();
  assert.equal(picks, 1); assert.equal(migrations.length, 0); assert.equal(page.storageLocation, 'internal');
  assert.ok(page.toasts.some(text => /应用内部/.test(text))); assert.equal(page.storageAccessBusy, false);
});
test('picker denial keeps internal storage and a later explicit settings action can authorize it', async () => {
  const page = subject(); dialogResult = async () => ({ index: 1 }); pickerResult = async () => { throw new Error('denied'); };
  await page.requestStorageAfterFirstNote(); assert.equal(migrations.length, 0); assert.equal(page.storageAccessBusy, false);
  pickerResult = async () => 'file://docs/Later'; await page.chooseStorageFolder();
  assert.deepEqual(migrations, ['file://docs/Later']); assert.equal(page.storageLocation, 'external');
});
test('after cancelling the first picker, settings can authorize without repeating the first-note dialog', async () => {
  const page = subject(); dialogResult = async () => ({ index: 1 });
  await page.requestStorageAfterFirstNote(); assert.equal(picks, 1); assert.equal(page.storageLocation, 'internal');
  assert.ok(page.toasts.some(text => text.includes('设置 → 关于')));
  pickerResult = async () => 'file://docs/Later'; await page.chooseStorageFolder();
  await page.requestStorageAfterFirstNote(); assert.equal(dialogs.length, 1); assert.equal(picks, 2);
  assert.deepEqual(migrations, ['file://docs/Later']); assert.equal(page.storageLocation, 'external');
});
test('the phone permission offer explains the system directory and the About retry entry', async () => {
  const page = subject(); folderSelection = false; await page.requestStorageAfterFirstNote();
  assert.match(dialogs[0].message, /系统提供的应用文档目录/); assert.match(dialogs[0].message, /设置 → 关于/);
  assert.equal(dialogs[0].buttons[1].text, '授权文档目录'); assert.equal(picks, 0);
});
test('repeated settings taps share one picker and release the busy state after cancellation', async () => {
  const page = subject(); let finish;
  pickerResult = () => new Promise(resolve => { finish = resolve; });
  const first = page.chooseStorageFolder();
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  assert.equal(page.storageAccessBusy, true); await page.chooseStorageFolder(); assert.equal(picks, 1);
  finish(''); await first; assert.equal(page.storageAccessBusy, false); assert.equal(migrations.length, 0);
});
test('cancelling a manual change retains the configured external location without claiming internal storage', async () => {
  const page = subject(); pending = false; location = 'external'; page.storageLocation = 'external';
  await page.chooseStorageFolder(); assert.equal(migrations.length, 0); assert.equal(page.storageLocation, 'external');
  assert.equal(page.toasts.some(text => /应用内部/.test(text)), false); assert.ok(page.toasts.some(text => /原|现有/.test(text)));
});
test('closing the explanatory dialog is reported as internal storage without opening the picker', async () => {
  const page = subject(); dialogResult = async () => { throw new Error('dismissed'); };
  page.storageAccessChanged(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(picks, 0); assert.equal(page.storageAccessBusy, false); assert.ok(page.toasts.some(text => /应用内部/.test(text)));
});
test('overlapping first-note events cannot open duplicate permission dialogs', async () => {
  const page = subject(); let finish;
  dialogResult = () => new Promise(resolve => { finish = resolve; });
  const first = page.requestStorageAfterFirstNote();
  while (!finish) await new Promise(resolve => setImmediate(resolve));
  await page.requestStorageAfterFirstNote(); assert.equal(dialogs.length, 1); assert.equal(takes, 1);
  finish({ index: 0 }); await first; assert.equal(page.storageAccessBusy, false);
});
test('status-read failures release the permission UI guard for later settings retries', async () => {
  for (const entry of ['requestStorageAfterFirstNote', 'chooseStorageFolder']) {
    const page = subject(); statusError = true; await assert.rejects(page[entry](), /status unavailable/);
    assert.equal(page.storageAccessBusy, false, entry);
  }
});
(async () => {
  for (const [name, run] of tests) { await run(); console.log('PASS ' + name); }
  console.log(tests.length + ' storage permission flow groups passed. Dialog and picker presentation are mocked.');
})().catch(error => { console.error(error); process.exitCode = 1; });
