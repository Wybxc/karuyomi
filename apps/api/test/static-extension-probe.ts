// Controlled static fixture preparation for the formal local probes. The API
// never imports this module or serves extension manifests/bundle bytes.
import {
  copyFile,
  mkdir,
  readdir,
  readFile,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import type { BuildManifest } from '../../../packages/contracts/src/index.ts';

export async function createStaticSnapshot(
  directory: string,
  manifest: BuildManifest,
  artifactDirectory: string,
  manifestBytes: Uint8Array,
) {
  const manifestPath = `/extensions/builds/${manifest.buildId}/manifest.json`;
  for (const file of [manifestPath, manifest.bundle.path])
    await mkdir(path.dirname(path.join(directory, file)), { recursive: true });
  await writeFile(path.join(directory, manifestPath), manifestBytes);
  await writeFile(
    path.join(directory, 'extensions/index.json'),
    JSON.stringify({
      schemaVersion: 1,
      builds: [
        {
          buildId: manifest.buildId,
          packageName: manifest.packageName,
          repoId: manifest.repoId,
          version: manifest.version,
          sourceIds: manifest.sourceIds,
          manifestPath,
        },
      ],
      nextCursor: null,
    }),
  );
  await copyFile(
    path.join(artifactDirectory, manifest.bundle.sha256 + '.gz'),
    path.join(directory, manifest.bundle.path),
  );
  // Explicit gzip is a payload encoding owned by the manifest, not HTTP CE.
  await writeFile(
    path.join(directory, '_headers'),
    '/extensions/artifacts/*\n  Content-Type: application/gzip\n  Cache-Control: public, max-age=31536000, immutable\n/extensions/index.json\n  Cache-Control: no-cache\n/extensions/builds/*\n  Cache-Control: no-cache\n',
  );
  return directory;
}

export async function migrationFiles(apiDirectory: string) {
  return (await readdir(path.join(apiDirectory, 'migrations')))
    .filter((name) => name.endsWith('.sql'))
    .sort()
    .map((name) => path.join(apiDirectory, 'migrations', name));
}

export async function staticProbeFile(
  directory: string,
  pathname: string,
  manifest: BuildManifest,
) {
  const manifestPath = `/extensions/builds/${manifest.buildId}/manifest.json`;
  if (
    !['/extensions/index.json', manifestPath, manifest.bundle.path].includes(
      pathname,
    )
  )
    return undefined;
  return {
    bytes: await readFile(path.join(directory, pathname)),
    contentType: pathname.endsWith('.gz')
      ? 'application/gzip'
      : 'application/json',
  };
}
