import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, rmSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const electronPath = require('electron');
const root = process.cwd();
const outDir = path.join(root, '.dsh-empty');
const dataDir = path.join(outDir, 'user-data');
rmSync(outDir, { recursive: true, force: true });
mkdirSync(dataDir, { recursive: true });

const child = spawn(
  electronPath,
  ['.', '--no-sandbox', '--disable-gpu', '--disable-gpu-sandbox', '--disable-software-rasterizer'],
  {
    cwd: root,
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '',
      LEXI_USER_DATA: dataDir,
      LEXI_DEMO_DATA: '',
      LEXI_SMOKE_SCRIPT: path.join(root, 'tests', 'empty.js')
    }
  }
);

let output = '';
child.stdout.on('data', (chunk) => {
  output += String(chunk);
  process.stdout.write(chunk);
});
child.stderr.on('data', (chunk) => {
  output += String(chunk);
  process.stderr.write(chunk);
});

child.on('exit', (code) => {
  const matched = output.match(/SMOKE_RESULT (\{.*\})/);
  const ui = matched ? JSON.parse(matched[1]) : null;
  let data = null;
  for (let attempt = 0; attempt < 20 && !data; attempt += 1) {
    try {
      data = JSON.parse(readFileSync(path.join(dataDir, 'lexinote-data.json'), 'utf8'));
    } catch {
      // The first renderer save may still be settling.
    }
  }
  const summary = data
    ? {
        notes: data.notes?.length ?? -1,
        maps: data.maps?.length ?? -1,
        canvases: data.canvases?.length ?? -1,
        projects: data.projects?.length ?? -1,
        vaults: (data.vaults ?? []).map((vault) => ({ name: vault.name, openMode: vault.openMode }))
      }
    : null;
  console.log(`EMPTY_RESULT ${JSON.stringify({ ui, data: summary })}`);
  const ok =
    !!ui &&
    ui.noteRows === 0 &&
    ui.tabs === 0 &&
    ui.spaceRows === 0 &&
    !!data &&
    data.notes.length === 0 &&
    data.maps.length === 0 &&
    data.canvases.length === 0 &&
    data.projects.length === 0 &&
    data.vaults.length === 1;
  process.exit(ok ? 0 : 1);
});
