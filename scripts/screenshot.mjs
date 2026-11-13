import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const electronPath = require('electron');

const states = process.argv.slice(2).filter((argument) => !argument.startsWith('-'));
const outDir = process.env.LEXI_SHOT_DIR || path.join(process.cwd(), '.dsh-shot');
const dataDir = process.env.LEXI_USER_DATA || path.join(outDir, 'user-data');
const demoData = process.env.LEXI_DEMO_DATA ?? '1';
mkdirSync(outDir, { recursive: true });

const child = spawn(electronPath, ['.', '--no-sandbox', '--disable-gpu', '--disable-gpu-sandbox', '--disable-software-rasterizer'], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    ELECTRON_RUN_AS_NODE: '',
    ELECTRON_NO_ATTACH_CONSOLE: '',
    LEXI_SHOT_DIR: outDir,
    LEXI_USER_DATA: dataDir,
    LEXI_DEMO_DATA: demoData,
    LEXI_SHOT_STATES: (states.length ? states : ['workspace']).join(',')
  },
  stdio: 'inherit'
});

child.on('exit', (code) => {
  console.log(`electron exited with ${code}; screenshots in ${outDir}`);
  process.exit(code ?? 0);
});
