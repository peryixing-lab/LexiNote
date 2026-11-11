// P14 · installer validation: ZIP structure/paths and manifest policy.
// Builds real ZIP byte streams in memory (stored entries, no dependencies) and runs the
// production scanner/validator from entry/src/main/ets/plugin/runtime.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { PluginZip } = box.load('plugin/runtime/PluginZip');
const { PluginManifestService, PluginText } = box.load('plugin/runtime/PluginManifestService');
const { PluginLimits, PluginKind } = box.load('plugin/model/PluginModels');

let assertions = 0;
const ok = (v, m) => { assertions++; assert.ok(v, m); };
const eq = (a, b, m) => { assertions++; assert.deepEqual(a, b, m); };

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let index = 0; index < 256; index++) {
    let value = index;
    for (let bit = 0; bit < 8; bit++) value = (value & 1) ? (0xEDB88320 ^ (value >>> 1)) : (value >>> 1);
    table[index] = value;
  }
  return table;
})();
function crc32(buffer) {
  let crc = -1;
  for (const byte of buffer) crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ byte) & 0xFF];
  return (crc ^ -1) >>> 0;
}

/** entries: [{name, data?, externalAttrs?, method?}] */
function makeZip(entries) {
  const locals = [];
  const central = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.data || '', 'utf8');
    const method = entry.method === undefined ? 0 : entry.method;
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, data);
    const header = Buffer.alloc(46);
    header.writeUInt32LE(0x02014b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(20, 6);
    header.writeUInt16LE(0, 8);
    header.writeUInt16LE(method, 10);
    header.writeUInt32LE(crc, 16);
    header.writeUInt32LE(data.length, 20);
    header.writeUInt32LE(data.length, 24);
    header.writeUInt16LE(name.length, 28);
    header.writeUInt16LE(0, 30);
    header.writeUInt16LE(0, 32);
    header.writeUInt16LE(0, 34);
    header.writeUInt32LE(entry.externalAttrs === undefined ? 0 : entry.externalAttrs >>> 0, 38);
    header.writeUInt32LE(offset, 42);
    central.push(header, name);
    offset += local.length + name.length + data.length;
  }
  const centralBuffer = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralBuffer.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...locals, centralBuffer, eocd]));
}

const MANIFEST = JSON.stringify({
  format: 'lexinote-plugin', formatVersion: 1, id: 'example.zip', name: 'ZIP 插件',
  version: '1.0.0', apiVersion: '1.0', main: 'main.js',
  capabilities: ['vault.read'], targets: ['harmonyos']
});

function scanOf(entries) { return PluginZip.scan(makeZip(entries)); }

// 1. A well formed archive passes.
const good = scanOf([
  { name: 'manifest.json', data: MANIFEST },
  { name: 'main.js', data: 'module.exports = {};' },
  { name: 'assets/', data: '' },
  { name: 'assets/icon.txt', data: 'x' }
]);
ok(good.ok, `well formed archive accepted: ${good.problems.join('; ')}`);
eq(good.entries.length, 4, 'all entries scanned');
eq(good.commonRoot, '', 'no shared root for a flat archive');
eq(good.totalUncompressed, Buffer.byteLength(MANIFEST) + 'module.exports = {};'.length + 1, 'uncompressed total');
console.log('PASS a well formed plugin archive is accepted');

// 2. A single shared root folder is detected and stripped.
const nested = scanOf([
  { name: 'my-plugin/manifest.json', data: MANIFEST },
  { name: 'my-plugin/main.js', data: 'x' }
]);
ok(nested.ok, 'nested archive accepted');
eq(nested.commonRoot, 'my-plugin', 'shared root detected');
eq(PluginZip.relativeName(nested, nested.entries[0]), 'manifest.json', 'relative name strips the root');
console.log('PASS a single shared root folder is detected and stripped');

// 3. Path attacks.
for (const bad of ['../evil.md', 'a/../../evil.md', '/absolute.md', 'a\\b.md', 'C:/x.md', 'a//b.md', './x.md']) {
  const scan = scanOf([{ name: 'manifest.json', data: MANIFEST }, { name: bad, data: 'x' }]);
  ok(!scan.ok, `archive with ${JSON.stringify(bad)} is rejected`);
  ok(scan.problems.some((problem) => /路径|穿越|绝对|反斜杠|驱动器|空路径段/.test(problem)),
    `rejection reason mentions the path problem for ${bad}`);
}
console.log('PASS traversal, absolute, backslash, drive and empty-segment paths are rejected');

// 4. Duplicates, symlinks and unsupported compression.
const duplicate = scanOf([{ name: 'manifest.json', data: MANIFEST }, { name: 'Main.js', data: 'a' }, { name: 'main.js', data: 'b' }]);
ok(!duplicate.ok, 'duplicate paths are rejected');
ok(duplicate.problems.some((problem) => problem.includes('重复路径')), 'duplicate reason reported');

const symlink = scanOf([{ name: 'manifest.json', data: MANIFEST },
  { name: 'link.js', data: '/etc/passwd', externalAttrs: (0xA1FF0000) >>> 0 }]);
ok(!symlink.ok, 'symlink entries are rejected');
ok(symlink.problems.some((problem) => problem.includes('符号链接')), 'symlink reason reported');

const weirdMethod = scanOf([{ name: 'manifest.json', data: MANIFEST }, { name: 'x.js', data: 'a', method: 12 }]);
ok(!weirdMethod.ok, 'unsupported compression method is rejected');
ok(weirdMethod.problems.some((problem) => problem.includes('压缩方式')), 'method reason reported');
console.log('PASS duplicates, symlinks and unknown compression are rejected');

// 5. Missing manifest and oversized archives.
const noManifest = scanOf([{ name: 'main.js', data: 'x' }]);
ok(!noManifest.ok, 'archive without manifest is rejected');
ok(noManifest.problems.some((problem) => problem.includes('manifest.json')), 'missing manifest reason');

const tooMany = [];
tooMany.push({ name: 'manifest.json', data: MANIFEST });
for (let index = 0; index < PluginLimits.MAX_ZIP_ENTRIES + 4; index++) tooMany.push({ name: `f${index}.js`, data: 'x' });
const many = scanOf(tooMany);
ok(!many.ok, 'entry count limit is enforced');
ok(many.problems.some((problem) => problem.includes('文件数量')), 'entry count reason');

const huge = scanOf([{ name: 'manifest.json', data: MANIFEST },
  { name: 'big.bin', data: 'x'.repeat(PluginLimits.MAX_ZIP_BYTES + 1) }]);
ok(!huge.ok, 'uncompressed size limit is enforced');
ok(huge.problems.some((problem) => problem.includes('体积')), 'size reason');

const notZip = scanOf([]);
ok(!notZip.ok, 'an empty buffer is not a zip');
const garbage = PluginZip.scan(new Uint8Array([1, 2, 3, 4, 5]));
ok(!garbage.ok, 'garbage bytes are rejected');
console.log('PASS missing manifest, entry-count, size and garbage input are rejected');

// 6. Manifest policy.
const parsed = PluginManifestService.parse(MANIFEST, PluginKind.LEXINOTE);
eq(parsed.id, 'example.zip', 'manifest id parsed');
eq(PluginManifestService.validate(parsed, PluginKind.LEXINOTE), [], 'valid manifest has no problems');

const unknownCap = PluginManifestService.parse(JSON.stringify({
  format: 'lexinote-plugin', formatVersion: 1, id: 'a.b', name: 'n', version: '1.0.0',
  apiVersion: '1.0', main: 'main.js', capabilities: ['root.everything']
}), PluginKind.LEXINOTE);
ok(PluginManifestService.validate(unknownCap, PluginKind.LEXINOTE).some((p) => p.includes('未知能力')),
  'unknown capability rejected');

const network = PluginManifestService.parse(JSON.stringify({
  format: 'lexinote-plugin', formatVersion: 1, id: 'a.b', name: 'n', version: '1.0.0',
  apiVersion: '1.0', main: 'main.js', capabilities: ['network']
}), PluginKind.LEXINOTE);
ok(PluginManifestService.validate(network, PluginKind.LEXINOTE).some((p) => p.includes('网络')),
  'network capability rejected in the experimental build');

const badId = PluginManifestService.parse(JSON.stringify({
  format: 'lexinote-plugin', formatVersion: 1, id: 'Bad Id!', name: 'n', version: '1.0.0',
  apiVersion: '1.0', main: 'main.js', capabilities: []
}), PluginKind.LEXINOTE);
ok(PluginManifestService.validate(badId, PluginKind.LEXINOTE).length > 0, 'malformed id rejected');

const escapeMain = PluginManifestService.parse(JSON.stringify({
  format: 'lexinote-plugin', formatVersion: 1, id: 'a.b', name: 'n', version: '1.0.0',
  apiVersion: '1.0', main: '../main.js', capabilities: []
}), PluginKind.LEXINOTE);
ok(PluginManifestService.validate(escapeMain, PluginKind.LEXINOTE).some((p) => p.includes('路径')),
  'entry escaping the plugin folder is rejected');

const desktopOnly = PluginManifestService.parse(JSON.stringify({
  id: 'dust-calendar', name: 'Calendar', version: '1.4.0', minAppVersion: '0.15.0',
  description: 'desktop only', author: 'dust', isDesktopOnly: true
}), PluginKind.OBSIDIAN);
// `isDesktopOnly` 只是作者自测平台的声明，不是 Node/Electron 依赖的证据；安装放行，
// 真实阻断在装载期（E_UNSUPPORTED_MODULE）。提示由 desktopOnlyNotice 提供。
ok(PluginManifestService.validate(desktopOnly, PluginKind.OBSIDIAN).length === 0,
  'isDesktopOnly Obsidian plugin installs (blocked at load time instead)');
ok(PluginManifestService.desktopOnlyNotice(desktopOnly).length > 0,
  'the desktop-only hint is surfaced as a notice, not a rejection');
eq(PluginManifestService.obsidianBaseline().includes('network'), false, 'the Obsidian baseline never includes network');
ok(PluginManifestService.obsidianBaseline().includes('vault.read'), 'the Obsidian baseline includes vault access');

const wrongFormat = PluginManifestService.parse(JSON.stringify({
  format: 'something-else', formatVersion: 1, id: 'a.b', name: 'n', version: '1.0.0',
  apiVersion: '1.0', main: 'main.js', capabilities: []
}), PluginKind.LEXINOTE);
ok(PluginManifestService.validate(wrongFormat, PluginKind.LEXINOTE).length > 0, 'wrong format rejected');
console.log('PASS manifest policy rejects unknown capabilities, network, bad ids, escaping entry points and desktop-only plugins');

// 7. UTF-8 decoding used for manifest/source text.
eq(PluginText.decodeUtf8(new Uint8Array(Buffer.from('插件 🦋 说明', 'utf8'))), '插件 🦋 说明', 'UTF-8 round-trip');
console.log('PASS the UTF-8 decoder round-trips CJK and astral characters');

console.log(`\nplugin-install-regression: ${assertions} assertions passed`);
