'use strict';

/**
 * Regression: Obsidian compatibility shim (real classes, identity, sync listings,
 * async vault I/O, events, plugin lifecycle, editor offset math, explicit unsupported
 * surfaces).
 *
 * Run with:
 *   /Applications/DevEco-Studio.app/Contents/tools/node/bin/node \
 *     scripts/tests/plugin-obsidian-regression.cjs
 */

const assert = require('node:assert/strict');
const {
  createRuntime,
  createSuite,
  makeFile
} = require('./lib/js-runtime-harness.cjs');

const suite = createSuite('plugin-obsidian-regression');

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function pluginSource(body, imports) {
  return `${imports || "const { Plugin } = require('obsidian');"}
class TestPlugin extends Plugin {
  async onload() {
    globalThis.__obsPlugin = this;
    ${body || ''}
  }
  async onunload() {
    globalThis.__obsUnloaded = true;
  }
}
module.exports = new TestPlugin();`;
}

async function bootPlugin(options) {
  const handle = createRuntime({ contents: options.contents });
  const result = await handle.boot({
    kind: 'obsidian',
    sourceCode: options.sourceCode,
    files: options.files || [],
    activeFile: options.activeFile,
    editor: options.editor
  });
  assert.equal(result.ok, true, `obsidian boot failed: ${result.error || ''}`);
  return { handle, api: handle.obsidian, plugin: globalThis.__obsPlugin };
}

function expectCode(fn, code, message) {
  let caught = null;
  try {
    fn();
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, message || `expected ${code}`);
  assert.equal(caught.code, code, `${message || ''} (got ${caught.message})`.trim());
  return caught;
}

suite.test('getMarkdownFiles() is synchronous, returns real TFiles and keeps identity', async () => {
  const files = [
    makeFile('f1', 'notes/a.md'),
    makeFile('f2', 'b.md'),
    makeFile('f3', 'image.png')
  ];
  const { handle, api, plugin } = await bootPlugin({
    files,
    activeFile: files[0],
    sourceCode: pluginSource('')
  });
  try {
    const vault = plugin.app.vault;
    const markdown = vault.getMarkdownFiles();
    assert.ok(Array.isArray(markdown), 'getMarkdownFiles must return an array');
    assert.equal(typeof markdown.then, 'undefined', 'getMarkdownFiles must not return a Promise');
    assert.equal(markdown.length, 2);
    for (const file of markdown) {
      assert.ok(file instanceof api.TFile, 'every entry must be a real TFile');
      assert.ok(file instanceof api.TAbstractFile);
      assert.equal(vault.getAbstractFileByPath(file.path), file, 'listing identity must hold');
    }
    assert.equal(vault.getAbstractFileByPath('image.png') instanceof api.TFile, true);
    assert.equal(vault.getAbstractFileByPath('missing.md'), null);
    assert.equal(vault.getRoot().isRoot(), true);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('read/modify/append/create/rename/delete are async and call the matching RPC', async () => {
  const file = makeFile('f1', 'notes/a.md', { mtime: 1000 });
  const { handle, plugin } = await bootPlugin({
    files: [file],
    activeFile: file,
    contents: { f1: 'hello' },
    sourceCode: pluginSource('')
  });
  const { host } = handle;
  try {
    const vault = plugin.app.vault;
    const target = vault.getAbstractFileByPath('notes/a.md');

    const readPromise = vault.read(target);
    assert.equal(typeof readPromise.then, 'function', 'read() must be async');
    assert.equal(await readPromise, 'hello');
    const readCall = host.findCall('vault.readText');
    assert.deepEqual(readCall.params, { vaultId: 'vault-1', fileId: 'f1' });

    await vault.modify(target, 'updated');
    const writeCall = host.findCall('vault.writeText');
    assert.deepEqual(writeCall.params, {
      vaultId: 'vault-1',
      fileId: 'f1',
      content: 'updated',
      expectedUpdatedAt: 1000
    });
    assert.equal(target.stat.mtime, 1001, 'TFile.stat must follow the host mtime');
    assert.equal(await vault.cachedRead(target), 'updated');
    assert.equal(host.callsTo('vault.readText').length, 1, 'cachedRead must not re-read');

    await vault.append(target, '!');
    const writes = host.callsTo('vault.writeText');
    assert.equal(writes.length, 2);
    assert.equal(writes[1].params.content, 'updated!');
    assert.equal(writes[1].params.expectedUpdatedAt, 1001);

    const created = await vault.create('fresh.md', 'new content');
    assert.ok(created instanceof handle.obsidian.TFile);
    assert.equal(host.findCall('vault.createText').params.path, 'fresh.md');
    assert.ok(vault.getMarkdownFiles().some((item) => item.path === 'fresh.md'));

    const renamed = await vault.rename(created, 'renamed.md');
    assert.equal(renamed, created, 'rename keeps the TFile instance');
    assert.equal(renamed.path, 'renamed.md');
    assert.equal(vault.getAbstractFileByPath('renamed.md'), created);
    assert.equal(host.findCall('vault.renameText').params.newPath, 'renamed.md');

    await vault.delete(created, true);
    assert.equal(host.callsTo('vault.deleteText').length, 1);
    assert.equal(vault.getAbstractFileByPath('renamed.md'), null);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('vault/workspace events deliver the same TFile instance and EventRef.off() detaches', async () => {
  const files = [makeFile('f1', 'notes/a.md'), makeFile('f2', 'b.md')];
  const { handle, api, plugin } = await bootPlugin({
    files,
    activeFile: files[0],
    sourceCode: pluginSource('')
  });
  const { host } = handle;
  try {
    const vault = plugin.app.vault;
    let created = null;
    const createRef = vault.on('create', (file) => {
      created = file;
    });
    assert.equal(typeof createRef.off, 'function');
    assert.ok(
      host.callsTo('events.on').some((call) => call.params.event === 'vault.created'),
      'vault.on(create) must ask the host for vault.created'
    );
    assert.equal(host.emit('vault.created', { fileId: 'f3', path: 'new.md' }), true);
    assert.ok(created instanceof api.TFile);
    assert.equal(created.path, 'new.md');
    assert.equal(vault.getAbstractFileByPath('new.md'), created, 'event and listing identity must match');

    createRef.off();
    await delay(5);
    assert.ok(host.callsTo('events.off').length > 0, 'EventRef.off() must release the host subscription');
    host.emit('vault.created', { fileId: 'f4', path: 'ignored.md' });
    assert.equal(created.path, 'new.md', 'EventRef.off() must stop delivery');

    let rawEventFile = null;
    vault.on('create', (file) => {
      rawEventFile = file;
    });
    assert.equal(handle.runtime.receiveEvent(JSON.stringify({
      event: 'vault.created',
      seq: 99,
      fileId: 'f5',
      path: 'raw.md',
      oldPath: '',
      vaultId: 'vault-1',
      revision: 5
    })), true, 'the raw ArkTS event shape must be accepted');
    assert.ok(rawEventFile instanceof api.TFile);
    assert.equal(rawEventFile.path, 'raw.md');
    assert.equal(vault.getAbstractFileByPath('raw.md'), rawEventFile);

    let renamed = null;
    let renamedFrom = '';
    vault.on('rename', (file, oldPath) => {
      renamed = file;
      renamedFrom = oldPath;
    });
    host.emit('vault.renamed', { fileId: 'f3', path: 'renamed.md', oldPath: 'new.md' });
    assert.ok(renamed instanceof api.TFile);
    assert.equal(renamed.path, 'renamed.md');
    assert.equal(renamedFrom, 'new.md');
    assert.equal(vault.getAbstractFileByPath('renamed.md'), renamed);

    const beforeDelete = vault.getAbstractFileByPath('renamed.md');
    let deleted = null;
    vault.on('delete', (file) => {
      deleted = file;
    });
    host.emit('vault.deleted', { fileId: 'f3', path: 'renamed.md' });
    assert.equal(deleted, beforeDelete, 'delete must reuse the previously listed instance');
    assert.equal(vault.getAbstractFileByPath('renamed.md'), null);

    let opened = null;
    plugin.app.workspace.on('file-open', (file) => {
      opened = file;
    });
    host.setActiveFile('f2');
    host.emit('workspace.active-file-changed', { fileId: 'f2', path: 'b.md' });
    assert.ok(opened instanceof api.TFile);
    assert.equal(opened.path, 'b.md');
    assert.equal(plugin.app.workspace.getActiveFile(), opened);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('Plugin subclass supports commands/notices/data/interval and refuses UI surfaces', async () => {
  globalThis.__obsUnloaded = false;
  const source = `${"const { Plugin, Notice } = require('obsidian');"}
class LifecyclePlugin extends Plugin {
  async onload() {
    globalThis.__obsPlugin = this;
    this.registerInterval(setInterval(() => {}, 1000));
    this.addCommand({ id: 'hello', name: 'Hello', callback: () => new Notice('你好，知萤') });
  }
  async onunload() {
    globalThis.__obsUnloaded = true;
  }
}
module.exports = new LifecyclePlugin();`;
  const { handle, api, plugin } = await bootPlugin({ files: [makeFile('f1', 'a.md')], sourceCode: source });
  try {
    assert.ok(plugin instanceof api.Plugin);
    assert.ok(plugin instanceof api.Component);
    assert.equal(plugin.app, plugin.app);

    const register = handle.host.findCall('commands.register');
    assert.deepEqual(register.params, { id: 'hello', title: 'Hello' });

    assert.equal(handle.runtime.runCommand('obsidian.hello:hello'), true);
    await delay(10);
    assert.equal(handle.host.state.notices.length, 1);
    assert.equal(handle.host.state.notices[0].message, '你好，知萤');
    assert.deepEqual(api.__notices, ['你好，知萤']);

    await plugin.saveData({ theme: 'dark' });
    const save = handle.host.findCall('storage.set');
    assert.deepEqual(save.params, { key: 'plugin-data', value: '{"theme":"dark"}' });
    assert.deepEqual(await plugin.loadData(), { theme: 'dark' });

    expectCode(() => plugin.addRibbonIcon('icon', 'title'), 'E_UNSUPPORTED_API', 'addRibbonIcon');
    expectCode(() => plugin.addStatusBarItem(), 'E_UNSUPPORTED_API', 'addStatusBarItem');
    expectCode(() => plugin.addSettingTab({}), 'E_UNSUPPORTED_API', 'addSettingTab');
    expectCode(() => plugin.registerView('x', {}), 'E_UNSUPPORTED_API', 'registerView');
    expectCode(() => plugin.registerMarkdownPostProcessor(() => {}), 'E_UNSUPPORTED_API', 'registerMarkdownPostProcessor');
    expectCode(() => plugin.registerEditorExtension([]), 'E_UNSUPPORTED_API', 'registerEditorExtension');
    expectCode(() => plugin.registerDomEvent(null, 'click', () => {}), 'E_UNSUPPORTED_API', 'registerDomEvent');

    let added = 0;
    let removed = 0;
    const element = {
      addEventListener() {
        added += 1;
      },
      removeEventListener() {
        removed += 1;
      }
    };
    plugin.registerDomEvent(element, 'click', () => {});
    assert.equal(added, 1);
    assert.equal(plugin._intervals.size, 1, 'registerInterval must track the timer');

    await handle.runtime.unload();
    assert.equal(globalThis.__obsUnloaded, true, 'onunload must run');
    assert.equal(removed, 1, 'unload must detach DOM listeners');
    assert.equal(plugin._intervals.size, 0, 'unload must clear tracked intervals');
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('Notice sends ui.notice and Platform reports HarmonyOS mobile', async () => {
  const { handle, api } = await bootPlugin({ files: [makeFile('f1', 'a.md')], sourceCode: pluginSource('') });
  try {
    assert.deepEqual(api.Platform, {
      isDesktopApp: false,
      isMobile: true,
      isAndroidApp: false,
      isIosApp: false,
      isMacOS: false,
      isWin: false,
      isLinux: false,
      isPhone: true,
      isTablet: false,
      isDesktop: false,
      isHarmonyOS: true
    });
    assert.equal(api.Platform.isDesktopApp, false);

    const notice = new api.Notice('platform notice', 500);
    assert.equal(handle.host.state.notices.length, 1);
    assert.deepEqual(handle.host.state.notices[0], { message: 'platform notice', timeoutMs: 500 });
    assert.deepEqual(api.__notices, ['platform notice']);
    notice.hide();
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('Editor offset math is correct over CRLF, CJK and emoji', async () => {
  const content = '第一行\r\n第二行😀\r\nabc';
  const file = makeFile('f1', 'notes/a.md');
  const { handle, api, plugin } = await bootPlugin({
    files: [file],
    activeFile: file,
    contents: { f1: content },
    editor: {
      editorId: 'editor-1',
      noteId: 'f1',
      vaultId: 'vault-1',
      windowId: 'window-1',
      revision: 3,
      baseContent: content,
      content,
      dirty: false,
      readOnly: false,
      focused: true
    },
    sourceCode: pluginSource('')
  });
  try {
    const view = plugin.app.workspace.getActiveViewOfType(api.MarkdownView);
    assert.ok(view instanceof api.MarkdownView, 'active view must be a MarkdownView');
    assert.equal(view.file, plugin.app.workspace.getActiveFile());
    const editor = view.editor;
    assert.ok(editor instanceof api.Editor);

    assert.equal(editor.getValue(), content);
    assert.equal(editor.lineCount(), 3);
    assert.equal(editor.getLine(0), '第一行');
    assert.equal(editor.getLine(1), '第二行😀');
    assert.equal(editor.getLine(2), 'abc');
    assert.equal(editor.getLine(9), '');

    // UTF-16 offsets: CJK = 1 unit, emoji = 2 units, CRLF = 2 units.
    assert.equal(editor.posToOffset({ line: 0, ch: 0 }), 0);
    assert.equal(editor.posToOffset({ line: 1, ch: 0 }), 5);
    assert.equal(editor.posToOffset({ line: 1, ch: 2 }), 7);
    assert.equal(editor.posToOffset({ line: 1, ch: 3 }), 8);
    assert.equal(editor.posToOffset({ line: 1, ch: 5 }), 10);
    assert.equal(editor.posToOffset({ line: 2, ch: 1 }), 13);
    assert.deepEqual(editor.offsetToPos(0), { line: 0, ch: 0 });
    assert.deepEqual(editor.offsetToPos(7), { line: 1, ch: 2 });
    assert.deepEqual(editor.offsetToPos(10), { line: 1, ch: 5 });
    assert.deepEqual(editor.offsetToPos(13), { line: 2, ch: 1 });

    assert.deepEqual(editor.getSelection(), {
      anchor: { line: 0, ch: 0 },
      head: { line: 0, ch: 0 }
    });
    editor.setSelection({ line: 1, ch: 3 }, { line: 1, ch: 5 });
    assert.deepEqual(editor.getSelection(), {
      anchor: { line: 1, ch: 3 },
      head: { line: 1, ch: 5 }
    });
    assert.deepEqual(editor.getCursor(), { line: 1, ch: 5 });
    assert.deepEqual(editor.getCursor('anchor'), { line: 1, ch: 3 });

    await editor.replaceRange('X', { line: 1, ch: 3 }, { line: 1, ch: 5 });
    assert.equal(editor.getValue(), '第一行\r\n第二行X\r\nabc');
    assert.deepEqual(editor.getSelection(), {
      anchor: { line: 1, ch: 4 },
      head: { line: 1, ch: 4 }
    });
    assert.equal(handle.host.state.editor.content, '第一行\r\n第二行X\r\nabc');
    assert.equal(handle.host.findCall('editor.replaceAll').params.expectedVersion, 3);

    handle.host.state.editorSelection = { from: 0, to: 0 };
    editor.setSelection({ line: 0, ch: 0 }, { line: 0, ch: 0 });
    await editor.replaceSelection('X');
    assert.equal(editor.getValue(), 'X第一行\r\n第二行X\r\nabc');

    const revision = handle.host.state.editorRevision;
    await editor.setValue('新内容');
    assert.equal(editor.getValue(), '新内容');
    assert.equal(handle.host.callsTo('editor.replaceAll').slice(-1)[0].params.expectedVersion, revision);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('MetadataCache exposes the supported subset and resolves link paths', async () => {
  const a = makeFile('f1', 'notes/a.md');
  const b = makeFile('f2', 'b.md');
  const { handle, api, plugin } = await bootPlugin({
    files: [a, b],
    activeFile: a,
    contents: {
      f1: '# 标题\n[[b]] #标签',
      f2: '# B'
    },
    sourceCode: pluginSource('')
  });
  try {
    assert.ok(handle.context, 'runtime diagnostic context must be available');
    await handle.context.metadata.get('notes/a.md');
    const vault = plugin.app.vault;
    const file = vault.getAbstractFileByPath('notes/a.md');
    const cache = plugin.app.metadataCache.getFileCache(file);
    assert.ok(cache, 'cache must be filled after metadata.get');
    assert.equal(cache.headings.length, 1);
    assert.deepEqual(cache.headings[0], { heading: '标题', level: 1 });
    assert.equal(cache.links[0].link, 'b');
    assert.deepEqual(cache.tags, [{ tag: '标签' }]);
    assert.equal('sections' in cache, false, 'unsupported members must be absent');
    assert.equal('frontmatter' in cache, false, 'frontmatter object is not fabricated');
    assert.ok(plugin.app.metadataCache.getCache('notes/a.md'));

    const resolved = plugin.app.metadataCache.getFirstLinkpathDest('b', 'notes/a.md');
    assert.equal(resolved, b ? vault.getAbstractFileByPath('b.md') : null);
    assert.equal(plugin.app.metadataCache.getFirstLinkpathDest('does-not-exist', ''), null);
  } finally {
    await handle.runtime.unload();
  }
});

suite.test('unsupported modules and classes raise explicit E_ codes, never silent no-ops', async () => {
  const { handle, api, plugin } = await bootPlugin({ files: [makeFile('f1', 'a.md')], sourceCode: pluginSource('') });
  try {
    expectCode(() => new api.Modal(), 'E_UNSUPPORTED_API', 'Modal');
    expectCode(() => new api.Setting(), 'E_UNSUPPORTED_API', 'Setting');
    expectCode(() => new api.PluginSettingTab(), 'E_UNSUPPORTED_API', 'PluginSettingTab');
    expectCode(() => api.requestUrl({ url: 'https://example.com' }), 'E_UNSUPPORTED_API', 'requestUrl');
    expectCode(() => plugin.app.vault.adapter, 'E_UNSUPPORTED_API', 'Vault.adapter');
    expectCode(() => plugin.app.workspace.getLeavesOfType('markdown'), 'E_UNSUPPORTED_API', 'getLeavesOfType');

    expectCode(
      () => handle.modules.loader.executeBundle("require('fs');", {}),
      'E_UNSUPPORTED_MODULE',
      'require(fs)'
    );
    expectCode(
      () => handle.modules.loader.executeBundle("require('obsidian');", {}),
      'E_UNSUPPORTED_MODULE',
      'missing obsidian module'
    );

    // module.exports forms work exactly like CommonJS.
    assert.deepEqual(handle.modules.loader.executeBundle('exports.a = 1;', {}), { a: 1 });
    assert.equal(handle.modules.loader.executeBundle('module.exports = 42;', {}), 42);
  } finally {
    await handle.runtime.unload();
  }
});

suite.run().then((summary) => {
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}).catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
