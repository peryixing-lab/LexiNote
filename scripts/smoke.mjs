import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import { mkdirSync, rmSync } from 'node:fs';

const require = createRequire(import.meta.url);
const electronPath = require('electron');
const dataDir = path.join(process.cwd(), '.dsh-smoke', 'user-data');
rmSync(path.join(process.cwd(), '.dsh-smoke'), { recursive: true, force: true });
mkdirSync(dataDir, { recursive: true });

const child = spawn(
  electronPath,
  ['.', '--no-sandbox', '--disable-gpu', '--disable-gpu-sandbox', '--disable-software-rasterizer'],
  {
    cwd: process.cwd(),
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '',
      LEXI_USER_DATA: dataDir,
      LEXI_DEMO_DATA: '1',
      LEXI_SMOKE_SCRIPT: path.join(process.cwd(), 'tests', 'smoke.js')
    },
    stdio: 'inherit'
  }
);

child.on('exit', (code) => {
  console.log(`smoke exited with ${code}`);
  process.exit(code ?? 0);
});
