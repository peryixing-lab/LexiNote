#!/usr/bin/env node
'use strict';

/**
 * Builds `entry/src/main/resources/rawfile/plugin-runtime/runtime.bundle.js` from the
 * seven CommonJS modules under `packages/plugin-runtime-js/src/`.
 *
 * The emitted file is a single IIFE with an id-keyed module registry:
 *
 *   (function () {
 *     'use strict';
 *     var __modules = Object.create(null);
 *     var __cache = Object.create(null);
 *     function __define(id, factory) { __modules[id] = factory; }
 *     function __require(id) { ... }
 *     __define('util', function (module, exports, require) { ...source... });
 *     ...
 *     __require('runtime');
 *   })();
 *
 * Usage:
 *   node scripts/build-plugin-runtime.cjs           # write the bundle
 *   node scripts/build-plugin-runtime.cjs --check   # fail when the committed bundle is stale
 */

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const SRC_DIR = path.join(ROOT, 'packages/plugin-runtime-js/src');
const OUTPUT = path.join(ROOT, 'entry/src/main/resources/rawfile/plugin-runtime/runtime.bundle.js');

/** Dependency order: a module may only require modules listed before it. */
const MODULES = [
  'util',
  'mirror',
  'bridge',
  'loader',
  'sdk',
  'ui',
  'obsidian',
  'runtime'
];

function readModule(id) {
  const file = path.join(SRC_DIR, `${id}.js`);
  if (!fs.existsSync(file)) {
    throw new Error(`missing runtime module: ${path.relative(ROOT, file)}`);
  }
  return fs.readFileSync(file, 'utf8');
}

function buildBundle() {
  const chunks = [];
  chunks.push('/*');
  chunks.push(' * LexiNote JavaScript plugin runtime — GENERATED FILE, DO NOT EDIT.');
  chunks.push(' * Source: packages/plugin-runtime-js/src/*.js');
  chunks.push(' * Rebuild: node scripts/build-plugin-runtime.cjs');
  chunks.push(' *');
  chunks.push(' * The bundle is loaded by entry/src/main/resources/rawfile/plugin-runtime/index.html');
  chunks.push(' * inside an ArkWeb WebView. It is a trusted-code runtime, not a sandbox.');
  chunks.push(' */');
  chunks.push('(function () {');
  chunks.push("  'use strict';");
  chunks.push('  var __modules = Object.create(null);');
  chunks.push('  var __cache = Object.create(null);');
  chunks.push('  function __define(id, factory) {');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__modules, id)) {');
  chunks.push("      throw new Error('E_PROTOCOL: duplicate runtime module ' + id);");
  chunks.push('    }');
  chunks.push('    __modules[id] = factory;');
  chunks.push('  }');
  chunks.push('  function __resolve(specifier) {');
  chunks.push('    if (typeof specifier !== \'string\' || specifier.length === 0) {');
  chunks.push("      throw new Error('E_UNSUPPORTED_MODULE: ' + String(specifier));");
  chunks.push('    }');
  chunks.push('    if (specifier.charAt(0) === \'.\') {');
  chunks.push("      return specifier.replace(/^\\.\\//, '').replace(/\\.js$/, '');");
  chunks.push('    }');
  chunks.push("    throw new Error('E_UNSUPPORTED_MODULE: ' + specifier);");
  chunks.push('  }');
  chunks.push('  function __require(id) {');
  chunks.push('    if (!Object.prototype.hasOwnProperty.call(__modules, id)) {');
  chunks.push("      throw new Error('E_UNSUPPORTED_MODULE: ' + id);");
  chunks.push('    }');
  chunks.push('    if (Object.prototype.hasOwnProperty.call(__cache, id)) {');
  chunks.push('      return __cache[id].exports;');
  chunks.push('    }');
  chunks.push('    var module = { exports: {} };');
  chunks.push('    __cache[id] = module;');
  chunks.push('    __modules[id](module, module.exports, function (specifier) {');
  chunks.push('      return __require(__resolve(specifier));');
  chunks.push('    }, id + \'.js\', \'/\');');
  chunks.push('    return module.exports;');
  chunks.push('  }');
  for (let index = 0; index < MODULES.length; index += 1) {
    const id = MODULES[index];
    const source = readModule(id);
    chunks.push('');
    chunks.push(`  // ---- module: ${id} ----`);
    chunks.push(`  __define('${id}', function (module, exports, require) {`);
    chunks.push(source.replace(/\s+$/, ''));
    chunks.push('  });');
  }
  chunks.push('');
  chunks.push("  __require('runtime');");
  chunks.push('})();');
  chunks.push('');
  return chunks.join('\n');
}

function formatBytes(bytes) {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  return `${(bytes / 1024).toFixed(1)} KiB (${bytes} B)`;
}

function main() {
  const check = process.argv.includes('--check');
  let bundle;
  try {
    bundle = buildBundle();
  } catch (error) {
    console.error(`build-plugin-runtime: ${error.message}`);
    process.exitCode = 1;
    return;
  }
  const bytes = Buffer.byteLength(bundle, 'utf8');
  const relativeOutput = path.relative(ROOT, OUTPUT);

  if (check) {
    if (!fs.existsSync(OUTPUT)) {
      console.error(`build-plugin-runtime: stale — ${relativeOutput} does not exist`);
      process.exitCode = 1;
      return;
    }
    const current = fs.readFileSync(OUTPUT, 'utf8');
    if (current !== bundle) {
      console.error(
        `build-plugin-runtime: stale — ${relativeOutput} differs from packages/plugin-runtime-js/src; ` +
        'run node scripts/build-plugin-runtime.cjs'
      );
      process.exitCode = 1;
      return;
    }
    console.log(`build-plugin-runtime: up to date — ${relativeOutput} (${formatBytes(bytes)})`);
    return;
  }

  fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
  fs.writeFileSync(OUTPUT, bundle, 'utf8');
  console.log(`build-plugin-runtime: wrote ${relativeOutput} (${formatBytes(bytes)})`);
}

main();
