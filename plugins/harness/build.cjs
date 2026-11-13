#!/usr/bin/env node
'use strict';

/**
 * Builds the Harness plugin:
 *
 *   src/*.js  ->  dist/main.js   (single CommonJS bundle, only `@lexinote/sdk` external)
 *   manifest.json -> dist/manifest.json
 *   dist/harness-lexinote-harness.zip  (manifest.json + main.js at the ZIP root)
 * The application does not bundle Harness; users install the standalone ZIP.
 *
 * No external bundler is required: modules are wrapped in a tiny registry, relative
 * requires are rewritten, and anything that would reach outside the whitelist fails the
 * build instead of failing at install time.
 *
 * Usage:
 *   node plugins/harness/build.cjs          # build the standalone distribution
 *   node plugins/harness/build.cjs --check  # fail when committed outputs are stale
 */

const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const HERE = __dirname;
const ROOT = path.resolve(HERE, '../..');
const SRC_DIR = path.join(HERE, 'src');
const DIST_DIR = path.join(HERE, 'dist');
const BUNDLE_PATH = path.join(DIST_DIR, 'main.js');
const ZIP_PATH = path.join(DIST_DIR, 'harness-lexinote-harness.zip');
const MANIFEST_PATH = path.join(HERE, 'manifest.json');

const MAX_MAIN_BYTES = 2 * 1024 * 1024;
const MAX_TOTAL_BYTES = 16 * 1024 * 1024;

function listModules() {
  return fs.readdirSync(SRC_DIR)
    .filter((name) => name.endsWith('.js'))
    .sort()
    .map((name) => `src/${name.slice(0, -3)}`);
}

function readModule(id) {
  return fs.readFileSync(path.join(HERE, `${id}.js`), 'utf8');
}

function rewriteRelativeRequires(id, source) {
  return source.replace(/require\(['"]markdown-it['"]\)/g, "__require('vendor/markdown-it')")
    .replace(/require\(\s*(['"])(\.\/[^'"]+)\1\s*\)/g, (match, quote, specifier) => {
    const target = path.posix.normalize(path.posix.join(path.posix.dirname(id), specifier));
    if (!target.startsWith('src/')) {
      throw new Error(`${id}: relative require escapes src/: ${specifier}`);
    }
    return `__require('${target.replace(/\.js$/, '')}')`;
  });
}

function buildBundle() {
  const modules = listModules();
  if (modules.indexOf('src/main') < 0) {
    throw new Error('src/main.js is required');
  }
  const chunks = [];
  chunks.push('/*');
  chunks.push(' * LexiNote Harness plugin — GENERATED FILE, DO NOT EDIT.');
  chunks.push(' * Source: plugins/harness/src/*.js');
  chunks.push(' * Rebuild: node plugins/harness/build.cjs');
  chunks.push(' *');
  chunks.push(' * The host loader provides exactly one module: @lexinote/sdk.');
  chunks.push(' */');
  chunks.push('(function () {');
  chunks.push("  'use strict';");
  chunks.push('  var __modules = Object.create(null);');
  chunks.push('  var __cache = Object.create(null);');
  chunks.push('  function __define(id, factory) {');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__modules, id)) {');
  chunks.push("      throw new Error('E_PROTOCOL: duplicate module ' + id);");
  chunks.push('    }');
  chunks.push('    __modules[id] = factory;');
  chunks.push('  }');
  // Reuse the repository's pinned markdown-it 14.1.0 dependency. No remote scripts.
  const markdownRoot = path.join(HERE, 'node_modules/markdown-it');
  const markdownPackage = JSON.parse(fs.readFileSync(path.join(markdownRoot, 'package.json'), 'utf8'));
  if (markdownPackage.version !== '14.1.0') { throw new Error('Harness requires markdown-it 14.1.0'); }
  const markdown = fs.readFileSync(path.join(markdownRoot, 'dist/markdown-it.min.js'), 'utf8');
  const markdownLicense = fs.readFileSync(path.join(markdownRoot, 'LICENSE'), 'utf8');
  const notices = fs.readFileSync(path.join(HERE, 'THIRD_PARTY_NOTICES.txt'), 'utf8');
  chunks.push(`/* Third-party notices:\n${markdownLicense}\n${notices}\n*/`);
  chunks.push("  __define('vendor/markdown-it', function (module, exports) {");
  chunks.push(markdown);
  chunks.push('  });');
  chunks.push('  function __require(id) {');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__cache, id)) { return __cache[id].exports; }');
  chunks.push('    var factory = __modules[id];');
  chunks.push("    if (!factory) { throw new Error('E_UNSUPPORTED_MODULE: ' + id); }");
  chunks.push('    var module = { exports: {} };');
  chunks.push('    __cache[id] = module;');
  chunks.push('    factory(module, module.exports, __require);');
  chunks.push('    return module.exports;');
  chunks.push('  }');
  for (const id of modules) {
    const source = rewriteRelativeRequires(id, readModule(id));
    chunks.push(`  __define('${id}', function (module, exports, __require) {`);
    chunks.push(source.replace(/\r\n/g, '\n').replace(/\n$/, ''));
    chunks.push('  });');
  }
  chunks.push("  module.exports = __require('src/main');");
  chunks.push('})();');
  chunks.push('');
  const bundle = chunks.join('\n');

  const leftovers = [];
  const pattern = /\brequire\(\s*(['"])([^'"]+)\1\s*\)/g;
  let match = pattern.exec(bundle);
  while (match) {
    if (match[2] !== '@lexinote/sdk') {
      leftovers.push(match[2]);
    }
    match = pattern.exec(bundle);
  }
  if (leftovers.length > 0) {
    throw new Error(`bundle still requires unsupported modules: ${leftovers.join(', ')}`);
  }
  const bytes = Buffer.byteLength(bundle, 'utf8');
  if (bytes > MAX_MAIN_BYTES) {
    throw new Error(`main.js is ${bytes} bytes, over the 2 MiB limit`);
  }
  return bundle;
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value;
  }
  return table;
})();

function crc32(buffer) {
  let value = -1;
  for (let index = 0; index < buffer.length; index += 1) {
    value = CRC_TABLE[(value ^ buffer[index]) & 0xff] ^ (value >>> 8);
  }
  return (value ^ -1) >>> 0;
}

function dosTime(date) {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
  const day = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time, day };
}

/** Minimal ZIP writer (deflate), enough for the documented install format. */
function createZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  // Fixed DOS timestamp so rebuilds are byte-identical (--check must not depend on wall time).
  const now = { time: 0, day: ((2026 - 1980) << 9) | (1 << 5) | 1 };
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const raw = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data, 'utf8');
    const compressed = zlib.deflateRawSync(raw, { level: 9 });
    const crc = crc32(raw);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(now.time, 10);
    local.writeUInt16LE(now.day, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, compressed);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(now.time, 12);
    central.writeUInt16LE(now.day, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(0, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);

    offset += local.length + name.length + compressed.length;
  }
  const centralStart = offset;
  const centralBuffer = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuffer.length, 12);
  end.writeUInt32LE(centralStart, 16);
  end.writeUInt16LE(0, 20);
  return Buffer.concat([...locals, centralBuffer, end]);
}

function writeIfChanged(file, data, checkMode, stale) {
  const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data, 'utf8');
  const exists = fs.existsSync(file);
  const same = exists && fs.readFileSync(file).equals(buffer);
  if (checkMode) {
    if (!same) { stale.push(path.relative(ROOT, file)); }
    return;
  }
  if (!same) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, buffer);
  }
}

function main() {
  const args = new Set(process.argv.slice(2));
  const checkMode = args.has('--check');
  const stale = [];

  const manifest = fs.readFileSync(MANIFEST_PATH, 'utf8');
  JSON.parse(manifest);
  const bundle = buildBundle();

  writeIfChanged(BUNDLE_PATH, bundle, checkMode, stale);
  writeIfChanged(path.join(DIST_DIR, 'manifest.json'), manifest, checkMode, stale);

  const zip = createZip([
    { name: 'manifest.json', data: manifest },
    { name: 'main.js', data: bundle }
  ]);
  if (zip.length > MAX_TOTAL_BYTES) {
    throw new Error(`plugin zip is ${zip.length} bytes, over the 16 MiB limit`);
  }
  writeIfChanged(ZIP_PATH, zip, checkMode, stale);

  if (checkMode) {
    if (stale.length > 0) {
      console.error(`Harness plugin outputs are stale:\n  ${stale.join('\n  ')}`);
      console.error('Run: node plugins/harness/build.cjs');
      process.exit(1);
    }
    console.log('Harness plugin outputs are up to date.');
    return;
  }

  const modules = listModules();
  console.log(`Built ${modules.length} modules -> ${path.relative(ROOT, BUNDLE_PATH)} (${Buffer.byteLength(bundle)} bytes)`);
  console.log(`Plugin zip -> ${path.relative(ROOT, ZIP_PATH)} (${zip.length} bytes)`);
}

main();
