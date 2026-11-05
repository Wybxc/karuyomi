import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  runtimeMaterialCatalogSchema,
  type RuntimeMaterialArtifact,
  type RuntimeMaterialCatalog,
} from '@karuyomi/contracts';
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
const digest = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');
const bridgeEntry = 'virtual:karuyomi-runtime-bridge/';

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
  const resource: RuntimeMaterialArtifact = {
    logicalName: 'zstd.wasm',
    path: '/runtime/materials/' + zstdSource.sha256,
    sha256: zstdSource.sha256,
    size: zstdSource.size,
    contentType: 'application/wasm',
  };
  data.set(resource.sha256, { bytes: wasm, contentType: resource.contentType });
  const resources = [resource];
  const identity = {
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    hostScripts,
    resources,
    imageCodecs: [],
    codecSource: null,
  };
  const catalog = runtimeMaterialCatalogSchema.parse({
    schemaVersion: 1,
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    materialVersion: digest(Buffer.from(JSON.stringify(identity))),
    hostScripts,
    resources,
    imageCodecs: [],
    sources: { zstd: zstdSource, imageCodecs: null },
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
    },
  };
}

/** Native is the same six Web materials embedded as independently owned bytes. */
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
  if (
    catalog.protocolVersion !== protocolVersion ||
    catalog.hostAbi !== hostAbi ||
    catalog.runtimeBaseline !== runtimeBaseline ||
    catalog.hostScripts.map((entry) => entry.logicalName).join('\n') !==
      scriptNames.map((name) => name + '-bridge.js').join('\n') ||
    catalog.resources.length !== 1 ||
    catalog.resources[0]?.sha256 !== zstdSource.sha256 ||
    catalog.imageCodecs.length ||
    catalog.sources.imageCodecs !== null ||
    source.packageName !== zstdSource.packageName ||
    source.version !== zstdSource.version ||
    source.file !== zstdSource.file ||
    source.sha256 !== zstdSource.sha256 ||
    source.size !== zstdSource.size
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
