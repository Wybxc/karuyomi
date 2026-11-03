import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  type BuildManifest,
} from '@karuyomi/contracts';
import { sha256 } from '../src/verified-loader.js';
const bytes = new TextEncoder().encode('self.productBuild = true;');
const artifact = async () => {
  const hash = await sha256(bytes);
  return {
    path: `/api/extensions/artifacts/${hash}`,
    sha256: hash,
    size: bytes.byteLength,
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
    packageName: 'test.extension',
    storageSchema: '1',
    sourceIds: ['9223372036854775806'],
    bundle: await artifact(),
    hostScripts: [],
    resources: [],
  };
}
