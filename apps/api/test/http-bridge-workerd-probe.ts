#!/usr/bin/env node
// Real workerd HTTP-v2 integration against a controlled binary HTTP origin.
// Production entry points/configuration never import or enable this fixture.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer, request as httpRequest } from 'node:http';
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync, brotliCompressSync } from 'node:zlib';
import { byteStream, streamChunks } from './http-probe-streams.ts';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  httpResponseMetaSchema,
  type HttpRequestMeta,
} from '../../../packages/contracts/src/http-frames.ts';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const require = createRequire(new URL('../package.json', import.meta.url));
const wranglerRequire = createRequire(require.resolve('wrangler'));
const { build }: typeof import('esbuild') = await import(
  wranglerRequire.resolve('esbuild')
);
const { Miniflare, convertV4MiniflareOptions }: typeof import('miniflare') =
  await import(wranglerRequire.resolve('miniflare'));
const { generateKeyPair, exportJWK, SignJWT }: typeof import('jose') =
  await import(require.resolve('jose'));
const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-http-v2-'));
const evidencePath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(root, '.local/probes/http-bridge-v2.json');
const payload = Buffer.alloc(HTTP_FRAME_LIMIT * 2 + 17);
for (let index = 0; index < payload.length; ++index)
  payload[index] = (index * 131 + (index >>> 7)) & 255;
const compressed = { gzip: gzipSync(payload), br: brotliCompressSync(payload) };
const sha256 = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
const calls: string[] = [];
let slowOpened = 0;
let slowClosed = 0;
const origin = createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', 'http://fixture.example.org');
  calls.push(url.pathname);
  if (url.pathname === '/echo') {
    assert.equal(request.headers['cf-access-jwt-assertion'], undefined);
    assert.equal(request.headers['x-app-request'], undefined);
    assert.equal(request.headers.authorization, 'Bearer fixture-source-token');
    assert.equal(request.headers.cookie, 'one=1; two=2');
    const hash = createHash('sha256');
    let size = 0;
    for await (const value of request) {
      assert(value instanceof Uint8Array);
      hash.update(value);
      size += value.byteLength;
    }
    response.setHeader('Content-Type', 'application/json');
    response.end(JSON.stringify({ size, sha256: hash.digest('hex') }));
    return;
  }
  if (url.pathname === '/slow') {
    ++slowOpened;
    response.writeHead(200, { 'Content-Type': 'application/octet-stream' });
    response.write(payload.subarray(0, 1024));
    const interval = setInterval(() => {
      response.write(payload.subarray(0, 1024));
    }, 20);
    response.on('close', () => {
      clearInterval(interval);
      ++slowClosed;
    });
    return;
  }
  if (url.pathname === '/early') {
    response.writeHead(Number(url.searchParams.get('status') ?? 403));
    response.end('early');
    return;
  }
  if (url.pathname === '/redirect') {
    response.writeHead(302, { Location: 'http://127.0.0.1/private' });
    response.end('redirect');
    return;
  }
  const encoding = url.pathname === '/br' ? 'br' : 'gzip';
  const bytes = compressed[encoding];
  const status = Number(url.searchParams.get('status') ?? 200);
  response.writeHead(status, {
    'Content-Type': 'application/octet-stream',
    'Content-Encoding': encoding,
    'Content-Length': bytes.length,
    ...(status === 206
      ? { 'Content-Range': `bytes 0-${payload.length - 1}/${payload.length}` }
      : {}),
    'Set-Cookie': [
      'one=1; Path=/; HttpOnly',
      'two=2; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
    ],
  });
  response.end(bytes);
});
await new Promise<void>((resolve) => origin.listen(0, '127.0.0.1', resolve));
const address = origin.address();
assert(address && typeof address !== 'string');
let mf: import('miniflare').Miniflare | undefined;
const checks: string[] = [];
try {
  const keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'http-v2-fixture';
  const compiled = await build({
    entryPoints: [path.join(root, 'apps/api/test/workerd-entry.ts')],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    target: 'es2022',
    write: false,
  });
  assert(compiled.outputFiles.length === 1);
  const wrangler = await readFile(
    path.join(root, 'apps/api/wrangler.jsonc'),
    'utf8',
  );
  const flags: unknown = JSON.parse(
    /"compatibility_flags"\s*:\s*(\[[^\]]*\])/.exec(wrangler)?.[1] ?? '[]',
  );
  assert(
    Array.isArray(flags) &&
      flags.every((value: unknown) => typeof value === 'string'),
  );
  mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: compiled.outputFiles[0]!.text,
      compatibilityDate: '2026-11-03',
      compatibilityFlags: flags,
      // Only this integration fixture maps declared public target names to a
      // loopback origin. No production target/hostname validation is relaxed.
      outboundService: {
        node: (request, response) =>
          new Promise<void>((resolve) => {
            const target = new URL(
              request.url ?? '/',
              'http://fixture.example.org',
            );
            const outbound = httpRequest(
              {
                hostname: '127.0.0.1',
                port: address.port,
                path: target.pathname + target.search,
                method: request.method,
                headers: request.headers,
              },
              (upstream) => {
                response.writeHead(
                  upstream.statusCode ?? 502,
                  upstream.headers,
                );
                upstream.pipe(response);
                response.once('close', () => {
                  upstream.destroy();
                  outbound.destroy();
                  resolve();
                });
              },
            );
            outbound.on('error', () => {
              response.destroy();
              resolve();
            });
            request.once('aborted', () => outbound.destroy());
            request.pipe(outbound);
          }),
      },
      resourcePersistencePath: path.join(temporary, 'state'),
      d1Databases: { DB: 'http-v2-fixture' },
      bindings: {
        ACCESS_TEAM_DOMAIN: 'probe.cloudflareaccess.com',
        ACCESS_AUD: 'http-v2',
        ACCESS_SUBJECT: 'probe-owner',
        OWNER_EMAIL: 'probe@example.com',
        APP_ORIGIN: 'https://read.example.com',
        PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
      },
    }),
  );
  const db = await mf.getD1Database('DB');
  for (const name of (await readdir(path.join(root, 'apps/api/migrations')))
    .filter((name) => name.endsWith('.sql'))
    .sort()) {
    for (const statement of (
      await readFile(path.join(root, 'apps/api/migrations', name), 'utf8')
    ).split('--> statement-breakpoint')) {
      if (statement.trim()) await db.exec(statement.replace(/\n/g, ' '));
    }
  }
  await db
    .prepare(
      'INSERT INTO extension_builds (build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (?,?,?,?,?,?)',
    )
    .bind(
      'v2-fixture',
      'fixture',
      'a'.repeat(64),
      'verified',
      0,
      '["fixture.example.org"]',
    )
    .run();
  const signed = await new SignJWT({ email: 'probe@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: String(jwk.kid) })
    .setSubject('probe-owner')
    .setIssuer('https://probe.cloudflareaccess.com')
    .setAudience('http-v2')
    .setIssuedAt()
    .setExpirationTime('10m')
    .sign(keys.privateKey);
  const worker = mf;
  let serial = 0;
  const requestMeta = (
    pathname: string,
    overrides: Partial<HttpRequestMeta> = {},
  ): HttpRequestMeta => ({
    requestId: `fixture-${++serial}`,
    runtimeGeneration: 'fixture-generation',
    url: `http://fixture.example.org${pathname}`,
    method: 'GET',
    headers: [['Accept-Encoding', 'gzip, br']],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 5000,
    ...overrides,
  });
  async function* wire(meta: HttpRequestMeta, bytes?: Uint8Array, end = true) {
    yield encodePreamble();
    yield encodeMetaFrame(meta);
    if (bytes)
      for (let offset = 0; offset < bytes.length; offset += HTTP_FRAME_LIMIT)
        yield encodeDataFrame(
          bytes.subarray(offset, offset + HTTP_FRAME_LIMIT),
        );
    if (end) yield encodeEndFrame(bytes?.length ?? 0);
  }
  const dispatch = (
    meta: HttpRequestMeta,
    bytes?: Uint8Array,
    end = true,
    headers: Record<string, string> = {},
    signal?: AbortSignal,
  ) =>
    worker.dispatchFetch('https://read.example.com/api/bridge/http', {
      method: 'POST',
      headers: {
        'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
        Accept: HTTP_BRIDGE_MEDIA_TYPE,
        'X-Runtime-Build': 'v2-fixture',
        'X-App-Request': '1',
        Origin: 'https://read.example.com',
        'Cf-Access-Jwt-Assertion': signed,
        ...headers,
      },
      body: wire(meta, bytes, end),
      duplex: 'half',
      ...(signal ? { signal } : {}),
    });
  const framed = async (response: Awaited<ReturnType<typeof dispatch>>) => {
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), HTTP_BRIDGE_MEDIA_TYPE);
    assert.equal(response.headers.get('set-cookie'), null);
    assert(response.body);
    const reader = new HttpFrameReader(
      byteStream(response.body),
      HTTP_RESPONSE_BODY_LIMIT,
    );
    return { reader, meta: httpResponseMetaSchema.parse(await reader.meta()) };
  };
  const consume = async (reader: HttpFrameReader) => {
    const hash = createHash('sha256');
    let size = 0;
    for (;;) {
      const data = await reader.read(HTTP_FRAME_LIMIT);
      if (data === null) break;
      assert(data.length <= HTTP_FRAME_LIMIT);
      hash.update(data);
      size += data.length;
    }
    return { size, sha256: hash.digest('hex') };
  };
  const expected = { size: payload.length, sha256: sha256(payload) };
  for (const encoding of ['gzip', 'br']) {
    for (const status of [200, 206, 403]) {
      const { reader, meta } = await framed(
        await dispatch(requestMeta(`/${encoding}?status=${status}`)),
      );
      assert.equal(meta.upstreamStatus, status);
      assert.equal(meta.decoded, true);
      assert.equal(meta.bodyLength, null);
      assert(
        !meta.headers.some(([name]) =>
          ['content-encoding', 'content-length'].includes(name),
        ),
      );
      assert.deepEqual(
        meta.headers
          .filter(([name]) => name === 'set-cookie')
          .map(([, value]) => value),
        [
          'one=1; Path=/; HttpOnly',
          'two=2; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
        ],
      );
      if (status === 206)
        assert(meta.headers.some(([name]) => name === 'content-range'));
      assert.deepEqual(await consume(reader), expected);
      checks.push(`real_${encoding}_bytes_status_${status}_decoded_once`);
    }
    const { reader, meta } = await framed(
      await dispatch(requestMeta(`/${encoding}`, { method: 'HEAD' })),
    );
    assert.equal(meta.hasBody, false);
    assert.equal(meta.decoded, false);
    assert(
      meta.headers.some(
        ([name, value]) => name === 'content-encoding' && value === encoding,
      ),
    );
    assert(
      meta.headers.some(
        ([name, value]) =>
          name === 'content-length' &&
          Number(value) ===
            compressed[encoding === 'br' ? 'br' : 'gzip'].length,
      ),
    );
    assert.equal(await reader.read(1), null);
    checks.push(`${encoding}_HEAD_representation_headers`);
  }
  {
    const before = calls.length;
    const { reader, meta } = await framed(
      await dispatch(requestMeta('/redirect')),
    );
    assert.equal(meta.upstreamStatus, 302);
    assert(
      meta.headers.some(
        ([name, value]) =>
          name === 'location' && value === 'http://127.0.0.1/private',
      ),
    );
    await consume(reader);
    assert.equal(calls.length, before + 1);
    checks.push('manual_redirect_not_followed');
  }
  {
    const bytes = payload.subarray(0, HTTP_FRAME_LIMIT + 11);
    const { reader } = await framed(
      await dispatch(
        requestMeta('/echo', {
          method: 'POST',
          hasBody: true,
          bodyLength: bytes.length,
          headers: [
            ['Authorization', 'Bearer fixture-source-token'],
            ['Cookie', 'one=1'],
            ['Cookie', 'two=2'],
            ['Cf-Access-Jwt-Assertion', 'must-not-leak'],
            ['X-App-Request', 'must-not-leak'],
          ],
        }),
        bytes,
      ),
    );
    const chunks: Uint8Array[] = []; // bounded small JSON fixture response only
    for (;;) {
      const data = await reader.read(HTTP_FRAME_LIMIT);
      if (data === null) break;
      assert(data.length < 1024);
      chunks.push(data);
    }
    assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString()), {
      size: bytes.length,
      sha256: sha256(bytes),
    });
    checks.push('streaming_binary_upload_identity');
  }
  for (const status of [200, 302, 403]) {
    for (const valid of [true, false]) {
      const bytes = new Uint8Array([0, 255]);
      const result = await dispatch(
        requestMeta(`/early?status=${status}`, {
          method: 'POST',
          hasBody: true,
          bodyLength: 2,
        }),
        bytes,
        valid,
      );
      if (!valid && result.status === 400) {
        assert.deepEqual(await result.json(), {
          error: 'invalid_bridge_request',
        });
        continue;
      }
      const { reader, meta } = await framed(result);
      assert.equal(meta.upstreamStatus, status);
      if (valid) await consume(reader);
      else
        await assert.rejects(
          consume(reader),
          (error: unknown) =>
            error instanceof Error &&
            'code' in error &&
            error.code === 'invalid_bridge_request',
        );
    }
  }
  checks.push('early_200_302_403_require_upload_END');
  {
    const { reader } = await framed(await dispatch(requestMeta('/slow')));
    assert((await reader.read(1))?.byteLength);
    await reader.cancel();
    const deadline = Date.now() + 5000;
    while (slowClosed < slowOpened && Date.now() < deadline)
      await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(slowClosed, slowOpened);
    checks.push('consumer_cancel_closes_origin');
  }
  {
    const abort = new AbortController();
    const { reader } = await framed(
      await dispatch(requestMeta('/slow'), undefined, true, {}, abort.signal),
    );
    assert((await reader.read(1))?.byteLength);
    const reading = consume(reader);
    const rejection = assert.rejects(reading);
    abort.abort();
    await rejection;
    const deadline = Date.now() + 5000;
    while (slowClosed < slowOpened && Date.now() < deadline)
      await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(slowClosed, slowOpened);
    checks.push('incoming_abort_closes_origin');
  }
  {
    const { reader } = await framed(
      await dispatch(requestMeta('/slow', { timeoutMs: 100 })),
    );
    await assert.rejects(
      consume(reader),
      (error: unknown) =>
        error instanceof Error && 'code' in error && error.code === 'timeout',
    );
    const deadline = Date.now() + 5000;
    while (slowClosed < slowOpened && Date.now() < deadline)
      await new Promise((resolve) => setTimeout(resolve, 20));
    assert.equal(slowClosed, slowOpened);
    checks.push('timeout_closes_origin');
  }
  const beforeDenied = calls.length;
  assert.equal(
    (
      await dispatch(requestMeta('/gzip'), undefined, true, {
        'Cf-Access-Jwt-Assertion': '',
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await dispatch(requestMeta('/gzip'), undefined, true, {
        Origin: 'https://evil.example.org',
      })
    ).status,
    403,
  );
  assert.equal(
    (
      await dispatch(requestMeta('/gzip'), undefined, true, {
        'X-Runtime-Build': 'unknown',
      })
    ).status,
    404,
  );
  assert.equal(
    (await dispatch(requestMeta('/gzip', { url: 'http://127.0.0.1/private' })))
      .status,
    403,
  );
  assert.equal(
    (
      await dispatch(requestMeta('/gzip'), undefined, true, {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      })
    ).status,
    415,
  );
  assert.equal(calls.length, beforeDenied);
  checks.push('auth_origin_build_target_and_v1_rejected_before_origin');
  const report = {
    probe: 'real-workerd-http-v2-controlled-origin',
    passed: true,
    realRS256Verification: true,
    realD1Policy: true,
    controlledOrigin: true,
    sourceOnlineVerified: false,
    productionAccessVerified: false,
    compatibilityFlags: flags,
    payload: expected,
    encodedSizes: { gzip: compressed.gzip.length, br: compressed.br.length },
    checks,
    sourceSha256: Object.fromEntries(
      await Promise.all(
        [
          'apps/api/src/http-bridge.ts',
          'apps/api/test/http-bridge-workerd-probe.ts',
          'apps/api/test/http-probe-streams.ts',
        ].map(async (name) => [
          name,
          sha256(await readFile(path.join(root, name))),
        ]),
      ),
    ),
  };
  await mkdir(path.dirname(evidencePath), { recursive: true });
  await writeFile(evidencePath, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
} finally {
  await mf?.dispose();
  origin.closeAllConnections();
  await new Promise<void>((resolve) => origin.close(() => resolve()));
  await rm(temporary, { recursive: true, force: true });
}
