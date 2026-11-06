import { expect, test } from 'vitest';
import { parseControlRequest, parseControlResponse } from '../src/index.ts';

const build = {
  buildId: 'test-build',
  packageName: 'test.package',
  repoId: 'keiyoushi',
  version: '1',
  sourceIds: ['-9223372036854775808'],
  manifestPath: '/extensions/builds/test-build/manifest.json',
  sources: [{ id: '-9223372036854775808', name: 'Source', lang: '' }],
};
const sha256 = 'a'.repeat(64);

test('management controls preserve exact preparation and close identities', () => {
  const request = parseControlRequest({
    requestId: 'control',
    prepareBuild: { preparationId: 'prepare', build },
  });
  expect(request.command.case).toBe('prepareBuild');
  if (request.command.case !== 'prepareBuild') throw new Error('Wrong command');
  expect(request.command.value.build?.sources[0]?.id).toBe(
    '-9223372036854775808',
  );
  expect(
    parseControlRequest({
      requestId: 'control',
      closeBuild: { buildId: 'test-build', generation: 'original' },
    }).command.case,
  ).toBe('closeBuild');
  for (const prepareBuild of [
    { preparationId: '', build },
    { preparationId: 'prepare' },
    { preparationId: 'prepare', build: { ...build, sources: [] } },
  ])
    expect(() =>
      parseControlRequest({ requestId: 'control', prepareBuild }),
    ).toThrow();
  for (const closeBuild of [
    { buildId: '../other', generation: 'original' },
    { buildId: 'test-build', generation: '' },
  ])
    expect(() =>
      parseControlRequest({ requestId: 'control', closeBuild }),
    ).toThrow();
  expect(() =>
    parseControlRequest({
      requestId: 'control',
      forgetExtensionArtifact: { sha256: 'A'.repeat(64) },
    }),
  ).toThrow();
});

test('a prepared response describes bounded code, without claiming Source runtime readiness', () => {
  const preparedBuild = { build, bundleSha256: sha256, byteLength: 1 };
  expect(
    parseControlResponse({ requestId: 'control', preparedBuild }).result.case,
  ).toBe('preparedBuild');
  for (const changed of [
    { ...preparedBuild, byteLength: 0 },
    { ...preparedBuild, byteLength: 64 * 1024 * 1024 + 1 },
    { ...preparedBuild, bundleSha256: 'bad' },
    { ...preparedBuild, runtimeReady: true },
  ])
    expect(() =>
      parseControlResponse({ requestId: 'control', preparedBuild: changed }),
    ).toThrow();
});

test('cache status cannot exceed byte/count budgets or misstate the receipt total', () => {
  const extensionCache = {
    artifacts: [{ sha256, byteLength: 3, contentType: 'text/javascript' }],
    totalBytes: 3,
    maxBytes: 256 * 1024 * 1024,
    maxArtifacts: 128,
  };
  expect(
    parseControlResponse({ requestId: 'control', extensionCache }).result.case,
  ).toBe('extensionCache');
  for (const changed of [
    { ...extensionCache, totalBytes: 2 },
    { ...extensionCache, maxBytes: 2 },
    { ...extensionCache, maxArtifacts: 129 },
    {
      ...extensionCache,
      artifacts: [extensionCache.artifacts[0], extensionCache.artifacts[0]],
      totalBytes: 6,
    },
    {
      ...extensionCache,
      artifacts: [{ sha256, byteLength: 3, contentType: 'text/html' }],
    },
  ])
    expect(() =>
      parseControlResponse({ requestId: 'control', extensionCache: changed }),
    ).toThrow();
});
