#!/usr/bin/env node
import { buildProbeApi } from './probe-build.ts';
// Real workerd HTTP-v2 integration against a controlled binary HTTP origin.
// Production entry points/configuration never import or enable this fixture.
import assert from 'node:assert/strict';
import { unstable_readConfig } from 'wrangler';
import { createHash } from 'node:crypto';
import { createServer, type RequestListener } from 'node:http';
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
import { Readable } from 'node:stream';
import type { Socket } from 'node:net';
import {
  buildConnector,
  Client,
  request as socketRequest,
  Response,
} from 'undici';
import { gzipSync, brotliCompressSync } from 'node:zlib';
import { byteStream } from './http-probe-streams.ts';
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
const {
  Miniflare,
  convertV4MiniflareOptions,
  HttpOptions_Style,
}: typeof import('miniflare') = await import(
  wranglerRequire.resolve('miniflare')
);
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
const appOrigin = 'http://127.0.0.1';
let slowOpened = 0;
let slowClosed = 0;
let truncateBody: (() => void) | undefined;
const originHandler: RequestListener = async (request, response) => {
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
  if (url.pathname === '/empty') {
    const status = Number(url.searchParams.get('status'));
    assert([204, 205, 304].includes(status));
    response.writeHead(status, {
      ETag: '"fixture-representation"',
      'Cache-Control': 'max-age=60',
      ...(status === 304
        ? {
            'Content-Encoding': 'gzip',
            'Content-Length': compressed.gzip.length,
          }
        : {}),
    });
    response.end();
    return;
  }
  if (url.pathname === '/range') {
    assert.equal(request.headers.range, 'bytes=65533-65551');
    response.writeHead(206, {
      'Content-Type': 'application/octet-stream',
      'Content-Range': `bytes 65533-65551/${payload.length}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': 19,
    });
    response.end(payload.subarray(65533, 65552));
    return;
  }
  if (url.pathname === '/inspect-form') {
    // The standard parser consumes only this small controlled form fixture.
    const chunks: Uint8Array[] = [];
    let size = 0;
    for await (const value of request) {
      assert(value instanceof Uint8Array);
      size += value.byteLength;
      assert(size <= HTTP_FRAME_LIMIT * 2);
      chunks.push(value);
    }
    const contentType = request.headers['content-type'];
    assert(typeof contentType === 'string');
    const form = await new Request('http://fixture.example.org/inspect-form', {
      method: 'POST',
      headers: { 'Content-Type': contentType },
      body: new Uint8Array(Buffer.concat(chunks)),
    }).formData();
    const file = form.get('image');
    assert(file === null || file instanceof File);
    response.setHeader('Content-Type', 'application/json');
    response.end(
      JSON.stringify({
        notes: form.getAll('note'),
        file:
          file === null
            ? null
            : {
                name: file.name,
                type: file.type,
                size: file.size,
                sha256: sha256(new Uint8Array(await file.arrayBuffer())),
              },
      }),
    );
    return;
  }
  if (url.pathname === '/truncate') {
    response.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': payload.length,
    });
    response.write(payload.subarray(0, HTTP_FRAME_LIMIT + 7));
    truncateBody = () => response.destroy();
    return;
  }
  if (url.pathname === '/slow') {
    ++slowOpened;
    response.writeHead(200, { 'Content-Type': 'application/octet-stream' });
    response.write(payload.subarray(0, 1024));
    const interval = url.searchParams.has('paused')
      ? undefined
      : setInterval(() => {
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
};
// workerd's PROXY request line carries the complete URL and may omit Host.
const origin = createServer({ requireHostHeader: false }, originHandler);
await new Promise<void>((resolve) => origin.listen(0, '127.0.0.1', resolve));
const address = origin.address();
assert(address && typeof address !== 'string');
let mf: import('miniflare').Miniflare | undefined;
let client: Client | undefined;
const checks: string[] = [];
const cancellationTimings: {
  check: string;
  requestTimeoutMs: number;
  cancellationBudgetMs: number;
  elapsedMs: number;
  tcpReset: boolean;
}[] = [];
const cancellationBudgetMs = 1000;
const cancellationRequestTimeoutMs = 30_000;
async function assertPromptCancellation(
  check: string,
  cancel: () => Promise<void>,
  tcpReset = false,
) {
  const opened = slowOpened;
  assert.equal(slowClosed, opened - 1, `${check}: origin must still be active`);
  const started = performance.now();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let observing = true;
  try {
    await Promise.race([
      Promise.all([
        cancel(),
        (async () => {
          while (observing && slowClosed < opened)
            await new Promise((resolve) => setTimeout(resolve, 10));
        })(),
      ]),
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${check}: origin did not close promptly`)),
          cancellationBudgetMs,
        );
      }),
    ]);
    const elapsedMs = performance.now() - started;
    assert(
      elapsedMs <= cancellationBudgetMs,
      `${check}: cancellation was late`,
    );
    cancellationTimings.push({
      check,
      requestTimeoutMs: cancellationRequestTimeoutMs,
      cancellationBudgetMs,
      elapsedMs,
      tcpReset,
    });
    checks.push(check);
  } finally {
    observing = false;
    clearTimeout(timer);
  }
}
try {
  const keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'http-v2-fixture';
  const { script: apiScript } = await buildProbeApi(temporary);
  const config = unstable_readConfig(
    { config: path.join(root, 'apps/api/wrangler.jsonc') },
    { hideWarnings: true },
  );
  assert(config.compatibility_date, 'Worker compatibility date is required');
  mf = new Miniflare(
    convertV4MiniflareOptions({
      resourcePersistencePath: path.join(temporary, 'state'),
      workers: [
        {
          name: 'http-v2-api',
          modules: true,
          script: apiScript,
          compatibilityDate: config.compatibility_date,
          compatibilityFlags: config.compatibility_flags,
          // Use the user Worker socket, with the product's request-signal flags.
          unsafeDirectSockets: [
            { host: '127.0.0.1', port: 0, entrypoint: 'default', proxy: false },
          ],
          outboundService: 'http-v2-origin',
          d1Databases: { DB: 'http-v2-fixture' },
          bindings: {
            ACCESS_TEAM_DOMAIN: 'probe.cloudflareaccess.com',
            ACCESS_AUD: 'http-v2',
            ACCESS_SUBJECT: 'probe-owner',
            OWNER_EMAIL: 'probe@example.com',
            APP_ORIGIN: appOrigin,
            PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
          },
        },
        {
          name: 'http-v2-origin',
          modules: true,
          script: `export default { fetch(request, env) { return env.ORIGIN.fetch(request); } };`,
          compatibilityDate: config.compatibility_date,
          compatibilityFlags: [
            'enable_request_signal',
            'request_signal_passthrough',
          ],
          // A node-handler inserts an old-compat Worker that loses cancellation
          // while the origin is idle. This native service keeps the signal and
          // maps only the test target to the controlled HTTP origin.
          serviceBindings: {
            ORIGIN: {
              external: {
                address: `127.0.0.1:${address.port}`,
                http: { style: HttpOptions_Style.PROXY },
              },
            },
          },
        },
      ],
    }),
  );
  const db = await mf.getD1Database('DB', 'http-v2-api');
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
  const direct = await mf.unsafeGetDirectURL('http-v2-api');
  let clientSocket: Socket | undefined;
  const connect = buildConnector({});
  client = new Client(direct.origin, {
    pipelining: 0,
    connect(options, callback) {
      connect(options, (...connected) => {
        const [, socket] = connected;
        if (socket) clientSocket = socket;
        callback(...connected);
      });
    },
  });
  const dispatcher = client;
  const resetConnection = () => {
    assert(
      clientSocket && !clientSocket.destroyed,
      'Expected an active client socket',
    );
    // A stalled HTTP/1 response cannot reliably detect ordinary local destroy.
    // Reset the actual TCP connection before releasing the local body reader.
    clientSocket.resetAndDestroy();
  };
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
    socketRequest(new URL('/api/bridge/http', direct), {
      dispatcher,
      method: 'POST',
      headers: {
        Host: new URL(appOrigin).host,
        'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
        Accept: HTTP_BRIDGE_MEDIA_TYPE,
        'X-Runtime-Build': 'v2-fixture',
        'X-App-Request': '1',
        Origin: appOrigin,
        'Cf-Access-Jwt-Assertion': signed,
        ...headers,
      },
      body: Readable.from(wire(meta, bytes, end), {
        objectMode: false,
        highWaterMark: HTTP_FRAME_LIMIT,
      }),
      ...(signal ? { signal } : {}),
    }).then((result) => {
      const responseHeaders = new Headers();
      for (const [name, values] of Object.entries(result.headers))
        if (values !== undefined)
          for (const value of Array.isArray(values) ? values : [values])
            responseHeaders.append(name, value);
      return new Response(result.body, {
        status: result.statusCode,
        headers: Array.from(responseHeaders),
      });
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
  for (const status of [204, 205, 304]) {
    const { reader, meta } = await framed(
      await dispatch(requestMeta(`/empty?status=${status}`)),
    );
    assert.equal(meta.upstreamStatus, status);
    assert.equal(meta.hasBody, false);
    assert.equal(meta.bodyLength, 0);
    assert.equal(meta.decoded, false);
    assert(
      meta.headers.some(
        ([name, value]) =>
          name === 'etag' && value === '"fixture-representation"',
      ),
    );
    if (status === 304) {
      assert(
        meta.headers.some(
          ([name, value]) => name === 'content-encoding' && value === 'gzip',
        ),
      );
      assert(
        meta.headers.some(
          ([name, value]) =>
            name === 'content-length' &&
            Number(value) === compressed.gzip.length,
        ),
      );
    }
    assert.equal(await reader.read(1), null);
    checks.push(`status_${status}_empty_body_and_representation_headers`);
  }
  {
    const { reader, meta } = await framed(
      await dispatch(
        requestMeta('/range', {
          headers: [['Range', 'bytes=65533-65551']],
        }),
      ),
    );
    assert.equal(meta.upstreamStatus, 206);
    assert.equal(meta.bodyLength, 19);
    assert(
      meta.headers.some(
        ([name, value]) =>
          name === 'content-range' &&
          value === `bytes 65533-65551/${payload.length}`,
      ),
    );
    assert.deepEqual(await consume(reader), {
      size: 19,
      sha256: sha256(payload.subarray(65533, 65552)),
    });
    checks.push('range_request_and_exact_partial_response');
  }
  for (const multipart of [false, true]) {
    const notes = ['空格 + & emoji 🦀', 'second=value'];
    const form = multipart ? new FormData() : new URLSearchParams();
    for (const note of notes) form.append('note', note);
    const fileBytes = new Uint8Array(payload.subarray(0, HTTP_FRAME_LIMIT + 7));
    if (form instanceof FormData)
      form.append(
        'image',
        new File([fileBytes], 'fixture.bin', {
          type: 'application/octet-stream',
        }),
      );
    const encoded = new Request('http://fixture.example.org/inspect-form', {
      method: 'POST',
      body: form,
    });
    const contentType = encoded.headers.get('content-type');
    assert(contentType);
    const bytes = new Uint8Array(await encoded.arrayBuffer());
    const { reader, meta } = await framed(
      await dispatch(
        requestMeta('/inspect-form', {
          method: 'POST',
          hasBody: true,
          bodyLength: bytes.length,
          headers: [['Content-Type', contentType]],
        }),
        bytes,
      ),
    );
    assert.equal(meta.upstreamStatus, 200);
    const result: Uint8Array[] = [];
    for (;;) {
      const chunk = await reader.read(HTTP_FRAME_LIMIT);
      if (chunk === null) break;
      assert(chunk.byteLength < 1024);
      result.push(chunk);
    }
    assert.deepEqual(JSON.parse(Buffer.concat(result).toString()), {
      notes,
      file: multipart
        ? {
            name: 'fixture.bin',
            type: 'application/octet-stream',
            size: fileBytes.byteLength,
            sha256: sha256(fileBytes),
          }
        : null,
    });
    checks.push(
      multipart
        ? 'multipart_fields_and_binary_file_preserved'
        : 'urlencoded_fields_and_duplicates_preserved',
    );
  }
  {
    const { reader, meta } = await framed(
      await dispatch(requestMeta('/truncate')),
    );
    assert.equal(meta.upstreamStatus, 200);
    assert.equal(meta.bodyLength, payload.length);
    const prefix = await reader.read(HTTP_FRAME_LIMIT);
    assert(prefix && prefix.byteLength > 0);
    assert.deepEqual(
      prefix,
      new Uint8Array(payload.subarray(0, prefix.byteLength)),
    );
    assert(truncateBody);
    truncateBody();
    truncateBody = undefined;
    await assert.rejects(
      consume(reader),
      (error: unknown) =>
        error instanceof Error &&
        'code' in error &&
        error.code === 'upstream_body_error',
    );
    checks.push('truncated_origin_body_fails_without_success_END');
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
  for (const paused of [false, true]) {
    const { reader } = await framed(
      await dispatch(
        requestMeta(paused ? '/slow?paused' : '/slow', {
          timeoutMs: cancellationRequestTimeoutMs,
        }),
      ),
    );
    assert((await reader.read(1))?.byteLength);
    await assertPromptCancellation(
      `consumer_cancel_closes_origin${paused ? '_after_tcp_reset_while_paused' : ''}`,
      async () => {
        if (paused) resetConnection();
        await reader.cancel();
      },
      paused,
    );
  }
  for (const paused of [false, true]) {
    const abort = new AbortController();
    const { reader } = await framed(
      await dispatch(
        requestMeta(paused ? '/slow?paused' : '/slow', {
          timeoutMs: cancellationRequestTimeoutMs,
        }),
        undefined,
        true,
        {},
        abort.signal,
      ),
    );
    assert((await reader.read(1))?.byteLength);
    const reading = consume(reader);
    const rejection = assert.rejects(reading);
    await assertPromptCancellation(
      `incoming_abort_closes_origin${paused ? '_after_tcp_reset_while_paused' : ''}`,
      async () => {
        if (paused) resetConnection();
        abort.abort();
        await rejection;
      },
      paused,
    );
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
    transport: 'direct-user-worker-http-socket',
    sourceOnlineVerified: false,
    productionAccessVerified: false,
    compatibilityDate: config.compatibility_date,
    compatibilityFlags: config.compatibility_flags,
    payload: expected,
    encodedSizes: { gzip: compressed.gzip.length, br: compressed.br.length },
    checks,
    cancellationTimings,
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
  await client?.destroy();
  await mf?.dispose();
  origin.closeAllConnections();
  await new Promise<void>((resolve) => origin.close(() => resolve()));
  await rm(temporary, { recursive: true, force: true });
}
