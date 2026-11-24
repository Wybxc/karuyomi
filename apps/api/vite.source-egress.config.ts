import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

export default defineConfig({
  ssr: { noExternal: true },
  build: {
    ssr: fileURLToPath(new URL('./source-egress/main.ts', import.meta.url)),
    target: 'node24',
    outDir: 'source-egress/dist',
    rollupOptions: { output: { entryFileNames: 'server.mjs' } },
  },
});
