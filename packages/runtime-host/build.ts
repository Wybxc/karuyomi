import { build, type InlineConfig } from 'vite';
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { digest, nativeMaterialGroups, prepareMaterials } from './materials.ts';

const directory = fileURLToPath(new URL('./', import.meta.url));
const output = path.join(directory, 'dist');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
const { catalog, data } = await prepareMaterials(output);
const nativeGroups = nativeMaterialGroups(catalog);
const common = {
  configFile: false,
  root: directory,
  publicDir: false,
  logLevel: 'warn',
  build: {
    target: 'es2022',
    minify: 'oxc',
    sourcemap: false,
    write: false,
    rolldownOptions: {
      cwd: directory,
      output: { codeSplitting: false, comments: false },
    },
  },
} satisfies InlineConfig;
function scriptBytes(result: Awaited<ReturnType<typeof build>>): Buffer {
  const bundles = Array.isArray(result) ? result : [result];
  const bundle = bundles[0];
  if (bundles.length !== 1 || !bundle || !('output' in bundle))
    throw new Error('Expected one runtime script bundle');
  const script = bundle.output[0];
  if (
    bundle.output.length !== 1 ||
    script?.type !== 'chunk' ||
    !script.isEntry ||
    script.imports.length ||
    script.dynamicImports.length
  )
    throw new Error('Runtime scripts must be self-contained single files');
  return Buffer.from(script.code);
}
const web = await Promise.all([
  build({
    ...common,
    build: {
      ...common.build,
      lib: { entry: 'src/host.ts', formats: ['es'], fileName: () => 'host.js' },
    },
  }),
  build({
    ...common,
    build: {
      ...common.build,
      lib: {
        entry: 'src/worker.ts',
        name: 'KaruyomiWorker',
        formats: ['iife'],
        fileName: () => 'worker.js',
      },
    },
  }),
]);
await writeFile(path.join(output, 'host.js'), scriptBytes(web[0]));
await writeFile(path.join(output, 'worker.js'), scriptBytes(web[1]));
await cp(
  path.join(directory, 'public/host.html'),
  path.join(output, 'host.html'),
);

// Each embedded value is decoded into fresh bytes. VerifiedLoader independently
// checks MIME, size and SHA on every use, and never falls back to a network read.
const embedded = Object.fromEntries(
  nativeGroups.sourceWorker.map(({ sha256 }) => {
    const value = data.get(sha256);
    if (!value) throw new Error('Missing Native Source material: ' + sha256);
    return [
      sha256,
      {
        base64: value.bytes.toString('base64'),
        contentType: value.contentType,
      },
    ];
  }),
);
const nativeMaterialModule = `import {createNativeMaterialResolver} from ${JSON.stringify(path.join(directory, 'src/native-materials.ts'))};
const values=${JSON.stringify(embedded)};
export const nativeMaterials=createNativeMaterialResolver(values);`;
const nativeMaterialId = '\0karuyomi:native-materials';
const nativeWorker = await build({
  ...common,
  build: {
    ...common.build,
    lib: {
      entry: 'src/worker.ts',
      name: 'KaruyomiWorker',
      formats: ['iife'],
      fileName: () => 'worker.js',
    },
  },
  plugins: [
    {
      name: 'embedded-native-materials',
      enforce: 'pre',
      resolveId(source, importer) {
        if (
          source === './materials.js' &&
          importer?.startsWith(path.join(directory, 'src/'))
        )
          return nativeMaterialId;
      },
      load(id) {
        if (id === nativeMaterialId) return nativeMaterialModule;
      },
    },
  ],
});
// Source host contains no client image decoders or image metadata policy.
const nativeHost = await build({
  ...common,
  build: {
    ...common.build,
    lib: {
      entry: 'src/host.native.ts',
      name: 'KaruyomiNativeHost',
      formats: ['iife'],
      fileName: () => 'host.js',
    },
  },
  define: {
    __KARUYOMI_MATERIAL_VERSION__: JSON.stringify(catalog.materialVersion),
  },
});
const nativeOutput = path.join(output, 'native');
await mkdir(nativeOutput, { recursive: true });
const nativeFiles = {
  host: { name: 'host.js', bytes: scriptBytes(nativeHost) },
  worker: { name: 'worker.js', bytes: scriptBytes(nativeWorker) },
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
  materials: nativeGroups.sourceWorker,
  sources: catalog.sources,
};
await writeFile(
  path.join(nativeOutput, 'manifest.json'),
  JSON.stringify(nativeManifest, null, 2) + '\n',
);

console.log(
  JSON.stringify({
    materialVersion: catalog.materialVersion,
    materials: data.size,
    nativeFiles: files,
  }),
);
