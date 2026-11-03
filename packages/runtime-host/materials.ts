import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import type { Artifact } from '@karuyomi/contracts';

const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(import.meta.url);
const zstdSource = Object.freeze({
  packageName: '@bokuweb/zstd-wasm',
  version: '0.0.27',
  file: 'dist/web/zstd.wasm',
  sha256: '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
  size: 251806,
});
const scriptNames = ['crypto', 'zstd', 'graphics', 'cache', 'file'];
export const digest = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');
export interface MaterialArtifact extends Artifact {
  logicalName: string;
  contentType: string;
}
export interface MaterialCatalog {
  schemaVersion: number;
  protocolVersion: number;
  hostAbi: string;
  runtimeBaseline: string;
  materialVersion: string;
  hostScripts: MaterialArtifact[];
  resources: MaterialArtifact[];
  sources: { zstd: typeof zstdSource };
}
export interface RuntimeMaterials {
  catalog: MaterialCatalog;
  data: Map<string, { bytes: Buffer; contentType: string }>;
}

/** Compile the maintained TS bridges into the current material catalog. */
export async function compileBridge(name: string): Promise<Buffer> {
  if (!scriptNames.includes(name)) throw new Error('Unknown runtime bridge');
  const result = await build({
    absWorkingDir: root,
    entryPoints: [`runtime/teavm/bridge/${name}-bridge.ts`],
    bundle: true,
    platform: 'browser',
    format: 'iife',
    target: 'es2022',
    minify: false,
    sourcemap: false,
    write: false,
    charset: 'utf8',
    legalComments: 'none',
    define: { 'import.meta.url': 'self.location.origin' },
  });
  const output = result.outputFiles[0];
  if (!output || result.outputFiles.length !== 1)
    throw new Error('Invalid runtime bridge output');
  return Buffer.from(output.contents);
}

/** Public materials only. Requires locked npm build dependencies, never JVM seed. */
export async function collectMaterials({
  includeWasmBytes = true,
} = {}): Promise<RuntimeMaterials> {
  const protocol: {
    protocolVersion: number;
    hostAbi: string;
    runtimeBaseline: string;
  } = JSON.parse(
    await readFile(path.join(root, 'packages/contracts/protocol.json'), 'utf8'),
  );
  const data: RuntimeMaterials['data'] = new Map();
  function artifact(
    logicalName: string,
    bytes: Buffer,
    contentType: string,
  ): MaterialArtifact {
    const sha256 = digest(bytes);
    data.set(sha256, { bytes, contentType });
    return {
      logicalName,
      path: '/runtime/materials/' + sha256,
      sha256,
      size: bytes.length,
      contentType,
    };
  }
  const hostScripts: MaterialArtifact[] = [];
  for (const name of scriptNames)
    hostScripts.push(
      artifact(
        name + '-bridge.js',
        await compileBridge(name),
        'application/javascript',
      ),
    );
  const resource: MaterialArtifact = {
    logicalName: 'zstd.wasm',
    path: '/runtime/materials/' + zstdSource.sha256,
    sha256: zstdSource.sha256,
    size: zstdSource.size,
    contentType: 'application/wasm',
  };
  if (includeWasmBytes) {
    const entry = require.resolve(zstdSource.packageName);
    const packageDirectory = path.resolve(path.dirname(entry), '../..');
    const metadata: { name: string; version: string } = JSON.parse(
      await readFile(path.join(packageDirectory, 'package.json'), 'utf8'),
    );
    if (
      metadata.name !== zstdSource.packageName ||
      metadata.version !== zstdSource.version
    )
      throw new Error(
        'Unexpected zstd material package; install the exact locked workspace dependencies',
      );
    const wasm = await readFile(path.join(packageDirectory, zstdSource.file));
    if (digest(wasm) !== zstdSource.sha256 || wasm.length !== zstdSource.size)
      throw new Error('Pinned zstd WASM digest/size mismatch');
    data.set(zstdSource.sha256, {
      bytes: wasm,
      contentType: resource.contentType!,
    });
  }
  const resources = [resource];
  const identity = { ...protocol, hostScripts, resources };
  const catalog: MaterialCatalog = {
    schemaVersion: 1,
    ...protocol,
    materialVersion: digest(Buffer.from(JSON.stringify(identity))),
    hostScripts,
    resources,
    sources: { zstd: zstdSource },
  };
  return { catalog, data };
}

export async function prepareMaterials(
  outputDirectory: string,
): Promise<RuntimeMaterials> {
  const materials = await collectMaterials();
  await mkdir(path.join(outputDirectory, 'materials'), { recursive: true });
  for (const [sha256, { bytes }] of materials.data)
    await writeFile(path.join(outputDirectory, 'materials', sha256), bytes);
  await writeFile(
    path.join(outputDirectory, 'materials.json'),
    JSON.stringify(materials.catalog, null, 2) + '\n',
  );
  return materials;
}
