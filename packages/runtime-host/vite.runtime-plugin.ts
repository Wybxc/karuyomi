import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import {
  hostAbi,
  pdfiumMaterialName,
  protocolVersion,
  runtimeBaseline,
  runtimeMaterialCatalogSchema,
  type RuntimeMaterialArtifact,
  type RuntimeMaterialCatalog,
} from '@karuyomi/contracts';
import {
  readPreparedWebpEncoder,
  readWebpEncoderSource,
} from '../../tools/teavm/webp.ts';
import { z } from 'zod';
import { transformWithOxc, type Plugin, type Rolldown } from 'vite';

const directory = fileURLToPath(new URL('./', import.meta.url));
const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(import.meta.url);
const scriptNames = ['crypto', 'zstd', 'graphics', 'cache', 'file'];
const zstdSource = Object.freeze({
  packageName: '@bokuweb/zstd-wasm',
  version: '0.0.27',
  file: 'dist/web/zstd.wasm',
  sha256: '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
  size: 251806,
});
const pdfiumSource = Object.freeze({
  packageName: '@hyzyla/pdfium',
  version: '3.0.0',
  file: 'dist/pdfium.wasm',
  sha256: 'beeaf5bbff216d555fecec7cd486072838c4632a2272d31b52ef1fd05008fe7c',
  size: 5298237,
});
const pdfiumDirectory = path.dirname(
  require.resolve('@hyzyla/pdfium/package.json'),
);
const digest = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');
const bridgeEntry = 'virtual:karuyomi-runtime-bridge/';
const wasmMime = 'application/wasm';
const zstdName = 'zstd.wasm';
const webpName = 'webp-encoder.wasm';

function singleScript(bundle: Rolldown.OutputBundle): Rolldown.OutputChunk {
  const outputs = Object.values(bundle);
  const script = outputs[0];
  if (
    outputs.length !== 1 ||
    script?.type !== 'chunk' ||
    !script.isEntry ||
    script.imports.length ||
    script.dynamicImports.length
  )
    throw new Error('Runtime output must be a self-contained single script');
  return script;
}

function materialArtifact(
  logicalName: string,
  bytes: Buffer,
  contentType: string,
): RuntimeMaterialArtifact {
  const sha256 = digest(bytes);
  return {
    logicalName,
    path: '/runtime/materials/' + sha256,
    sha256,
    size: bytes.length,
    contentType,
  };
}

function wasmArtifact(
  logicalName: string,
  { sha256, size }: { sha256: string; size: number },
): RuntimeMaterialArtifact {
  return {
    logicalName,
    path: '/runtime/materials/' + sha256,
    sha256,
    size,
    contentType: wasmMime,
  };
}

async function packageBuiltMaterials(scripts: ReadonlyMap<string, Buffer>) {
  const data = new Map<string, { bytes: Buffer; contentType: string }>();
  const hostScripts = scriptNames.map((name) => {
    const bytes = scripts.get(name);
    if (!bytes) throw new Error('Missing Vite runtime bridge output: ' + name);
    const entry = materialArtifact(
      name + '-bridge.js',
      bytes,
      'application/javascript',
    );
    data.set(entry.sha256, { bytes, contentType: entry.contentType });
    return entry;
  });
  const entry = require.resolve(zstdSource.packageName);
  const packageDirectory = path.resolve(path.dirname(entry), '../..');
  z.object({
    name: z.literal(zstdSource.packageName),
    version: z.literal(zstdSource.version),
  }).parse(
    JSON.parse(
      await readFile(path.join(packageDirectory, 'package.json'), 'utf8'),
    ),
  );
  const wasm = await readFile(path.join(packageDirectory, zstdSource.file));
  if (digest(wasm) !== zstdSource.sha256 || wasm.length !== zstdSource.size)
    throw new Error('Pinned zstd WASM digest/size mismatch');
  const webp = readPreparedWebpEncoder();
  z.object({
    name: z.literal(pdfiumSource.packageName),
    version: z.literal(pdfiumSource.version),
  }).parse(
    JSON.parse(
      await readFile(path.join(pdfiumDirectory, 'package.json'), 'utf8'),
    ),
  );
  const pdfium = await readFile(path.join(pdfiumDirectory, pdfiumSource.file));
  if (
    digest(pdfium) !== pdfiumSource.sha256 ||
    pdfium.length !== pdfiumSource.size
  )
    throw new Error('Pinned PDFium WASM digest/size mismatch');
  const resources = [
    wasmArtifact(zstdName, zstdSource),
    wasmArtifact(webpName, webp.source),
    wasmArtifact(pdfiumMaterialName, pdfiumSource),
  ];
  data.set(zstdSource.sha256, { bytes: wasm, contentType: wasmMime });
  data.set(webp.source.sha256, { bytes: webp.bytes, contentType: wasmMime });
  data.set(pdfiumSource.sha256, { bytes: pdfium, contentType: wasmMime });
  const identity = {
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    hostScripts,
    resources,
  };
  const catalog = runtimeMaterialCatalogSchema.parse({
    schemaVersion: 1,
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    materialVersion: digest(Buffer.from(JSON.stringify(identity))),
    hostScripts,
    resources,
    sources: {
      zstd: zstdSource,
      pdfium: pdfiumSource,
      webpEncoder: webp.source,
    },
  });
  return { catalog, data };
}

/** Vite owns compilation; this hook publishes the project's material contract. */
export function runtimeMaterialAssets(): Plugin {
  const scripts = new Map<string, Buffer>();
  return {
    name: 'karuyomi-runtime-material-assets',
    sharedDuringBuild: true,
    enforce: 'pre',
    resolveId(source) {
      if (source.startsWith(bridgeEntry)) return '\0' + source;
    },
    load(id) {
      if (!id.startsWith('\0' + bridgeEntry)) return;
      const name = id.slice(bridgeEntry.length + 1);
      if (!scriptNames.includes(name))
        throw new Error('Unknown runtime bridge: ' + name);
      return `import ${JSON.stringify(path.join(root, 'runtime/teavm/bridge', name + '-bridge.ts'))};`;
    },
    transform: {
      filter: { code: /import\.meta\.url/ },
      handler(code, id) {
        // Classic bridge scripts load their pinned WASM through the host resolver.
        // Replace before Vite's asset transform can inline another WASM copy.
        return transformWithOxc(code, id, {
          define: { 'import.meta.url': 'self.location.origin' },
          sourcemap: false,
        });
      },
    },
    async generateBundle(_options, bundle) {
      const name =
        this.environment.name === 'client' ? 'crypto' : this.environment.name;
      const script = singleScript(bundle);
      scripts.set(name, Buffer.from(script.code));
      delete bundle[script.fileName];
      if (name !== 'file') return;
      const { catalog, data } = await packageBuiltMaterials(scripts);
      for (const [sha256, { bytes }] of data)
        this.emitFile({
          type: 'asset',
          fileName: 'materials/' + sha256,
          source: bytes,
        });
      this.emitFile({
        type: 'asset',
        fileName: 'materials.json',
        source: JSON.stringify(catalog, null, 2) + '\n',
      });
      const [license, patents] = await Promise.all(
        ['COPYING', 'PATENTS'].map((name) =>
          readFile(path.join(root, 'vendor/libwebp', name), 'utf8'),
        ),
      );
      this.emitFile({
        type: 'asset',
        fileName: 'notices/libwebp.txt',
        source: `${license}\n${patents}`,
      });
      const [pdfiumLicense, pdfiumNotices] = await Promise.all([
        readFile(path.join(pdfiumDirectory, 'LICENSE.md'), 'utf8'),
        readFile(
          path.join(root, 'runtime/teavm/licenses/PDFium-Third-Party.txt'),
          'utf8',
        ),
      ]);
      this.emitFile({
        type: 'asset',
        fileName: 'notices/pdfium.txt',
        source: `${pdfiumLicense}\n${pdfiumNotices}`,
      });
    },
  };
}

/** Native embeds the same Web materials as independently owned bytes. */
export async function nativeRuntimeAssets(): Promise<Plugin> {
  let catalog: RuntimeMaterialCatalog;
  try {
    catalog = runtimeMaterialCatalogSchema.parse(
      JSON.parse(
        await readFile(path.join(directory, 'dist/materials.json'), 'utf8'),
      ),
    );
  } catch (cause) {
    throw new Error(
      'Runtime materials are missing or invalid; run pnpm --filter @karuyomi/runtime-host build:materials first',
      { cause },
    );
  }
  const source = catalog.sources.zstd;
  const pdfium = catalog.sources.pdfium;
  const webp = readWebpEncoderSource();
  const webpSource = catalog.sources.webpEncoder;
  const expectedResources = [
    wasmArtifact(zstdName, zstdSource),
    wasmArtifact(webpName, webp),
    wasmArtifact(pdfiumMaterialName, pdfiumSource),
  ];
  if (
    catalog.protocolVersion !== protocolVersion ||
    catalog.hostAbi !== hostAbi ||
    catalog.runtimeBaseline !== runtimeBaseline ||
    catalog.hostScripts.map((entry) => entry.logicalName).join('\n') !==
      scriptNames.map((name) => name + '-bridge.js').join('\n') ||
    catalog.resources.length !== expectedResources.length ||
    expectedResources.some((expected, index) => {
      const actual = catalog.resources[index];
      return (
        actual?.logicalName !== expected.logicalName ||
        actual.path !== expected.path ||
        actual.sha256 !== expected.sha256 ||
        actual.size !== expected.size ||
        actual.contentType !== expected.contentType
      );
    }) ||
    source.packageName !== zstdSource.packageName ||
    source.version !== zstdSource.version ||
    source.file !== zstdSource.file ||
    source.sha256 !== zstdSource.sha256 ||
    source.size !== zstdSource.size ||
    pdfium.packageName !== pdfiumSource.packageName ||
    pdfium.version !== pdfiumSource.version ||
    pdfium.file !== pdfiumSource.file ||
    pdfium.sha256 !== pdfiumSource.sha256 ||
    pdfium.size !== pdfiumSource.size ||
    webpSource.version !== webp.version ||
    webpSource.upstreamCommit !== webp.upstreamCommit ||
    webpSource.compilerVersion !== webp.compilerVersion ||
    webpSource.sha256 !== webp.sha256 ||
    webpSource.size !== webp.size
  )
    throw new Error(
      'Generated product material catalog contains unexpected assets',
    );
  const sourceMaterials = [...catalog.hostScripts, ...catalog.resources];
  const embedded = Object.fromEntries(
    await Promise.all(
      sourceMaterials.map(
        async ({ sha256, size, logicalName, contentType }) => {
          const bytes = await readFile(
            path.join(directory, 'dist/materials', sha256),
          );
          if (bytes.length !== size)
            throw new Error(
              'Generated runtime material changed length: ' + logicalName,
            );
          if (logicalName === pdfiumMaterialName) {
            const encoded = gzipSync(bytes, { level: 9 });
            encoded[9] = 255;
            return [
              sha256,
              {
                base64: encoded.toString('base64'),
                contentType,
                decodedSize: size,
              },
            ];
          }
          return [sha256, { base64: bytes.toString('base64'), contentType }];
        },
      ),
    ),
  );
  const materialId = '\0karuyomi:native-materials';
  const files: Record<string, { path: string; sha256: string; size: number }> =
    {};
  return {
    name: 'karuyomi-native-runtime-assets',
    sharedDuringBuild: true,
    enforce: 'pre',
    config() {
      return {
        environments: {
          nativeHost: {
            define: {
              __KARUYOMI_MATERIAL_VERSION__: JSON.stringify(
                catalog.materialVersion,
              ),
              __KARUYOMI_NATIVE_MATERIALS__: JSON.stringify(sourceMaterials),
            },
          },
        },
      };
    },
    resolveId(source, importer) {
      if (
        this.environment.name === 'nativeWorker' &&
        source === './materials.js' &&
        importer?.startsWith(path.join(directory, 'src/'))
      )
        return materialId;
    },
    load(id) {
      if (id === materialId)
        return `import {createNativeMaterialResolver} from ${JSON.stringify(path.join(directory, 'src/native-materials.ts'))};
const values=${JSON.stringify(embedded)};
export const nativeMaterials=createNativeMaterialResolver(values);`;
    },
    generateBundle(_options, bundle) {
      const script = singleScript(bundle);
      const environment = this.environment.name;
      if (environment !== 'nativeHost' && environment !== 'nativeWorker')
        return;
      const bytes = Buffer.from(script.code);
      const key = environment === 'nativeHost' ? 'host' : 'worker';
      files[key] = {
        path: key + '.js',
        sha256: digest(bytes),
        size: bytes.length,
      };
      if (environment !== 'nativeWorker') return;
      if (!files.host)
        throw new Error('Native host must be built before Native worker');
      this.emitFile({
        type: 'asset',
        fileName: 'manifest.json',
        source:
          JSON.stringify(
            {
              schemaVersion: 1,
              protocolVersion: catalog.protocolVersion,
              hostAbi: catalog.hostAbi,
              runtimeBaseline: catalog.runtimeBaseline,
              materialVersion: catalog.materialVersion,
              files,
              materials: sourceMaterials,
              sources: catalog.sources,
            },
            null,
            2,
          ) + '\n',
      });
    },
  };
}
