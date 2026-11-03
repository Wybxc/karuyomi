import { expect, test, vi } from 'vitest';
import {
  buildManifestSchema,
  hostAbi,
  protocolVersion,
  runtimeBaseline,
} from '@karuyomi/contracts';
import { createApp, type Bindings } from '../src/app.js';
import { byteRange, type ExtensionStore } from '../src/extensions.js';

const hash = 'a'.repeat(64);
const manifest = buildManifestSchema.parse({
  protocolVersion,
  hostAbi,
  runtimeBaseline,
  bridgeVersion: 1,
  buildId: 'verified-build',
  packageName: 'example.source',
  repoId: 'example',
  version: '1',
  storageSchema: 'v1',
  sourceIds: ['9223372036854775807'],
  bundle: { path: `/api/extensions/artifacts/${hash}`, sha256: hash, size: 4 },
  hostScripts: [],
});

function fixture() {
  const store: ExtensionStore = {
    list: vi.fn(async () => [
      { buildId: manifest.buildId, manifestJson: JSON.stringify(manifest) },
    ]),
    manifest: vi.fn(async (id) =>
      id === manifest.buildId ? JSON.stringify(manifest) : null,
    ),
    artifact: vi.fn(async (id) =>
      id === hash
        ? {
            sha256: hash,
            objectKey: `artifacts/${hash}`,
            size: 4,
            contentType: 'application/javascript',
          }
        : null,
    ),
  };
  const bucket = {
    head: vi.fn(async () => ({ size: 4, httpMetadata: {} })),
    get: vi.fn(async (_key, options) => ({
      size: 4,
      body: new Response(
        new Uint8Array([1, 2, 3, 4]).slice(
          options?.range?.offset ?? 0,
          options?.range ? options.range.offset + options.range.length : 4,
        ),
      ).body,
    })),
  };
  const env = {
    ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
    ACCESS_AUD: 'app',
    ACCESS_SUBJECT: 'owner',
    OWNER_EMAIL: 'owner@example.com',
    APP_ORIGIN: 'https://read.example.com',
    ARTIFACTS: bucket,
  } as unknown as Bindings;
  const app = createApp(
    async () => ({
      subject: 'owner',
      email: 'owner@example.com',
      expiresAt: 4_000_000_000,
    }),
    () => store,
  );
  const request = (
    path: string,
    headers: Record<string, string> = {},
    authenticated = true,
    method = 'GET',
  ) =>
    app.request(
      `https://read.example.com/api/extensions/${path}`,
      {
        method,
        headers: {
          ...(authenticated
            ? { 'Cf-Access-Jwt-Assertion': 'test-signed-by-injected-verifier' }
            : {}),
          ...headers,
        },
      },
      env,
    );
  return { store, bucket, request };
}

test('only a registered, verified build exposes its validated manifest', async () => {
  const f = fixture();
  const response = await f.request('builds/verified-build/manifest');
  expect(response.status).toBe(200);
  expect(buildManifestSchema.parse(await response.json()).sourceIds).toEqual([
    '9223372036854775807',
  ]);
  expect((await f.request('builds/missing/manifest')).status).toBe(404);
});

test.each([{ 'If-None-Match': `"${hash}"` }, { Range: 'bytes=0-1' }])(
  'authentication precedes conditional or range reads: %j',
  async (headers) => {
    const f = fixture();
    expect((await f.request(`artifacts/${hash}`, headers, false)).status).toBe(
      401,
    );
    expect(f.store.artifact).not.toHaveBeenCalled();
    expect(f.bucket.head).not.toHaveBeenCalled();
  },
);

test('raw artifact is streamed with private revalidation and content hash ETag', async () => {
  const f = fixture();
  const response = await f.request(`artifacts/${hash}`);
  expect(response.status).toBe(200);
  expect(response.headers.get('cache-control')).toBe('private, no-cache');
  expect(response.headers.get('etag')).toBe(`"${hash}"`);
  expect([...new Uint8Array(await response.arrayBuffer())]).toEqual([
    1, 2, 3, 4,
  ]);
});

test('304 and HEAD do not open an R2 body', async () => {
  const f = fixture();
  expect(
    (await f.request(`artifacts/${hash}`, { 'If-None-Match': `W/"${hash}"` }))
      .status,
  ).toBe(304);
  expect((await f.request(`artifacts/${hash}`, {}, true, 'HEAD')).status).toBe(
    200,
  );
  expect(f.bucket.get).not.toHaveBeenCalled();
});

test('byte ranges, unsatisfied ranges and If-Range preserve complete object identity', async () => {
  const f = fixture();
  const partial = await f.request(`artifacts/${hash}`, { Range: 'bytes=1-2' });
  expect(partial.status).toBe(206);
  expect(partial.headers.get('content-range')).toBe('bytes 1-2/4');
  expect([...new Uint8Array(await partial.arrayBuffer())]).toEqual([2, 3]);
  expect(
    (await f.request(`artifacts/${hash}`, { Range: 'bytes=99-' })).status,
  ).toBe(416);
  expect(
    (
      await f.request(`artifacts/${hash}`, {
        Range: 'bytes=0-1',
        'If-Range': '"old"',
      })
    ).status,
  ).toBe(200);
  expect(byteRange('bytes=-2', 4)).toEqual({ offset: 2, length: 2 });
  expect(byteRange('bytes=0-1,2-3', 4)).toBeNull();
});

test('unregistered hashes and missing or wrong-size R2 objects cannot be served', async () => {
  const f = fixture();
  expect((await f.request(`artifacts/${'b'.repeat(64)}`)).status).toBe(404);
  f.bucket.head.mockResolvedValueOnce({ size: 9, httpMetadata: {} });
  expect((await f.request(`artifacts/${hash}`)).status).toBe(503);
  expect(f.bucket.get).not.toHaveBeenCalled();
});

test.each([
  { sha256: 'b'.repeat(64) },
  { objectKey: 'private/unregistered' },
  { size: 0 },
])(
  'inconsistent artifact metadata cannot read an arbitrary object: %j',
  async (override) => {
    const f = fixture();
    vi.mocked(f.store.artifact).mockResolvedValueOnce({
      sha256: hash,
      objectKey: `artifacts/${hash}`,
      size: 4,
      contentType: 'application/javascript',
      ...override,
    });
    expect((await f.request(`artifacts/${hash}`)).status).toBe(503);
    expect(f.bucket.head).not.toHaveBeenCalled();
    expect(f.bucket.get).not.toHaveBeenCalled();
  },
);
