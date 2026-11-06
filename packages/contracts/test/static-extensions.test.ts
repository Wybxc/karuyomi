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
  sources: [{ id: '123', name: 'Fixture', lang: 'en' }],
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
    sources: build.sources,
    manifestPath: '/extensions/builds/test-build/manifest.json',
  };
  const index = {
    schemaVersion: 1,
    repoId: build.repoId,
    builds: [descriptor],
  };
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

test('static Source metadata is complete, bounded and bound to the declared identities', () => {
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: '/extensions/builds/test-build/manifest.json',
  };
  const invalid = [
    undefined,
    [],
    [{ id: '456', name: 'Other', lang: 'zh' }],
    [...build.sources, ...build.sources],
    [{ id: '123', name: '', lang: 'zh' }],
    [{ id: '123', name: '   ', lang: 'zh' }],
    [{ id: '123', name: 'x'.repeat(501), lang: 'zh' }],
    [{ id: '123', name: 'Fixture', lang: 'x'.repeat(65) }],
    [{ id: 123, name: 'Fixture', lang: 'zh' }],
    [{ id: '123', name: 'Fixture', lang: 'zh', supportsLatest: true }],
  ];
  for (const sources of invalid) {
    expect(buildManifestSchema.safeParse({ ...build, sources }).success).toBe(
      false,
    );
    expect(
      extensionIndexSchema.safeParse({
        schemaVersion: 1,
        repoId: build.repoId,
        builds: [{ ...descriptor, sources }],
      }).success,
    ).toBe(false);
  }
  const sources = [{ id: '123', name: 'x'.repeat(500), lang: 'x'.repeat(64) }];
  expect(buildManifestSchema.parse({ ...build, sources }).sources).toEqual(
    sources,
  );
});

test('static metadata preserves language values and signed identities without runtime capability claims', () => {
  const sourceIds = ['-9223372036854775808', '9223372036854775807'];
  const sources = [
    { id: sourceIds[1], name: '多语种源', lang: 'all' },
    { id: sourceIds[0], name: '未标注', lang: '' },
  ];
  expect(
    buildManifestSchema.parse({ ...build, sourceIds, sources }).sources,
  ).toEqual(sources);
  for (const id of ['-9223372036854775809', '9223372036854775808']) {
    expect(
      buildManifestSchema.safeParse({
        ...build,
        sourceIds: [id],
        sources: [{ id, name: 'Fixture', lang: 'en' }],
      }).success,
    ).toBe(false);
  }
});
