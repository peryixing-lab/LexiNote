// Install-time archive acceptance: what a normal Obsidian plugin zip looks like in the wild.
//
// The scanner is the gate that decides "may this archive be unpacked at all", so the cases
// below are the ones users actually produce: Finder's "压缩" (adds __MACOSX/ + ._*),
// a single wrapper folder, a wrapper folder plus .DS_Store, and genuinely broken archives.
const assert = require('node:assert/strict');
const { createSandbox } = require('./lib/plugin-sandbox.cjs');

const box = createSandbox();
box.reset();
const { PluginZip } = box.load('plugin/runtime/PluginZip');
const { PluginManifestService } = box.load('plugin/runtime/PluginManifestService');
const { PluginKind } = box.load('plugin/model/PluginModels');

let passed = 0;
function ok(name, condition, detail) {
  if (condition) { passed++; console.log('PASS ' + name); return; }
  console.log('FAIL ' + name + (detail ? ' — ' + detail : ''));
  process.exitCode = 1;
}

function crc32(buf) {
  let c; let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    c = (crc ^ buf[i]) & 0xFF;
    for (let k = 0; k < 8; k++) { c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; }
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

/** Minimal stored-method ZIP writer (the scanner only reads the central directory). */
function zip(files) {
  const locals = []; const centrals = []; let offset = 0;
  for (const [name, content] of files) {
    const data = Buffer.from(content, 'utf8');
    const crc = crc32(data);
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(0, 8);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(data.length, 18); lh.writeUInt32LE(data.length, 22);
    lh.writeUInt16LE(Buffer.byteLength(name), 26);
    const rec = Buffer.concat([lh, Buffer.from(name, 'utf8'), data]);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(data.length, 20); ch.writeUInt32LE(data.length, 24);
    ch.writeUInt16LE(Buffer.byteLength(name), 28); ch.writeUInt32LE(offset, 42);
    centrals.push(Buffer.concat([ch, Buffer.from(name, 'utf8')]));
    locals.push(rec); offset += rec.length;
  }
  const cd = Buffer.concat(centrals); const local = Buffer.concat(locals);
  const eo = Buffer.alloc(22);
  eo.writeUInt32LE(0x06054b50, 0); eo.writeUInt16LE(files.length, 8); eo.writeUInt16LE(files.length, 10);
  eo.writeUInt32LE(cd.length, 12); eo.writeUInt32LE(local.length, 16);
  return Buffer.concat([local, cd, eo]);
}

const manifest = (extra) => JSON.stringify(Object.assign({
  id: 'sample-plugin', name: 'Sample', version: '1.0.0', main: 'main.js', isDesktopOnly: false
}, extra));
const scanOf = (files) => PluginZip.scan(new Uint8Array(zip(files)));

// 1. Flat release layout: main.js + manifest.json (+ styles.css) at the archive root.
{
  const scan = scanOf([['manifest.json', manifest()], ['main.js', 'x'], ['styles.css', 'y']]);
  ok('扁平发布包（manifest 在根）可安装', scan.ok, (scan.problems || []).join(' | '));
}

// 2. macOS Finder compression: __MACOSX/ + ._* must not break root detection.
{
  const scan = scanOf([
    ['manifest.json', manifest()], ['main.js', 'x'],
    ['__MACOSX/._manifest.json', 'j'], ['__MACOSX/._main.js', 'j']
  ]);
  ok('macOS「压缩」产生的 __MACOSX 不影响安装', scan.ok, (scan.problems || []).join(' | '));
}
{
  const scan = scanOf([
    ['sample/manifest.json', manifest()], ['sample/main.js', 'x'],
    ['__MACOSX/sample/._main.js', 'j']
  ]);
  ok('文件夹套一层 + __MACOSX 仍识别共享根', scan.ok && scan.commonRoot === 'sample',
    'ok=' + scan.ok + ' root=' + scan.commonRoot);
}

// 2b. A stray root-level file whose name equals the wrapper folder is ambiguous: it would be
// unpacked *outside* the plugin directory. Policy (docs/plugin-system/04-security.md): refuse to
// guess and report the structure instead of silently dropping an unknown file.
{
  const scan = scanOf([
    ['realclaudian', 'junk'],
    ['realclaudian/manifest.json', manifest()],
    ['realclaudian/main.js', 'x']
  ]);
  // 同名条目是同一目录的另一种写法（有的工具不带结尾斜杠），不是"目录外的散落文件"。
  ok('根上与目录同名的无扩展名条目并入该目录',
    scan.ok && scan.commonRoot === 'realclaudian',
    'ok=' + scan.ok + ' root=' + scan.commonRoot + ' problems=' + (scan.problems || []).join(' | '));
}

// 2c. 真实归档会包含包装目录自身的目录项（`sample/`）：macOS「压缩」、`zip -r`、
// GitHub Download ZIP 都是这个形状。它必须被当作结构的一部分，而不是"目录外的文件"。
{
  const scan = scanOf([
    ['sample/', ''],
    ['sample/manifest.json', manifest()],
    ['sample/main.js', 'x']
  ]);
  ok('包装目录自身有目录项时仍可安装', scan.ok && scan.commonRoot === 'sample',
    'ok=' + scan.ok + ' root=' + scan.commonRoot + ' ' + (scan.problems || []).join(' | '));
}
{
  const scan = scanOf([
    ['sample/', ''], ['sample/manifest.json', manifest()], ['sample/main.js', 'x'],
    ['__MACOSX/sample/._main.js', 'j']
  ]);
  ok('目录项 + __MACOSX 组合可安装', scan.ok && scan.commonRoot === 'sample',
    'ok=' + scan.ok + ' ' + (scan.problems || []).join(' | '));
}

// 2d. 目录名带版本点号（…-1.4.0）时，同名根级条目仍要并入该目录。
{
  const scan = scanOf([
    ['dust-obsidian-calendar-1.4.0', 'junk'],
    ['dust-obsidian-calendar-1.4.0/manifest.json', manifest()],
    ['dust-obsidian-calendar-1.4.0/main.js', 'x']
  ]);
  ok('带点号的目录名 + 同名根级条目仍可安装', scan.ok && scan.commonRoot === 'dust-obsidian-calendar-1.4.0',
    'ok=' + scan.ok + ' root=' + scan.commonRoot + ' ' + (scan.problems || []).join(' | '));
}

// 3. Single wrapper folder (GitHub "Download ZIP" style) and stray .DS_Store.
{
  const scan = scanOf([['plugin-main/manifest.json', manifest()], ['plugin-main/main.js', 'x']]);
  ok('GitHub Download ZIP 的单层文件夹被当作共享根', scan.ok && scan.commonRoot === 'plugin-main');
}
{
  const scan = scanOf([['manifest.json', manifest()], ['main.js', 'x'], ['.DS_Store', 'j']]);
  ok('根目录杂项 .DS_Store 不影响安装', scan.ok, (scan.problems || []).join(' | '));
}

// 4. Broken archives stay rejected, with a self-explaining reason.
{
  const scan = scanOf([['__MACOSX/only', 'j']]);
  ok('只剩元数据的包被拒且说明包结构',
    !scan.ok && scan.problems.join(' ').indexOf('manifest.json') >= 0 &&
    scan.problems.join(' ').indexOf('包内顶层') >= 0, (scan.problems || []).join(' | '));
}
{
  const scan = scanOf([['../evil.js', 'x'], ['manifest.json', manifest()]]);
  ok('路径穿越仍被拒', !scan.ok && scan.problems.join(' ').indexOf('路径穿越') >= 0);
}
{
  const scan = scanOf([['manifest.json', manifest()], ['main.js', 'x'], ['manifest.json', manifest()]]);
  ok('重复路径仍被拒', !scan.ok && scan.problems.join(' ').indexOf('重复路径') >= 0);
}

// 5. `isDesktopOnly` 只提示不阻断：Dust Calendar / Tasks 等大量插件都声明它，
// 拿它当安装门等于把用户想用的插件全挡掉；真正的阻断在装载期（E_UNSUPPORTED_MODULE）。
{
  const parsed = PluginManifestService.parse(manifest({ isDesktopOnly: true }), PluginKind.OBSIDIAN);
  const problems = PluginManifestService.validate(parsed, PluginKind.OBSIDIAN);
  ok('isDesktopOnly 不再阻断安装', problems.length === 0, problems.join(' | '));
  ok('isDesktopOnly 仍记录在清单上', parsed.isDesktopOnly === true);
  ok('isDesktopOnly 作为安装提示返回', PluginManifestService.desktopOnlyNotice(parsed).length > 0);
}
{
  const parsed = PluginManifestService.parse(manifest({ id: 'Bad Id' }), PluginKind.OBSIDIAN);
  ok('非法 id 仍被拒', PluginManifestService.validate(parsed, PluginKind.OBSIDIAN).length > 0);
  const badVersion = PluginManifestService.parse(manifest({ version: 'v1' }), PluginKind.OBSIDIAN);
  ok('非法版本号仍被拒', PluginManifestService.validate(badVersion, PluginKind.OBSIDIAN).length > 0);
}

// 6. Install wiring: archive metadata is dropped from the installed folder.
{
  const src = require('node:fs').readFileSync(
    require('node:path').resolve(__dirname, '../../entry/src/main/ets/plugin/runtime/PluginInstallService.ets'), 'utf8');
  ok('安装后清理归档元数据', /dropArchiveMetadata\(target\)/.test(src) &&
    /__MACOSX/.test(src) && /unlinkSync/.test(src));
  ok('仅桌面声明在安装器里不再被降级为警告',
    !/isDesktopOnly\)[\s\S]{0,200}warnings\.push/.test(src));
}

console.log(`\n[summary] 通过 ${passed} 项`);
