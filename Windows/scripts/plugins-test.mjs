import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import { copyFileSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';

const require = createRequire(import.meta.url);
const electronPath = require('electron');

const ROOT = process.cwd();
const HARNESS_ZIP = process.env.LEXINOTE_HARNESS_ZIP || path.resolve(ROOT, '../plugins/harness/dist/harness-lexinote-harness.zip');
const WORK_DIR = path.join(ROOT, '.dsh-plugin-test');
const USER_DATA_DIR = path.join(WORK_DIR, 'user-data');
const FIXTURES_DIR = path.join(WORK_DIR, 'fixtures');

function crc32(buf) {
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) {
    crc ^= buf[i];
    for (let j = 0; j < 8; j += 1) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/**
 * Builds a standards-compliant ZIP archive from [{ name, data, externalAttr }].
 * Allows setting external POSIX mode bits (e.g. symlink) to verify security filters.
 */
function buildZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;

  for (const item of entries) {
    const nameBuf = Buffer.from(item.name, 'utf8');
    const raw = Buffer.isBuffer(item.data) ? item.data : Buffer.from(String(item.data), 'utf8');
    const compressed = deflateRawSync(raw);
    const sum = crc32(raw);
    const extAttr = item.externalAttr ?? ((0o100644 << 16) >>> 0);

    const local = Buffer.alloc(30 + nameBuf.length);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(0, 10);
    local.writeUInt16LE(0, 12);
    local.writeUInt32LE(sum, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    nameBuf.copy(local, 30);

    locals.push(local, compressed);

    const central = Buffer.alloc(46 + nameBuf.length);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE((3 << 8) | 20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(0, 14);
    central.writeUInt32LE(sum, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(extAttr, 38);
    central.writeUInt32LE(offset, 42);
    nameBuf.copy(central, 46);
    centrals.push(central);

    offset += local.length + compressed.length;
  }

  const centralBuf = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(0, 20);

  return Buffer.concat([...locals, centralBuf, eocd]);
}

function writeFixtures() {
  rmSync(WORK_DIR, { recursive: true, force: true });
  mkdirSync(USER_DATA_DIR, { recursive: true });
  mkdirSync(FIXTURES_DIR, { recursive: true });

  // 1. Native LexiNote test plugin ZIP (nested under single root folder to verify commonRoot)
  const nativeManifest = {
    format: 'lexinote-plugin',
    formatVersion: 1,
    id: 'test.native.suite',
    name: 'Native Test Suite',
    version: '1.0.0',
    apiVersion: '1.0',
    main: 'main.js',
    description: 'Comprehensive native SDK verification plugin',
    author: 'LexiNote Test',
    targets: ['windows', 'harmonyos'],
    capabilities: [
      'vault.read',
      'vault.write',
      'notes.metadata.read',
      'editor.read',
      'editor.write',
      'workspace.views',
      'ui.commands',
      'ui.views',
      'ui.notice',
      'plugin.storage'
    ]
  };
  const nativeMain = `'use strict';
const { definePlugin } = require('@lexinote/sdk');

module.exports = definePlugin({
  async activate(ctx) {
    const probes = {
      hasPreloadBridge: typeof globalThis.lexi !== 'undefined',
      unsupportedModuleBlocked: false,
      ungrantedVaultReadError: '',
      vaultModifiedEvents: []
    };
    try {
      require('fs');
    } catch (err) {
      probes.unsupportedModuleBlocked = String(err && err.message || err);
    }
    try {
      await ctx.vault.listMarkdown();
    } catch (err) {
      probes.ungrantedVaultReadError = String(err && err.message || err);
    }
    try {
      await ctx.storage.set('boot_probes', probes);
    } catch (err) {
      // storage.set may not yet be granted
    }

    ctx.subscriptions.add(ctx.events.on('vault.modified', async (ev) => {
      probes.vaultModifiedEvents.push(ev && ev.fileId ? ev.fileId : 'unknown');
      try {
        await ctx.storage.set('boot_probes', probes);
      } catch (e) {}
    }));

    ctx.subscriptions.add(ctx.views.register({
      id: 'native-panel',
      title: 'Native Panel',
      render(container) {
        container.replaceChildren();
        const heading = document.createElement('h3');
        heading.id = 'native-view-title';
        heading.textContent = 'Native Plugin Sandbox Ready';
        container.appendChild(heading);
        return () => {};
      }
    }));

    ctx.subscriptions.add(ctx.commands.register({
      id: 'run-vault-flow',
      title: 'Native: Run Vault Flow',
      async run() {
        const created = await ctx.vault.create('native-created.md', '# Native Note\\n\\nBody #native-tag [[Target]]');
        const readBack = await ctx.vault.read(created);
        const meta = await ctx.metadata.get(created);
        await ctx.workspace.openFile(created);
        await ctx.storage.set('vault_flow', {
          createdId: created.id,
          createdPath: created.path,
          readBack,
          headings: meta.headings.map((h) => h.heading),
          tags: meta.tags,
          links: meta.links.map((l) => l.link)
        });
        await ctx.ui.notice('Native Vault Flow OK');
      }
    }));

    ctx.subscriptions.add(ctx.commands.register({
      id: 'insert-editor-text',
      title: 'Native: Insert Into Editor',
      async run() {
        const before = await ctx.editor.active();
        const after = await ctx.editor.replaceSelection(' [INSERTED]');
        await ctx.storage.set('editor_flow', {
          hadActive: Boolean(before),
          noteId: before ? before.noteId : '',
          afterContent: after ? after.content : ''
        });
      }
    }));

    ctx.subscriptions.add(ctx.commands.register({
      id: 'probe-revoked-write',
      title: 'Native: Probe Revoked Write',
      async run() {
        let errorText = '';
        try {
          await ctx.vault.create('blocked-by-revoke.md', 'x');
        } catch (err) {
          errorText = String(err && err.message || err);
        }
        await ctx.storage.set('revoked_write_probe', { errorText });
      }
    }));

    ctx.subscriptions.add(ctx.commands.register({
      id: 'probe-path-traversal',
      title: 'Native: Probe Path Traversal',
      async run() {
        let errorText = '';
        try {
          await ctx.vault.create('../escape.md', 'bad');
        } catch (err) {
          errorText = String(err && err.message || err);
        }
        await ctx.storage.set('traversal_probe', { errorText });
      }
    }));

    ctx.subscriptions.add(ctx.commands.register({
      id: 'write-persist-check',
      title: 'Native: Write Persistent Key',
      async run() {
        const prev = (await ctx.storage.get('persist_count')) || { count: 0 };
        await ctx.storage.set('persist_count', { count: Number(prev.count || 0) + 1 });
      }
    }));
  },
  deactivate() {}
});
`;
  writeFileSync(
    path.join(FIXTURES_DIR, 'native-plugin.zip'),
    buildZip([
      { name: 'native-suite/manifest.json', data: JSON.stringify(nativeManifest, null, 2) },
      { name: 'native-suite/main.js', data: nativeMain }
    ])
  );

  // 2. Unpacked Obsidian plugin folder fixture
  const obsidianDir = path.join(FIXTURES_DIR, 'obsidian-compat-suite');
  mkdirSync(obsidianDir, { recursive: true });
  writeFileSync(
    path.join(obsidianDir, 'manifest.json'),
    JSON.stringify(
      {
        id: 'test-obsidian-suite',
        name: 'Obsidian Compat Suite',
        version: '1.0.0',
        minAppVersion: '1.4.0',
        description: 'Tests Obsidian Plugin, SettingTab, Modal, Notice, Vault, Platform, Ribbon & StatusBar',
        author: 'LexiNote Test',
        isDesktopOnly: true
      },
      null,
      2
    ),
    'utf8'
  );
  writeFileSync(
    path.join(obsidianDir, 'styles.css'),
    '.obs-box { padding: 8px; border: 1px solid var(--background-modifier-border); }',
    'utf8'
  );
  writeFileSync(
    path.join(obsidianDir, 'main.js'),
    `'use strict';
const {
  Plugin,
  PluginSettingTab,
  Setting,
  Modal,
  Notice,
  Platform,
  normalizePath,
  requestUrl
} = require('obsidian');

class TestModal extends Modal {
  onOpen() {
    this.setTitle('Obsidian Modal');
    this.setContent('Opened from ribbon click inside sandbox.');
  }
}

class TestSettingTab extends PluginSettingTab {
  display() {
    const { containerEl } = this;
    containerEl.empty();
    new Setting(containerEl)
      .setName('Greeting Prefix')
      .addText((text) => text.setValue(this.plugin.settings.prefix).onChange(async (val) => {
        this.plugin.settings.prefix = val;
        await this.plugin.saveSettings();
      }));
  }
}

module.exports = class TestObsidianPlugin extends Plugin {
  async onload() {
    this.settings = Object.assign({ prefix: 'OBS' }, await this.loadData());
    const statusItem = this.addStatusBarItem();
    statusItem.setText('OBS:ready');

    this.addRibbonIcon('star', 'Open Obsidian Test Modal', () => {
      new Notice('Ribbon modal opened');
      new TestModal(this.app).open();
    });

    this.addSettingTab(new TestSettingTab(this.app, this));

    this.addCommand({
      id: 'obsidian-run-compat',
      name: 'Obsidian: Run Compat Checks',
      callback: async () => {
        let adapterError = '';
        let requestUrlError = '';
        try {
          const unused = this.app.vault.adapter;
          void unused;
        } catch (err) {
          adapterError = String(err && err.message || err);
        }
        try {
          await requestUrl({ url: 'https://example.com' });
        } catch (err) {
          requestUrlError = String(err && err.message || err);
        }
        const norm = normalizePath('////a//b/../c.md');
        const created = await this.app.vault.create('obsidian-note.md', '# Obsidian Created');
        await this.app.vault.modify(created, '# Obsidian Modified');
        this.settings.report = {
          isDesktop: Platform.isDesktop,
          isDesktopApp: Platform.isDesktopApp,
          isMobile: Platform.isMobile,
          normalizedPath: norm,
          createdPath: created.path,
          adapterError,
          requestUrlError
        };
        await this.saveSettings();
        statusItem.setText('OBS:done');
        new Notice('Obsidian compat verified');
      }
    });
  }
  async saveSettings() {
    await this.saveData(this.settings);
  }
};
`,
    'utf8'
  );

  // 3. Malicious Zip-Slip ZIP
  writeFileSync(
    path.join(FIXTURES_DIR, 'malicious-slip.zip'),
    buildZip([
      { name: '../evil.js', data: 'console.log("pwned")' },
      { name: 'manifest.json', data: JSON.stringify(nativeManifest) },
      { name: 'main.js', data: 'module.exports = {};' }
    ])
  );

  // 4. Malicious Symlink ZIP
  writeFileSync(
    path.join(FIXTURES_DIR, 'malicious-symlink.zip'),
    buildZip([
      {
        name: 'symlink-entry.js',
        data: '/etc/passwd',
        externalAttr: ((0o120777 << 16) >>> 0)
      },
      { name: 'manifest.json', data: JSON.stringify(nativeManifest) },
      { name: 'main.js', data: 'module.exports = {};' }
    ])
  );

  if (existsSync(HARNESS_ZIP)) {
    copyFileSync(HARNESS_ZIP, path.join(FIXTURES_DIR, 'harness-lexinote-harness.zip'));
  }
  return {
    harnessExists: existsSync(HARNESS_ZIP)
  };
}

const info = writeFixtures();
console.log(`Fixtures prepared at ${FIXTURES_DIR} (harnessZip=${info.harnessExists})`);

const child = spawn(
  electronPath,
  ['.', '--no-sandbox', '--disable-gpu', '--disable-gpu-sandbox', '--disable-software-rasterizer'],
  {
    cwd: ROOT,
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '',
      LEXI_USER_DATA: USER_DATA_DIR,
      LEXI_DEMO_DATA: '1',
      LEXI_SMOKE_SCRIPT: path.join(ROOT, 'tests', 'plugins.js')
    },
    stdio: ['ignore', 'pipe', 'pipe']
  }
);

let stdoutBuf = '';
let stderrBuf = '';

child.stdout.on('data', (chunk) => {
  const text = chunk.toString();
  stdoutBuf += text;
  process.stdout.write(text);
});

child.stderr.on('data', (chunk) => {
  const text = chunk.toString();
  stderrBuf += text;
  process.stderr.write(text);
});

child.on('exit', (code) => {
  const resultMatch = stdoutBuf.match(/^SMOKE_RESULT\s+(\{.*\})$/m);
  const errorMatch = stdoutBuf.match(/^SMOKE_ERROR\s+(.*)$/m) || stderrBuf.match(/^SMOKE_ERROR\s+(.*)$/m);
  let passed = false;
  if (resultMatch) {
    try {
      const parsed = JSON.parse(resultMatch[1]);
      passed = parsed.passed === true && Array.isArray(parsed.failures) && parsed.failures.length === 0;
    } catch {
      passed = false;
    }
  }
  const finalCode = code && code !== 0 ? code : (!errorMatch && passed ? 0 : 1);
  rmSync(WORK_DIR, { recursive: true, force: true });
  console.log(`plugins-test exited with ${finalCode} (electronExit=${code ?? 0}, passed=${passed})`);
  process.exit(finalCode);
});
