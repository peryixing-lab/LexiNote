import { spawn, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { createServer } from 'vite';

const require = createRequire(import.meta.url);
const electronPath = require('electron');

const runtimeBuild = spawnSync('node', ['scripts/build-plugin-runtime.mjs'], { stdio: 'inherit' });
if (runtimeBuild.status !== 0) process.exit(runtimeBuild.status ?? 1);

const build = spawnSync('node', ['scripts/build-main.mjs'], { stdio: 'inherit' });
if (build.status !== 0) process.exit(build.status ?? 1);

const server = await createServer({ configFile: 'vite.config.ts' });
await server.listen();
const url = server.resolvedUrls?.local?.[0] ?? 'http://127.0.0.1:5273/';
console.log(`\nVite renderer at ${url}`);

const child = spawn(electronPath, ['.', '--no-sandbox'], {
  stdio: 'inherit',
  env: { ...process.env, ELECTRON_RUN_AS_NODE: '', VITE_DEV_SERVER_URL: url }
});

child.on('exit', async (code) => {
  await server.close();
  process.exit(code ?? 0);
});
