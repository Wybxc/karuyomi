import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, type EnvironmentOptions } from 'vite';
import { runtimeMaterialAssets } from './vite.runtime-plugin.ts';

const directory = fileURLToPath(new URL('./', import.meta.url));
const root = fileURLToPath(new URL('../../', import.meta.url));

// The official app builder visits environments in this order. Only the first
// clears dist; the final bridge hook emits the catalog only after all five scripts succeed.
const environments: Record<string, EnvironmentOptions> = Object.fromEntries(
  ['crypto', 'zstd', 'graphics', 'cache', 'file'].map((name, index) => [
    index === 0 ? 'client' : name,
    {
      consumer: 'client',
      build: {
        outDir: path.join(directory, 'dist'),
        emptyOutDir: index === 0,
        copyPublicDir: false,
        target: 'es2022',
        minify: false,
        sourcemap: false,
        lib: {
          entry: 'virtual:karuyomi-runtime-bridge/' + name,
          name: 'KaruyomiBridge',
          formats: ['iife'],
          fileName: () => 'bridge.js',
        },
        rolldownOptions: {
          cwd: root,
          input: 'virtual:karuyomi-runtime-bridge/' + name,
          output: { codeSplitting: false, comments: false },
        },
      },
    } satisfies EnvironmentOptions,
  ]),
);

export default defineConfig({
  root: directory,
  publicDir: false,
  builder: { sharedConfigBuild: true },
  environments,
  plugins: [runtimeMaterialAssets()],
  define: { 'import.meta.url': 'self.location.origin' },
});
