import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const directory = fileURLToPath(new URL('./', import.meta.url));
const root = fileURLToPath(new URL('../../', import.meta.url));
const clientId = '\0karuyomi:image-codec-client';

// Candidate UI codecs are a separate CLI target. Product and Native builds do
// not invoke it or publish these optional assets.
export default defineConfig({
  root: directory,
  publicDir: false,
  builder: { sharedConfigBuild: true },
  build: {
    outDir: path.join(directory, '.local/image-codecs'),
    copyPublicDir: false,
    target: 'es2022',
    minify: 'oxc',
    sourcemap: false,
    rolldownOptions: {
      cwd: root,
      output: { codeSplitting: false, comments: false },
    },
  },
  environments: {
    client: {
      consumer: 'client',
      build: {
        emptyOutDir: true,
        rolldownOptions: { input: clientId },
        lib: { entry: clientId, formats: ['es'], fileName: () => 'client.js' },
      },
    },
    worker: {
      consumer: 'client',
      build: {
        emptyOutDir: false,
        lib: {
          entry: path.join(root, 'runtime/image-codec/worker.ts'),
          formats: ['es'],
          fileName: () => 'worker.js',
        },
      },
    },
  },
  plugins: [
    {
      name: 'karuyomi-image-codec-exports',
      resolveId(source) {
        if (source === clientId) return clientId;
      },
      load(id) {
        if (id === clientId)
          return ['client', 'assets']
            .map(
              (name) =>
                `export * from ${JSON.stringify(path.join(root, 'runtime/image-codec', name + '.ts'))};`,
            )
            .join('\n');
      },
      generateBundle(_options, bundle) {
        const outputs = Object.values(bundle);
        const script = outputs[0];
        if (
          outputs.length !== 1 ||
          script?.type !== 'chunk' ||
          !script.isEntry ||
          script.imports.length ||
          script.dynamicImports.length
        )
          throw new Error(
            'Candidate image codec must be a self-contained single script',
          );
      },
    },
  ],
});
