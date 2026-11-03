import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
export const digest = (bytes) =>
  createHash('sha256').update(bytes).digest('hex');

/** Collect only public runtime materials; never reads the private JVM seed. */
export async function collectMaterials({ includeWasmBytes = true } = {}) {
  const protocol = JSON.parse(
    await readFile(path.join(root, 'packages/contracts/protocol.json'), 'utf8'),
  );
  const data = new Map();
  function artifact(logicalName, bytes, contentType) {
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
  const hostScripts = [];
  for (const name of scriptNames) {
    const logicalName = name + '-bridge.js';
    hostScripts.push(
      artifact(
        logicalName,
        await readFile(path.join(root, 'runtime/teavm/bridge', logicalName)),
        'application/javascript',
      ),
    );
  }
  const resource = {
    logicalName: 'zstd.wasm',
    path: '/runtime/materials/' + zstdSource.sha256,
    sha256: zstdSource.sha256,
    size: zstdSource.size,
    contentType: 'application/wasm',
  };
  if (includeWasmBytes) {
    const entry = require.resolve(zstdSource.packageName);
    const packageDirectory = path.resolve(path.dirname(entry), '../..');
    const metadata = JSON.parse(
      await readFile(path.join(packageDirectory, 'package.json'), 'utf8'),
    );
    if (
      metadata.name !== zstdSource.packageName ||
      metadata.version !== zstdSource.version
    ) {
      throw new Error(
        'Unexpected zstd material package; install the exact locked workspace dependencies',
      );
    }
    const wasm = await readFile(path.join(packageDirectory, zstdSource.file));
    if (digest(wasm) !== zstdSource.sha256 || wasm.length !== zstdSource.size)
      throw new Error('Pinned zstd WASM digest/size mismatch');
    data.set(zstdSource.sha256, {
      bytes: wasm,
      contentType: resource.contentType,
    });
  }
  const resources = [resource];
  const compatibility = [];
  for (const [version, names, nativeSupported] of [
    ['release9-v1', ['cache', 'file'], false],
    ['source-aot-v1', scriptNames, true],
  ]) {
    for (const name of names) {
      const logicalName = version + '/' + name + '-bridge.js';
      compatibility.push({
        ...artifact(
          logicalName,
          await readFile(
            path.join(root, 'runtime/teavm/bridge/compat', logicalName),
          ),
          'application/javascript',
        ),
        nativeSupported,
      });
    }
  }
  const identity = { ...protocol, hostScripts, resources, compatibility };
  const catalog = {
    schemaVersion: 1,
    ...protocol,
    materialVersion: digest(Buffer.from(JSON.stringify(identity))),
    hostScripts,
    resources,
    compatibility,
    sources: { zstd: zstdSource },
  };
  return { catalog, data };
}

/** Write content-addressed static files and their deterministic catalog. */
export async function prepareMaterials(outputDirectory) {
  const materials = await collectMaterials();
  await mkdir(path.join(outputDirectory, 'materials'), { recursive: true });
  for (const [sha256, { bytes }] of materials.data) {
    await writeFile(path.join(outputDirectory, 'materials', sha256), bytes);
  }
  await writeFile(
    path.join(outputDirectory, 'materials.json'),
    JSON.stringify(materials.catalog, null, 2) + '\n',
  );
  return materials;
}
