import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const electronPath = require('electron');
const root = process.cwd();
const dataDir = path.join(root, '.dsh-flush', 'user-data');
rmSync(path.join(root, '.dsh-flush'), { recursive: true, force: true });
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
      LEXI_AUTOCLOSE_EXIT: '1',
      LEXI_DEMO_DATA: '1',
      LEXI_SCRIPT: path.join(root, 'tests', 'flush.js')
    },
    stdio: 'inherit'
  }
);

child.on('exit', (code) => {
  try {
    const raw = readFileSync(path.join(dataDir, 'lexinote-data.json'), 'utf8');
    const saved = /FLUSH_\d+/.test(raw);
    console.log(saved ? 'FLUSH_RESULT saved=true' : 'FLUSH_RESULT saved=false');
    process.exit(saved ? 0 : 1);
  } catch (error) {
    console.error('FLUSH_RESULT saved=false', error);
    process.exit(code ?? 1);
  }
});
