import { expect, test } from 'vitest';
import {
  artifactSchema,
  buildManifestSchema,
  bundleArtifactSchema,
  extensionIndexSchema,
  hostAbi,
  protocolVersion,
  runtimeBaseline,
} from '../src/index.js';

const hash = 'a'.repeat(64);
const bundle = {
  path: `/extensions/artifacts/${hash}.gz`,
  sha256: hash,
  size: 100,
  contentType: 'application/javascript',
  encoding: 'gzip',
  encodedSha256: 'b'.repeat(64),
  encodedSize: 50,
};
const build = {
  protocolVersion,
  hostAbi,
  runtimeBaseline,
  bridgeVersion: 2,
  buildId: 'test-build',
  packageName: 'test.extension',
  repoId: 'repo',
  version: '1',
  storageSchema: '1',
  sourceIds: ['123'],
  bundle,
  hostScripts: [],
  resources: [],
};

test('the bundle requires both gzip and canonical metadata without uncompressed or private alternatives', () => {
  expect(buildManifestSchema.parse(build).bundle).toEqual(bundle);
  for (const value of [
    { ...bundle, encoding: undefined },
    { ...bundle, encodedSha256: undefined },
    { ...bundle, encodedSize: undefined },
    { ...bundle, path: `/api/extensions/artifacts/${hash}` },
    { ...bundle, path: `/extensions/artifacts/${hash}` },
    { ...bundle, contentType: 'text/html' },
    { ...bundle, encodedSize: 25 * 1024 * 1024 + 1 },
  ])
    expect(bundleArtifactSchema.safeParse(value).success).toBe(false);
  expect(
    bundleArtifactSchema.safeParse({ ...bundle, size: 64 * 1024 * 1024 })
      .success,
  ).toBe(true);
  expect(
    buildManifestSchema.safeParse({
      ...build,
      bundle: { ...bundle, path: `/extensions/artifacts/${'c'.repeat(64)}.gz` },
    }).success,
  ).toBe(false);
});

test('shared material fields cannot accept encoded bundle fields or private delivery', () => {
  const material = {
    path: `/runtime/materials/${hash}`,
    sha256: hash,
    size: 1,
    contentType: 'application/javascript',
    logicalName: 'crypto-bridge.js',
  };
  expect(artifactSchema.parse(material)).toEqual(material);
  expect(
    artifactSchema.safeParse({ ...material, encoding: 'gzip' }).success,
  ).toBe(false);
  expect(
    artifactSchema.safeParse({
      ...material,
      path: `/api/extensions/artifacts/${hash}`,
    }).success,
  ).toBe(false);
});

test('the static index binds manifest paths to one current build per package', () => {
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: '/extensions/builds/test-build/manifest.json',
  };
  const index = { schemaVersion: 1, builds: [descriptor], nextCursor: null };
  expect(extensionIndexSchema.parse(index)).toEqual(index);
  for (const value of [
    { ...index, nextCursor: 'next' },
    {
      ...index,
      builds: [
        descriptor,
        {
          ...descriptor,
          buildId: 'new-build',
          manifestPath: '/extensions/builds/new-build/manifest.json',
        },
      ],
    },
    {
      ...index,
      builds: [
        {
          ...descriptor,
          manifestPath: '/extensions/builds/other/manifest.json',
        },
      ],
    },
    {
      ...index,
      builds: [
        {
          ...descriptor,
          manifestPath: '/api/extensions/builds/test-build/manifest',
        },
      ],
    },
  ])
    expect(extensionIndexSchema.safeParse(value).success).toBe(false);
});
