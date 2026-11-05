import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import { nativeRuntimeAssets } from './vite.runtime-plugin.ts';

const directory = fileURLToPath(new URL('./', import.meta.url));

export default defineConfig({
  root: directory,
  publicDir: path.join(directory, 'public'),
  builder: { sharedConfigBuild: true },
  build: {
    target: 'es2022',
    minify: 'oxc',
    sourcemap: false,
    outDir: path.join(directory, 'dist'),
    emptyOutDir: false,
    copyPublicDir: false,
    rolldownOptions: {
      cwd: directory,
      output: { codeSplitting: false, comments: false },
    },
  },
  environments: {
    client: {
      consumer: 'client',
      build: {
        copyPublicDir: true,
        lib: {
          entry: 'src/host.ts',
          formats: ['es'],
          fileName: () => 'host.js',
        },
      },
    },
    webWorker: {
      consumer: 'client',
      build: {
        lib: {
          entry: 'src/worker.ts',
          name: 'KaruyomiWorker',
          formats: ['iife'],
          fileName: () => 'worker.js',
        },
      },
    },
    nativeHost: {
      consumer: 'client',
      build: {
        outDir: path.join(directory, 'dist/native'),
        lib: {
          entry: 'src/host.native.ts',
          name: 'KaruyomiNativeHost',
          formats: ['iife'],
          fileName: () => 'host.js',
        },
      },
    },
    nativeWorker: {
      consumer: 'client',
      build: {
        outDir: path.join(directory, 'dist/native'),
        lib: {
          entry: 'src/worker.ts',
          name: 'KaruyomiWorker',
          formats: ['iife'],
          fileName: () => 'worker.js',
        },
      },
    },
  },
  plugins: [await nativeRuntimeAssets()],
});
