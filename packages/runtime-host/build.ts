import { build, type BuildOptions } from 'esbuild';
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { digest, prepareMaterials } from './materials.ts';

const directory = fileURLToPath(new URL('./', import.meta.url));
const root = fileURLToPath(new URL('../../', import.meta.url));
const output = path.join(directory, 'dist');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
const { catalog, data } = await prepareMaterials(output);
const common = {
  absWorkingDir: directory,
  bundle: true,
  platform: 'browser',
  target: 'es2022',
  minify: true,
  write: false,
} satisfies BuildOptions;
const web = await Promise.all([
  build({ ...common, entryPoints: ['src/host.ts'], format: 'esm' }),
  build({ ...common, entryPoints: ['src/worker.ts'], format: 'iife' }),
]);
await writeFile(path.join(output, 'host.js'), web[0]!.outputFiles[0]!.contents);
await writeFile(
  path.join(output, 'worker.js'),
  web[1]!.outputFiles[0]!.contents,
);
await cp(
  path.join(directory, 'public/host.html'),
  path.join(output, 'host.html'),
);

// Each embedded value is decoded into fresh bytes. VerifiedLoader independently
// checks MIME, size and SHA on every use, and never falls back to a network read.
const embedded = Object.fromEntries(
  [...data].map(([sha256, value]) => [
    sha256,
    {
      base64: value.bytes.toString('base64'),
      contentType: value.contentType,
    },
  ]),
);
const nativeMaterialModule = `import {createNativeMaterialResolver} from ${JSON.stringify(path.join(directory, 'src/native-materials.ts'))};
const values=${JSON.stringify(embedded)};
export const nativeMaterials=createNativeMaterialResolver(values);`;
const nativeWorker = await build({
  ...common,
  entryPoints: ['src/worker.ts'],
  format: 'iife',
  plugins: [
    {
      name: 'embedded-native-materials',
      setup(builder) {
        builder.onResolve({ filter: /^\.\/materials\.js$/ }, () => ({
          path: 'materials',
          namespace: 'native-materials',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'native-materials' }, () => ({
          contents: nativeMaterialModule,
          loader: 'js',
          resolveDir: directory,
        }));
      },
    },
  ],
});
const nativeHost = await build({
  ...common,
  entryPoints: ['src/host.native.ts'],
  format: 'iife',
  define: {
    __KARUYOMI_MATERIAL_VERSION__: JSON.stringify(catalog.materialVersion),
  },
});
const nativeOutput = path.join(output, 'native');
await mkdir(nativeOutput, { recursive: true });
const nativeFiles = {
  host: { name: 'host.js', bytes: nativeHost.outputFiles[0]!.contents },
  worker: { name: 'worker.js', bytes: nativeWorker.outputFiles[0]!.contents },
};
const files: Record<string, { path: string; sha256: string; size: number }> =
  {};
for (const [key, { name, bytes }] of Object.entries(nativeFiles)) {
  await writeFile(path.join(nativeOutput, name), bytes);
  files[key] = { path: name, sha256: digest(bytes), size: bytes.length };
}
const nativeManifest = {
  schemaVersion: 1,
  protocolVersion: catalog.protocolVersion,
  hostAbi: catalog.hostAbi,
  runtimeBaseline: catalog.runtimeBaseline,
  materialVersion: catalog.materialVersion,
  files,
  materials: [...catalog.hostScripts, ...catalog.resources],
};
await writeFile(
  path.join(nativeOutput, 'manifest.json'),
  JSON.stringify(nativeManifest, null, 2) + '\n',
);

// Flutter consumes only these three generated files. Material bytes occur once,
// inside worker.js; the web static copies and audit files do not enter the app.
const flutterAssets = path.join(root, 'apps/reader/assets/runtime');
await mkdir(flutterAssets, { recursive: true });
for (const name of ['host.js', 'worker.js', 'manifest.json']) {
  await cp(path.join(nativeOutput, name), path.join(flutterAssets, name));
}
console.log(
  JSON.stringify({
    materialVersion: catalog.materialVersion,
    materials: data.size,
    nativeFiles: files,
  }),
);
