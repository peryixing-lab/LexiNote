import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

/**
 * Cross-builds the Windows packages from macOS/Linux as well as Windows.
 *
 * electron-builder downloads Electron and its own helpers into the user cache
 * directory. On locked-down machines that directory can be unwritable, so the
 * script keeps every cache inside the repository and points HOME at a local
 * folder on macOS. Nothing outside the repository is modified.
 */

const args = process.argv.slice(2);
const requested = args.filter((argument) => ['x64', 'arm64', 'ia32'].includes(argument));
const archs = requested.length > 0 ? requested : ['x64', 'arm64', 'ia32'];
const dirOnly = args.includes('--dir');
const root = process.cwd();

const env = {
  ...process.env,
  ELECTRON_CACHE: path.join(root, '.electron-cache'),
  ELECTRON_BUILDER_CACHE: path.join(root, '.eb-cache')
};

if (process.platform === 'darwin') {
  const home = path.join(root, '.build-home');
  mkdirSync(home, { recursive: true });
  env.HOME = home;
}

if (process.env.LEXI_ELECTRON_MIRROR) {
  env.ELECTRON_MIRROR = process.env.LEXI_ELECTRON_MIRROR;
}

function run(command, args) {
  console.log(`\n$ ${command} ${args.join(' ')}`);
  const result = spawnSync(command, args, { stdio: 'inherit', env, cwd: root, shell: process.platform === 'win32' });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

run('npm', ['run', 'build']);
run('npx', [
  'electron-builder',
  '--win',
  ...archs.map((arch) => `--${arch}`),
  ...(dirOnly ? ['--dir'] : []),
  '--publish',
  'never'
]);
console.log(`\nWindows packages for ${archs.join(', ')} are in ${path.join(root, 'release')}`);
