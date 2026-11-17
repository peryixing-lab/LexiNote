import { build } from 'esbuild';
import { cpSync, mkdirSync, rmSync } from 'node:fs';

rmSync('dist/main', { recursive: true, force: true });

const common = {
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node20',
  external: ['electron'],
  sourcemap: false,
  logLevel: 'info',
  define: {
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production')
  }
};

await build({
  ...common,
  entryPoints: ['src/main/main.ts'],
  outfile: 'dist/main/main.js'
});

await build({
  ...common,
  entryPoints: ['src/preload/preload.ts'],
  outfile: 'dist/main/preload.js'
});

mkdirSync('dist/main/katex', { recursive: true });
cpSync('node_modules/katex/dist/katex.min.css', 'dist/main/katex/katex.min.css');
cpSync('node_modules/katex/dist/fonts', 'dist/main/katex/fonts', { recursive: true });
