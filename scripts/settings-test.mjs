import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

const require = createRequire(import.meta.url);
const reduced = process.argv.includes('--reduced-motion');
const dataDir = mkdtempSync(path.join(tmpdir(), 'lexinote-settings-'));
const child = spawn(require('electron'), [
  '.', '--no-sandbox', '--disable-gpu', '--disable-background-timer-throttling',
  '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
  ...(reduced ? ['--force-prefers-reduced-motion'] : [])
], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    ELECTRON_RUN_AS_NODE: '',
    LEXI_USER_DATA: dataDir,
    LEXI_DEMO_DATA: '1',
    LEXI_SMOKE_SCRIPT: path.join(process.cwd(), 'tests/settings-sheets.js')
  },
  stdio: ['ignore', 'pipe', 'pipe']
});

let output = '';
child.stdout.on('data', (chunk) => {
  output += chunk.toString();
  process.stdout.write(chunk);
});
child.stderr.pipe(process.stderr);
const timeout = setTimeout(() => child.kill(), 45000);
child.on('error', (error) => {
  console.error(error);
  process.exitCode = 1;
});
child.on('exit', (code) => {
  clearTimeout(timeout);
  rmSync(dataDir, { recursive: true, force: true });
  const match = output.match(/^SMOKE_RESULT (\{.*\})$/m);
  const result = match ? JSON.parse(match[1]) : null;
  const passed = code === 0 && result?.passed && result.reducedMotion === reduced;
  console.log(`settings-test: ${passed ? 'PASS' : 'FAIL'} (${reduced ? 'reduced' : 'normal'} motion)`);
  process.exitCode = passed ? 0 : 1;
});
