import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  type BundleArtifact,
  type BuildManifest,
} from '@karuyomi/contracts';
import { gzipSync } from 'node:zlib';
import { sha256 } from '../src/verified-loader.js';
export const catalog = {
  catalogUrl: 'https://read.example.com/extensions/index.json',
  repoId: 'test-repo',
};
export const bytes = new TextEncoder().encode('self.productBuild = true;');
export const encodedBytes = new Uint8Array(gzipSync(bytes));
export const artifact = async (): Promise<BundleArtifact> => {
  const hash = await sha256(bytes);
  return {
    path: `/extensions/artifacts/${hash}.gz`,
    sha256: hash,
    size: bytes.byteLength,
    contentType: 'application/javascript',
    encoding: 'gzip',
    encodedSha256: await sha256(encodedBytes),
    encodedSize: encodedBytes.byteLength,
  };
};
export async function manifest(): Promise<BuildManifest> {
  return {
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    bridgeVersion: 2,
    buildId: 'test-build',
    repoId: 'test-repo',
    version: '1',
    packageName: 'eu.kanade.tachiyomi.extension.test',
    storageSchema: '1',
    sourceIds: ['9223372036854775806'],
    sources: [{ id: '9223372036854775806', name: 'Fixture', lang: 'en' }],
    bundle: await artifact(),
    hostScripts: [],
    resources: [],
  };
}
