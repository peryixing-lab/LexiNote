// Exercise the shipped map routes without the retired agent runtime.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXI_TYPESCRIPT || '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const base = path.resolve(__dirname, '../../entry/src/main/ets');
const memo = new Map();
let notes = [], maps = [], savedMaps = [], exported = [];
const clone = value => value === undefined ? undefined : JSON.parse(JSON.stringify(value));
const storage = {
  init: async () => {}, getActiveVaultId: async () => 'v', getActiveProjectId: async () => 'other-project',
  getNotes: async () => clone(notes), getNoteById: async id => clone(notes.find(note => note.id === id)),
  getMindMapById: async id => clone(maps.find(map => map.id === id)),
  saveMindMap: async (_context, doc) => { const saved = clone(doc); saved.id ||= 'saved-map'; savedMaps.push(saved); return saved; },
  saveViaDocumentPicker: async (_context, name, content) => { exported.push({ name, content }); }
};
function load(relative) {
  const filename = path.resolve(base, relative) + '.ets';
  if (memo.has(filename)) return memo.get(filename);
  const js = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const mod = { exports: {} };
  vm.runInThisContext('(function(require,module,exports){' + js + '\n})')(
    spec => {
      if (spec.startsWith('@kit.')) return {};
      return load(path.relative(base, path.resolve(path.dirname(filename), spec)));
    }, mod, mod.exports);
  memo.set(filename, mod.exports);
  return mod.exports;
}
const { NoteItem, MindMapDoc, MindMapNode } = load('core/LexiModels');
const { MarkdownEngine } = load('core/MarkdownEngine');
function section(source, start, end) {
  const at = source.indexOf(start);
  const stop = source.indexOf(end, at);
  assert.ok(at >= 0 && stop > at, start);
  return source.slice(at, stop);
}
function methodsClass(source) {
  const js = ts.transpileModule('class MapRoute {' + source + '} module.exports = MapRoute;', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const mod = { exports: {} };
  vm.runInThisContext('(function(module,LexiStorageService,MindMapDoc,MarkdownEngine){' + js + '\n})')(
    mod, storage, MindMapDoc, MarkdownEngine);
  return mod.exports;
}
const index = fs.readFileSync(path.join(base, 'pages/Index.ets'), 'utf8');
const Desktop = methodsClass(section(index, '  private async createDesktopMap(', '  private openMap('));
const phone = fs.readFileSync(path.join(base, 'pages/MindMapPage.ets'), 'utf8');
const Phone = methodsClass(
  section(phone, '  private async loadFromRoute(', '  private pushSnapshot(') +
  section(phone, '  private persistAndRedraw(', '  private schedulePersistAndRedraw(') +
  section(phone, '  private async exportOutlineOrJson(', '  @Builder\n  topControlStrip('));
function fixture(projectId = '') {
  const note = new NoteItem(); note.id = 'source'; note.vaultId = 'v'; note.projectId = projectId;
  note.title = '源笔记'; note.content = '# 章节\n## 概念'; notes = [note];
  const map = new MindMapDoc(); map.id = 'existing'; map.vaultId = 'v'; map.projectId = projectId; map.title = '源导图';
  const node = new MindMapNode(); node.id = 'root'; node.text = '概念'; map.nodes = [node]; maps = [map];
  savedMaps = []; exported = [];
}
function phoneRoute() {
  return Object.assign(new Phone(), { context: () => ({}), selectNode() {}, relayoutAndDraw() {},
    toast() {}, saveTimer: -1 });
}
const tests = [
  ['phone conversions retain the source project, including the workspace root', async () => {
    for (const projectId of ['', 'source-project']) {
      fixture(projectId);
      await phoneRoute().loadFromRoute({ mapId: '', createNew: true, fromNoteId: 'source' });
      assert.equal(savedMaps[0].projectId, projectId);
      assert.equal(savedMaps[0].nodes[0].noteRefId, 'source');
    }
  }],
  ['editing a map from another project preserves its save destination', async () => {
    fixture('source-project'); const route = phoneRoute();
    await route.loadFromRoute({ mapId: 'existing', createNew: false, fromNoteId: '' });
    route.doc.title = '更新导图'; route.persistAndRedraw(); await Promise.resolve();
    assert.equal(savedMaps[0].projectId, 'source-project');
    assert.equal(savedMaps[0].title, '更新导图');
    assert.equal(maps[0].title, '源导图');
  }],
  ['map exports preserve project metadata and do not rewrite the source document', async () => {
    fixture('source-project'); const route = phoneRoute();
    await route.loadFromRoute({ mapId: 'existing', createNew: false, fromNoteId: '' });
    const before = JSON.stringify(route.doc);
    await route.exportOutlineOrJson(true); await route.exportOutlineOrJson(false);
    assert.equal(JSON.parse(exported[0].content).projectId, 'source-project');
    assert.equal(exported[0].name, '源导图.json');
    assert.equal(exported[1].content, MarkdownEngine.mindMapToMarkdownOutline(route.doc));
    assert.equal(JSON.stringify(route.doc), before); assert.equal(savedMaps.length, 0);
  }],
  ['desktop conversions retain the source workspace and project', async () => {
    for (const projectId of ['', 'source-project']) {
      fixture(projectId); notes[0].vaultId = 'source-vault';
      const desktop = Object.assign(new Desktop(), { activeVaultId: 'v', activeProjectId: 'other-project', context: () => ({}),
        desktopMapSaved() {}, openMap() {}, toast(message) { throw new Error(message); } });
      await desktop.createDesktopMap('source');
      assert.equal(savedMaps[0].vaultId, 'source-vault'); assert.equal(savedMaps[0].projectId, projectId);
    }
  }]
];
(async () => {
  for (const [name, run] of tests) { await run(); console.log('PASS ' + name); }
  console.log(`${tests.length} mind-map scope regression groups passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
