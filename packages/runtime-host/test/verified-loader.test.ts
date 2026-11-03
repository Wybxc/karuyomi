import { expect, test, vi } from 'vitest';
import { manifest } from './fixtures.js';
import { sha256, VerifiedLoader } from '../src/verified-loader.js';
import { TeaVMDriver, type TeaVMGlobals } from '../src/teavm-driver.js';

const origin = 'https://read.example.com';
const signal = () => new AbortController().signal;
const bytes = new TextEncoder().encode('self.productBuild = true;');
const artifact = async () => {
  const hash = await sha256(bytes);
  return {
    path: `/api/extensions/artifacts/${hash}`,
    sha256: hash,
    size: bytes.byteLength,
  };
};

test('private asset fetch preserves origin credentials and disallows redirects', async () => {
  const fetcher = vi.fn(
    async () =>
      new Response(bytes, {
        headers: { 'Content-Type': 'application/javascript' },
      }),
  );
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  expect(await loader.artifact(await artifact(), signal(), true)).toEqual(
    bytes,
  );
  expect(fetcher).toHaveBeenCalledWith(
    `${origin}${(await artifact()).path}`,
    expect.objectContaining({
      credentials: 'same-origin',
      redirect: 'manual',
      cache: 'no-cache',
    }),
  );
});

test.each([
  { status: 401, code: 'access_required' },
  { status: 403, code: 'access_denied' },
  { status: 302, code: 'access_required' },
])(
  'separates Access responses from Source errors: $status',
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
  ).rejects.toMatchObject({ code: 'access_required' });
  expect(importScript).not.toHaveBeenCalled();
});

test('hash mismatch never reaches script execution', async () => {
  const tampered = new Uint8Array(bytes);
  tampered[0] = 0;
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response(tampered, {
        headers: { 'Content-Type': 'application/javascript' },
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
      new Response(bytes.subarray(1), {
        headers: { 'Content-Type': 'application/javascript' },
      })) as typeof fetch,
  );
  await expect(
    short.artifact(await artifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  const long = new VerifiedLoader(
    origin,
    (async () =>
      new Response(new Uint8Array(bytes.byteLength + 1), {
        headers: { 'Content-Type': 'application/javascript' },
      })) as typeof fetch,
  );
  await expect(
    long.artifact(await artifact(), signal(), true),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
});

test('cross-origin and public manifest paths cannot be fetched', async () => {
  const fetcher = vi.fn();
  const loader = new VerifiedLoader(origin, fetcher as typeof fetch);
  await expect(
    loader.manifest(
      'https://attacker.example/api/extensions/builds/test/manifest',
      signal(),
    ),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  await expect(
    loader.manifest('/runtime/build.json', signal()),
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
      { ...value, path: `/runtime/materials/${value.sha256}` },
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
  const corrupt = new Uint8Array(bytes);
  corrupt[0] ^= 1;
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
    loader.manifest('/api/extensions/builds/test/manifest', signal()),
  ).rejects.toMatchObject({ code: 'protocol_error' });
});

test('real TeaVM export handshake validates loaded Source IDs before readiness', async () => {
  const scope: TeaVMGlobals = {};
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response(bytes, {
        headers: { 'Content-Type': 'application/javascript' },
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
    },
    origin,
  );
  await expect(
    driver.open(await manifest(), 'test', signal()),
  ).rejects.toMatchObject({ code: 'integrity_error' });
});

test('Access expiry cannot be swallowed as successful Source data by a Java error handler', async () => {
  const scope: TeaVMGlobals = {};
  const build = await manifest();
  const loader = new VerifiedLoader(
    origin,
    (async () =>
      new Response(bytes, {
        headers: { 'Content-Type': 'application/javascript' },
      })) as typeof fetch,
  );
  const fetcher = vi.fn(async () => new Response('', { status: 401 }));
  vi.stubGlobal('fetch', fetcher);
  const driver = new TeaVMDriver(
    scope,
    loader,
    () => {
      scope.hostInit = () => scope.teaDone?.('"ready"');
      scope.hostLoad = () =>
        scope.teaDone?.(
          JSON.stringify([
            { id: build.sourceIds[0], name: 'Test', lang: 'en' },
          ]),
        );
      scope.hostInvoke = () => {
        void scope.teaHttp!('{}').catch(() => {
          scope.teaDone?.('{"mangas":[],"hasNextPage":false}');
        });
      };
    },
    origin,
  );
  try {
    await driver.open(build, 'test', signal());
    await expect(
      driver.invoke(build.sourceIds[0]!, 'popular', { page: 1 }),
    ).rejects.toMatchObject({ code: 'access_required' });
    expect(fetcher).toHaveBeenCalledWith(
      new URL('/api/bridge/http', origin),
      expect.objectContaining({
        credentials: 'same-origin',
        redirect: 'manual',
        headers: expect.objectContaining({
          'X-App-Request': '1',
          'X-Runtime-Build': build.buildId,
        }),
      }),
    );
  } finally {
    await driver.close();
    vi.unstubAllGlobals();
  }
});

async function sharedArtifact() {
  const value = await artifact();
  return { ...value, path: `/runtime/materials/${value.sha256}` };
}
