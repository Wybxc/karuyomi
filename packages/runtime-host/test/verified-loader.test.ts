import { expect, test, vi } from 'vitest';
import { HTTP_BRIDGE_MEDIA_TYPE } from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { gzipSync } from 'node:zlib';
import { manifest, artifact, bytes, encodedBytes } from './fixtures.js';
import { sha256, VerifiedLoader } from '../src/verified-loader.js';
import { TeaVMDriver, type TeaVMGlobals } from '../src/teavm-driver.js';

const origin = 'https://read.example.com';
const signal = () => new AbortController().signal;
const sourceCall = (sourceId: string) =>
  create(pb.SourceCallSchema, {
    requestId: 'metadata',
    generation: 'generation',
    sourceId,
    request: { case: 'popular', value: { page: 1 } },
  });
test('static gzip fetch omits credentials and verifies both byte domains', async () => {
  const fetcher = vi.fn(
    async () =>
      new Response(encodedBytes, {
        headers: { 'Content-Type': 'application/gzip' },
      }),
  );
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  expect(await loader.artifact(await artifact(), signal(), true)).toEqual(
    bytes,
  );
  expect(fetcher).toHaveBeenCalledWith(
    `${origin}${(await artifact()).path}`,
    expect.objectContaining({
      credentials: 'omit',
      redirect: 'manual',
      cache: 'force-cache',
    }),
  );
});

test('each gzip byte domain is hashed exactly once at the loading boundary', async () => {
  const value = await artifact();
  const digest = vi.spyOn(crypto.subtle, 'digest');
  try {
    const loader = new VerifiedLoader(
      origin,
      async () =>
        new Response(encodedBytes, {
          headers: { 'Content-Type': 'application/gzip' },
        }),
    );
    expect(await loader.artifact(value, signal(), true)).toEqual(bytes);
    expect(digest).toHaveBeenCalledTimes(2);
    expect(digest.mock.calls.map((call) => call[1].byteLength)).toEqual([
      encodedBytes.length,
      bytes.length,
    ]);
  } finally {
    digest.mockRestore();
  }
});

test('gzip validation rejects a valid compressed hash with wrong canonical hash or size', async () => {
  const value = await artifact();
  for (const changed of [
    {
      ...value,
      sha256: 'a'.repeat(64),
      path: '/extensions/artifacts/' + 'a'.repeat(64) + '.gz',
    },
    { ...value, size: value.size - 1 },
    { ...value, size: value.size + 1 },
  ]) {
    const loader = new VerifiedLoader(
      origin,
      async () =>
        new Response(encodedBytes, {
          headers: { 'Content-Type': 'application/gzip' },
        }),
    );
    await expect(
      loader.artifact(changed, signal(), true),
    ).rejects.toMatchObject({
      code: changed.size < value.size ? 'limit_exceeded' : 'integrity_error',
    });
  }
});

test('truncated gzip and a small compressed decompression bomb fail before execution', async () => {
  const value = await artifact();
  const bomb = new Uint8Array(gzipSync(new Uint8Array(1024 * 1024)));
  for (const encoded of [encodedBytes.slice(0, -1), bomb]) {
    const changed = {
      ...value,
      encodedSize: encoded.length,
      encodedSha256: await sha256(encoded),
    };
    const loader = new VerifiedLoader(
      origin,
      async () =>
        new Response(encoded, {
          headers: { 'Content-Type': 'application/gzip' },
        }),
    );
    await expect(
      loader.artifact(changed, signal(), true),
    ).rejects.toMatchObject({
      code: encoded === bomb ? 'limit_exceeded' : 'integrity_error',
    });
  }
});

test('the gzip file cannot be transparently marked as HTTP content encoding', async () => {
  const cancelled = vi.fn();
  const loader = new VerifiedLoader(
    origin,
    async () =>
      new Response(new ReadableStream<Uint8Array>({ cancel: cancelled }), {
        headers: {
          'Content-Type': 'application/gzip',
          'Content-Encoding': 'gzip',
        },
      }),
  );
  await expect(
    loader.artifact(await artifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(cancelled).toHaveBeenCalledOnce();
});

test('aborting an encoded download cancels its reader even when a custom fetch ignores the signal', async () => {
  const cancelled = vi.fn();
  let reading: (() => void) | undefined;
  const started = new Promise<void>((resolve) => {
    reading = resolve;
  });
  const loader = new VerifiedLoader(
    origin,
    async () =>
      new Response(
        new ReadableStream<Uint8Array>(
          {
            pull() {
              reading?.();
              return new Promise<void>(() => {});
            },
            cancel: cancelled,
          },
          { highWaterMark: 0 },
        ),
        { headers: { 'Content-Type': 'application/gzip' } },
      ),
  );
  const controller = new AbortController();
  const pending = loader.artifact(await artifact(), controller.signal, true);
  const failure = expect(pending).rejects.toMatchObject({ name: 'AbortError' });
  await started;
  controller.abort();
  await failure;
  expect(cancelled).toHaveBeenCalledOnce();
});

test('static manifest path must match its returned build and cannot use API fallback', async () => {
  const build = await manifest();
  const fetcher = vi.fn(async () => Response.json(build));
  const loader = new VerifiedLoader(origin, fetcher);
  expect(
    await loader.manifest(
      '/extensions/builds/test-build/manifest.json',
      signal(),
    ),
  ).toEqual(build);
  expect(fetcher).toHaveBeenCalledWith(
    origin + '/extensions/builds/test-build/manifest.json',
    expect.objectContaining({
      credentials: 'omit',
      cache: 'no-cache',
      redirect: 'manual',
    }),
  );
  await expect(
    loader.manifest('/extensions/builds/other/manifest.json', signal()),
  ).rejects.toMatchObject({ code: 'protocol_error' });
});

test('static index accepts more than 64KiB, validates current package uniqueness and bounds JSON', async () => {
  const builds = Array.from({ length: 1000 }, (_, index) => ({
    buildId: 'build-' + index,
    packageName: 'package-' + index,
    repoId: 'repo',
    version: '1',
    sourceIds: [String(index)],
    manifestPath: '/extensions/builds/build-' + index + '/manifest.json',
  }));
  const value = { schemaVersion: 1, builds };
  const fetcher = vi.fn(async () => Response.json(value));
  expect(
    (await new VerifiedLoader(origin, fetcher).index(signal())).builds,
  ).toHaveLength(1000);
  expect(fetcher).toHaveBeenCalledWith(
    origin + '/extensions/index.json',
    expect.objectContaining({ credentials: 'omit', cache: 'no-cache' }),
  );
  const duplicate = new VerifiedLoader(origin, async () =>
    Response.json({ ...value, builds: [builds[0], builds[0]] }),
  );
  await expect(duplicate.index(signal())).rejects.toMatchObject({
    code: 'protocol_error',
  });
  const oversized = new VerifiedLoader(
    origin,
    async () =>
      new Response('x'.repeat(2 * 1024 * 1024 + 1), {
        headers: { 'Content-Type': 'application/json' },
      }),
  );
  await expect(oversized.index(signal())).rejects.toMatchObject({
    code: 'limit_exceeded',
  });
});

test.each([
  { status: 401, code: 'runtime_lost' },
  { status: 403, code: 'runtime_lost' },
  { status: 302, code: 'protocol_error' },
])(
  'static delivery failures never fall back to Access APIs: $status',
  async ({ status, code }) => {
    const loader = new VerifiedLoader(
      origin,
      (async () => new Response('', { status })) as typeof fetch,
    );
    await expect(
      loader.artifact(await artifact(), signal(), true),
    ).rejects.toMatchObject({ code });
  },
);

test('login HTML is never executed as a bundle, even with HTTP 200', async () => {
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response('<html>login</html>', {
        headers: { 'Content-Type': 'text/html' },
      })) as typeof fetch,
  );
  const scope: TeaVMGlobals = {};
  const importScript = vi.fn();
  const driver = new TeaVMDriver(scope, loader, importScript, origin);
  await expect(
    driver.open(await manifest(), 'test', signal()),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(importScript).not.toHaveBeenCalled();
});

test('hash mismatch never reaches script execution', async () => {
  const tampered = new Uint8Array(encodedBytes);
  tampered[0] = 0;
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response(tampered, {
        headers: { 'Content-Type': 'application/gzip' },
      })) as typeof fetch,
  );
  const importScript = vi.fn();
  const driver = new TeaVMDriver({}, loader, importScript, origin);
  await expect(
    driver.open(await manifest(), 'test', signal()),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  expect(importScript).not.toHaveBeenCalled();
});

test('streamed over-budget and truncated artifacts fail before execution', async () => {
  const short = new VerifiedLoader(
    origin,
    (async () =>
      new Response(encodedBytes.subarray(1), {
        headers: { 'Content-Type': 'application/gzip' },
      })) as typeof fetch,
  );
  await expect(
    short.artifact(await artifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  const long = new VerifiedLoader(
    origin,
    (async () =>
      new Response(new Uint8Array(encodedBytes.byteLength + 1), {
        headers: { 'Content-Type': 'application/gzip' },
      })) as typeof fetch,
  );
  await expect(
    long.artifact(await artifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
});

test('cross-origin and old API manifest paths cannot be fetched', async () => {
  const fetcher = vi.fn();
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  await expect(
    loader.manifest(
      'https://attacker.example/extensions/builds/test/manifest.json',
      signal(),
    ),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  await expect(
    loader.manifest('/api/extensions/builds/test/manifest', signal()),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(fetcher).not.toHaveBeenCalled();
});

test('Web shared materials always use credential-free static digest paths', async () => {
  const fetcher = vi.fn(
    async () =>
      new Response(bytes, {
        headers: { 'Content-Type': 'application/javascript; charset=utf-8' },
      }),
  );
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  const value = {
    ...(await sharedArtifact()),
    contentType: 'application/javascript',
  };
  expect(await loader.sharedArtifact(value, signal(), true)).toEqual(bytes);
  expect(fetcher).toHaveBeenCalledWith(
    `${origin}/runtime/materials/${value.sha256}`,
    expect.objectContaining({
      credentials: 'omit',
      redirect: 'manual',
      cache: 'force-cache',
    }),
  );
  await expect(
    loader.artifact(
      { ...(await artifact()), path: `/runtime/materials/${value.sha256}` },
      signal(),
      true,
    ),
  ).rejects.toMatchObject({ code: 'integrity_error' });
});

test('Native shared materials use only bundled bytes and never fall back to network', async () => {
  const fetcher = vi.fn();
  const value = {
    ...(await sharedArtifact()),
    contentType: 'application/javascript',
  };
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch, (hash) =>
    hash === value.sha256
      ? { bytes, contentType: 'application/javascript' }
      : undefined,
  );
  const loaded = await loader.sharedArtifact(value, signal(), true);
  expect(loaded).toEqual(bytes);
  expect(loaded).not.toBe(bytes);
  const missing = new VerifiedLoader(
    origin,
    fetcher as typeof fetch,
    () => undefined,
  );
  await expect(
    missing.sharedArtifact(value, signal(), true),
  ).rejects.toMatchObject({ code: 'unsupported_capability' });
  expect(fetcher).not.toHaveBeenCalled();
});

test('shared materials reject changed bytes, MIME and paths before execution', async () => {
  const value = {
    ...(await sharedArtifact()),
    contentType: 'application/javascript',
  };
  const corrupt = Uint8Array.from(bytes, (byte) => byte ^ 1);
  for (const material of [
    { bytes: corrupt, contentType: 'application/javascript' },
    { bytes, contentType: 'text/html' },
    { bytes: bytes.subarray(1), contentType: 'application/javascript' },
  ]) {
    const loader = new VerifiedLoader(origin, vi.fn(), () => material);
    await expect(
      loader.sharedArtifact(value, signal(), true),
    ).rejects.toMatchObject({ code: 'integrity_error' });
  }
  const fetcher = vi.fn();
  await expect(
    new VerifiedLoader(origin, fetcher).sharedArtifact(
      { ...value, path: 'https://attacker.example/' + value.sha256 },
      signal(),
      true,
    ),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  expect(fetcher).not.toHaveBeenCalled();
});

test('unavailable Web material never falls back to the private artifact endpoint', async () => {
  const fetcher = vi.fn(async () => new Response('', { status: 404 }));
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  await expect(
    loader.sharedArtifact(await sharedArtifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'unsupported_capability' });
  expect(fetcher).toHaveBeenCalledTimes(1);
});

test('incompatible manifest ABI is rejected as protocol error', async () => {
  const value = { ...(await manifest()), hostAbi: 'wrong-abi' };
  const loader = new VerifiedLoader(origin, (async () =>
    Response.json(value)) as typeof fetch);
  await expect(
    loader.manifest('/extensions/builds/test-build/manifest.json', signal()),
  ).rejects.toMatchObject({ code: 'protocol_error' });
});

test('real TeaVM export handshake validates loaded Source IDs before readiness', async () => {
  const scope: TeaVMGlobals = {};
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response(encodedBytes, {
        headers: { 'Content-Type': 'application/gzip' },
      })) as typeof fetch,
  );
  const driver = new TeaVMDriver(
    scope,
    loader,
    () => {
      scope.hostInit = () => scope.teaDone?.('"ready"');
      scope.hostLoad = () =>
        scope.teaDone?.(
          JSON.stringify([{ id: '1', name: 'Wrong Source', lang: 'en' }]),
        );
      scope.hostInvoke = () => {};
      scope.hostAcquireImage = () => {};
      scope.hostClosePageSession = () => {};
    },
    origin,
  );
  await expect(
    driver.open(await manifest(), 'test', signal()),
  ).rejects.toMatchObject({ code: 'integrity_error' });
});

test.each([
  { status: 401, code: 'access_required' },
  { status: 403, code: 'access_denied' },
])(
  'Access $status cannot be swallowed as successful Source data by a Java error handler',
  async ({ status, code }) => {
    const scope: TeaVMGlobals = {};
    const build = await manifest();
    const loader = new VerifiedLoader(
      origin,
      (async () =>
        new Response(encodedBytes, {
          headers: { 'Content-Type': 'application/gzip' },
        })) as typeof fetch,
    );
    const fetcher = vi.fn(async () => new Response('', { status }));
    vi.stubGlobal('fetch', fetcher);
    const driver = new TeaVMDriver(
      scope,
      loader,
      () => {
        scope.hostInit = () => scope.teaDone?.('"ready"');
        scope.hostAcquireImage = () => {};
        scope.hostClosePageSession = () => {};
        scope.hostLoad = () =>
          scope.teaDone?.(
            JSON.stringify([
              { id: build.sourceIds[0], name: 'Test', lang: 'en' },
            ]),
          );
        scope.hostInvoke = () => {
          const handle = scope.teaHttpOpen!(
            JSON.stringify({
              url: 'https://source.example/catalog',
              method: 'GET',
              headers: [],
              hasBody: false,
              bodyLength: 0,
              timeoutMs: 30_000,
            }),
          );
          void scope.teaHttpFinish!(handle).catch(() => {
            // A Source can catch the Java IOException and even make another bad
            // bridge call; the fatal Access failure must survive both handlers.
            try {
              scope.teaHttpOpen!('{}');
            } catch {}
            scope.teaDone?.('{"mangas":[],"hasNextPage":false}');
          });
        };
      },
      origin,
    );
    try {
      expect(
        Object.keys(scope)
          .filter((key) => key.startsWith('teaHttp'))
          .sort(),
      ).toEqual([
        'teaHttpCancel',
        'teaHttpClose',
        'teaHttpFinish',
        'teaHttpOpen',
        'teaHttpRead',
        'teaHttpWrite',
      ]);
      await driver.open(build, 'test', signal());
      await expect(
        driver.invoke(sourceCall(build.sourceIds[0]!)),
      ).rejects.toMatchObject({ code });
      expect(fetcher).toHaveBeenCalledWith(
        new URL('/api/bridge/http', origin),
        expect.objectContaining({
          credentials: 'same-origin',
          redirect: 'manual',
          headers: expect.objectContaining({
            Accept: HTTP_BRIDGE_MEDIA_TYPE,
            'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
            'X-App-Request': '1',
            'X-Runtime-Build': build.buildId,
          }),
        }),
      );
    } finally {
      await driver.close();
      vi.unstubAllGlobals();
    }
  },
);

async function sharedArtifact() {
  const hash = await sha256(bytes);
  return {
    path: `/runtime/materials/${hash}`,
    sha256: hash,
    size: bytes.length,
  };
}

test('the installed v2 finish callback carries a controlled connection flag through TeaVM failure handling', async () => {
  const scope: TeaVMGlobals = {};
  const build = await manifest();
  const rejected: unknown[] = [];
  const loader = new VerifiedLoader(
    origin,
    async () =>
      new Response(encodedBytes, {
        headers: { 'Content-Type': 'application/gzip' },
      }),
  );
  vi.stubGlobal('fetch', async () => {
    throw new TypeError(
      'Failed to fetch https://source.invalid/?secret=never-reflect',
    );
  });
  const driver = new TeaVMDriver(
    scope,
    loader,
    () => {
      scope.hostInit = () => scope.teaDone?.('"ready"');
      scope.hostAcquireImage = () => {};
      scope.hostClosePageSession = () => {};
      scope.hostLoad = () =>
        scope.teaDone?.(
          JSON.stringify([
            { id: build.sourceIds[0], name: 'Test', lang: 'en' },
          ]),
        );
      scope.hostInvoke = () => {
        const handle = scope.teaHttpOpen!(
          JSON.stringify({
            url: 'https://source.example/catalog',
            method: 'GET',
            headers: [],
            hasBody: false,
            bodyLength: 0,
            timeoutMs: 30_000,
          }),
        );
        void scope.teaHttpFinish!(handle).catch((error: unknown) => {
          rejected.push(error);
          scope.teaFail?.('java.io.IOException: Source request failed');
        });
      };
    },
    origin,
  );
  try {
    await driver.open(build, 'test', signal());
    await expect(
      driver.invoke(sourceCall(build.sourceIds[0]!)),
    ).rejects.toMatchObject({
      code: 'source_error',
      message: 'Source bridge connection failed',
      retryable: true,
    });
    expect(rejected).toHaveLength(1);
    expect(rejected[0]).toMatchObject({
      retryable: true,
      message: 'Source bridge connection failed',
    });
  } finally {
    await driver.close();
    vi.unstubAllGlobals();
  }
});
