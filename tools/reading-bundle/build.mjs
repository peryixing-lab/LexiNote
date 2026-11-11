// Bundles the LexiNote reading kernel into a single file and copies it (plus the
// skeleton stylesheet) into the app rawfile directory.
import { build } from 'esbuild';
import { copyFile, mkdir, readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const bundlesDir = path.join(here, 'bundles');
const outfile = path.join(bundlesDir, 'reading.js');
const cssSource = path.join(here, 'src', 'reading.css');
const rawfileDir = path.resolve(here, '../../entry/src/main/resources/rawfile');
const rawTarget = path.join(rawfileDir, 'lexinote_reading.js');
const cssTarget = path.join(rawfileDir, 'lexinote_reading.css');
const MAX_BUNDLE_BYTES = 150 * 1024;

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

await mkdir(bundlesDir, { recursive: true });
await build({
  entryPoints: [path.join(here, 'src', 'main.js')],
  outfile,
  bundle: true,
  format: 'iife',
  target: ['es2019'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  logLevel: 'warning'
});

await mkdir(rawfileDir, { recursive: true });
await copyFile(outfile, rawTarget);
await copyFile(cssSource, cssTarget);

const bundleBytes = await readFile(outfile);
const cssBytes = await readFile(cssTarget);
const info = await stat(outfile);
const gzipBytes = gzipSync(bundleBytes).length;
const bundleSha = sha256(bundleBytes);
const rawSha = sha256(await readFile(rawTarget));

console.log('[reading-bundle] bundles/reading.js     ' + info.size + ' bytes (' + (info.size / 1024).toFixed(1) + ' KB), gzip ' + gzipBytes + ' bytes');
console.log('[reading-bundle] sha256(bundle)          ' + bundleSha);
console.log('[reading-bundle] copied -> rawfile/lexinote_reading.js, sha256 matches: ' + (bundleSha === rawSha));
console.log('[reading-bundle] rawfile/lexinote_reading.css ' + cssBytes.length + ' bytes, sha256 ' + sha256(cssBytes));

if (info.size > MAX_BUNDLE_BYTES) {
  console.error('[reading-bundle] bundle exceeds ' + MAX_BUNDLE_BYTES + ' bytes (pre-gzip)');
  process.exitCode = 1;
}
