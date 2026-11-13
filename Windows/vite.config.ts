import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The renderer is a plain web bundle. Electron loads it over file:// in production,
// so every asset URL has to stay relative.
export default defineConfig({
  root: 'src/renderer',
  base: './',
  plugins: [react()],
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
    target: 'chrome120',
    assetsInlineLimit: 0,
    sourcemap: false
  },
  server: {
    port: 5273,
    strictPort: true
  }
});
