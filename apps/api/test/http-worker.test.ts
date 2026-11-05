import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  httpResponseMetaSchema,
  type HttpRequestMeta,
} from '@karuyomi/contracts';
import { setupNetwork } from '@msw/cloudflare';
import { env, exports } from 'cloudflare:workers';
import { applyD1Migrations } from 'cloudflare:test';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { http, HttpResponse } from 'msw';
import { gzipSync } from 'node:zlib';
import {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
  expect,
  test,
} from 'vitest';

const appOrigin = 'https://read.example.com';
const upstreamOrigin = 'https://fixture.example.org';
const buildId = 'http-workers-fixture';
const network = setupNetwork();
const payload = Uint8Array.from(
  { length: HTTP_FRAME_LIMIT * 2 + 17 },
  (_, index) => (index * 131 + (index >>> 7)) & 255,
);
let signed: string;
let denied: string;

beforeAll(async () => {
  const keys = await generateKeyPair('RS256');
  const publicKey = await exportJWK(keys.publicKey);
  publicKey.kid = 'http-workers-fixture';
  env.PROBE_ACCESS_JWKS = JSON.stringify({ keys: [publicKey] });
  signed = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: publicKey.kid })
    .setSubject('http-owner')
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('state-fixture')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  denied = await new SignJWT({ email: 'another@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: publicKey.kid })
    .setSubject('denied-owner')
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('state-fixture')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
  await registerBuild(buildId, 'verified', '["fixture.example.org"]');
  network.enable();
}, 30_000);

beforeEach(() => {
  network.use(http.all('*', () => HttpResponse.error()));
});
afterEach(() => network.resetHandlers());
afterAll(() => network.disable());

async function registerBuild(id: string, status: string, policy: string) {
  await env.DB.prepare(
    'INSERT INTO extension_builds (build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (?,?,?,?,?,?)',
  )
    .bind(id, id, 'a'.repeat(64), status, 0, policy)
    .run();
}

function metadata(
  pathname = '/binary',
  overrides: Partial<HttpRequestMeta> = {},
): HttpRequestMeta {
  return {
    requestId: crypto.randomUUID(),
    runtimeGeneration: 'http-fixture-generation',
    url: upstreamOrigin + pathname,
    method: 'GET',
    headers: [],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 5000,
    ...overrides,
  };
}

function framedBody(
  meta: HttpRequestMeta,
  bytes?: Uint8Array,
  end = true,
): ReadableStream<Uint8Array> {
  const prefix = [encodePreamble(), encodeMetaFrame(meta)];
  let offset = 0;
  return new ReadableStream(
    {
      pull(controller) {
        const header = prefix.shift();
        if (header) {
          controller.enqueue(header);
        } else if (bytes && offset < bytes.length) {
          const part = bytes.subarray(offset, offset + HTTP_FRAME_LIMIT);
          offset += part.length;
          controller.enqueue(encodeDataFrame(part));
        } else {
          if (end) controller.enqueue(encodeEndFrame(bytes?.length ?? 0));
          controller.close();
        }
      },
    },
    { highWaterMark: 0 },
  );
}

function dispatch(
  meta = metadata(),
  options: {
    bytes?: Uint8Array;
    end?: boolean;
    headers?: Record<string, string>;
  } = {},
) {
  return exports.default.fetch(appOrigin + '/api/bridge/http', {
    method: 'POST',
    headers: {
      'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
      Accept: HTTP_BRIDGE_MEDIA_TYPE,
      'X-Runtime-Build': buildId,
      'X-App-Request': '1',
      Origin: appOrigin,
      'Cf-Access-Jwt-Assertion': signed,
      ...options.headers,
    },
    body: framedBody(meta, options.bytes, options.end ?? true),
  });
}

async function framed(response: Response) {
  if (response.status !== 200) {
    throw new Error(
      'HTTP bridge failed: ' + response.status + ' ' + (await response.text()),
    );
  }
  expect(response.headers.get('content-type')).toBe(HTTP_BRIDGE_MEDIA_TYPE);
  expect(response.headers.get('set-cookie')).toBeNull();
  expect(response.body).not.toBeNull();
  const reader = new HttpFrameReader(response.body!, HTTP_RESPONSE_BODY_LIMIT);
  return {
    reader,
    meta: httpResponseMetaSchema.parse(await reader.meta()),
  };
}

async function consume(reader: HttpFrameReader): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  let length = 0;
  for (;;) {
    const part = await reader.read(HTTP_FRAME_LIMIT);
    if (part === null) break;
    expect(part.length).toBeLessThanOrEqual(HTTP_FRAME_LIMIT);
    length += part.length;
    chunks.push(part);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const part of chunks) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}

test('verified JWT and D1 policy deliver bounded binary frames with control identity', async () => {
  network.use(
    http.get(
      upstreamOrigin + '/binary',
      () =>
        new HttpResponse(payload, {
          headers: [
            ['Content-Type', 'application/octet-stream'],
            ['Content-Length', String(payload.length)],
            ['Set-Cookie', 'one=1; Path=/; HttpOnly'],
            [
              'Set-Cookie',
              'two=2; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
            ],
          ],
        }),
    ),
  );
  const descriptor = metadata();
  const { reader, meta } = await framed(await dispatch(descriptor));
  expect(meta.requestId).toBe(descriptor.requestId);
  expect(meta.runtimeGeneration).toBe(descriptor.runtimeGeneration);
  expect(meta.upstreamStatus).toBe(200);
  expect(meta.bodyLength).toBe(payload.length);
  expect(
    meta.headers
      .filter(([name]) => name === 'set-cookie')
      .map(([, value]) => value),
  ).toEqual([
    'one=1; Path=/; HttpOnly',
    'two=2; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
  ]);
  expect(await consume(reader)).toEqual(payload);
});

test.each(['gzip', 'br'])(
  'preserves fetch-decoded %s bytes and removes representation encoding metadata',
  async (encoding) => {
    // MSW decompresses gzip through the Workers DecompressionStream API.
    // Its browser adapter does not decompress Brotli: that case only verifies
    // the already-decoded fetch boundary and metadata normalization.
    const bytes =
      encoding === 'gzip' ? new Uint8Array(gzipSync(payload)) : payload;
    network.use(
      http.get(
        upstreamOrigin + '/encoded',
        () =>
          new HttpResponse(bytes, {
            headers: {
              'Content-Encoding': encoding,
              'Content-Length': String(encoding === 'gzip' ? bytes.length : 19),
              'Content-Type': 'application/octet-stream',
            },
          }),
      ),
    );
    const { reader, meta } = await framed(await dispatch(metadata('/encoded')));
    expect(meta.decoded).toBe(true);
    expect(meta.bodyLength).toBeNull();
    expect(
      meta.headers.some(([name]) =>
        ['content-encoding', 'content-length'].includes(name),
      ),
    ).toBe(false);
    expect(await consume(reader)).toEqual(payload);
  },
);

test('HEAD retains representation metadata without a DATA body', async () => {
  network.use(
    http.head(
      upstreamOrigin + '/head',
      () =>
        new HttpResponse(null, {
          headers: { 'Content-Encoding': 'gzip', 'Content-Length': '19' },
        }),
    ),
  );
  const { reader, meta } = await framed(
    await dispatch(metadata('/head', { method: 'HEAD' })),
  );
  expect(meta.hasBody).toBe(false);
  expect(meta.decoded).toBe(false);
  expect(meta.bodyLength).toBe(0);
  expect(meta.headers).toContainEqual(['content-encoding', 'gzip']);
  expect(meta.headers).toContainEqual(['content-length', '19']);
  expect(await reader.read(1)).toBeNull();
});

test.each([204, 205, 304])(
  'upstream status %i has no DATA body and retains representation validators',
  async (status) => {
    network.use(
      http.get(
        upstreamOrigin + '/empty',
        () =>
          new HttpResponse(null, {
            status,
            headers: { ETag: '"fixture"' },
          }),
      ),
    );
    const { reader, meta } = await framed(await dispatch(metadata('/empty')));
    expect(meta.upstreamStatus).toBe(status);
    expect(meta.hasBody).toBe(false);
    expect(meta.bodyLength).toBe(0);
    expect(meta.headers).toContainEqual(['etag', '"fixture"']);
    expect(await reader.read(1)).toBeNull();
  },
);

test('Range request and exact partial response cross the Worker bridge', async () => {
  const partial = payload.subarray(65533, 65552);
  network.use(
    http.get(upstreamOrigin + '/range', ({ request }) => {
      expect(request.headers.get('Range')).toBe('bytes=65533-65551');
      return new HttpResponse(partial, {
        status: 206,
        headers: {
          'Content-Length': '19',
          'Content-Range': 'bytes 65533-65551/' + payload.length,
          'Accept-Ranges': 'bytes',
        },
      });
    }),
  );
  const { reader, meta } = await framed(
    await dispatch(
      metadata('/range', {
        headers: [['Range', 'bytes=65533-65551']],
      }),
    ),
  );
  expect(meta.upstreamStatus).toBe(206);
  expect(meta.bodyLength).toBe(19);
  expect(meta.headers).toContainEqual([
    'content-range',
    'bytes 65533-65551/' + payload.length,
  ]);
  expect(await consume(reader)).toEqual(partial);
});

test('streaming upload preserves binary/source headers and strips application credentials', async () => {
  const bytes = payload.subarray(0, HTTP_FRAME_LIMIT + 11);
  network.use(
    http.post(upstreamOrigin + '/echo', async ({ request }) => {
      expect(request.headers.get('Authorization')).toBe('Bearer source-token');
      expect(request.headers.get('Cookie')).toBe('one=1; two=2');
      expect(request.headers.get('Cf-Access-Jwt-Assertion')).toBeNull();
      expect(request.headers.get('X-App-Request')).toBeNull();
      expect(request.headers.get('X-Runtime-Build')).toBeNull();
      expect(request.headers.get('X-Remove-Me')).toBeNull();
      return new HttpResponse(await request.arrayBuffer());
    }),
  );
  const { reader } = await framed(
    await dispatch(
      metadata('/echo', {
        method: 'POST',
        hasBody: true,
        bodyLength: bytes.length,
        headers: [
          ['Authorization', 'Bearer source-token'],
          ['Cookie', 'one=1'],
          ['Cookie', 'two=2'],
          ['Cf-Access-Jwt-Assertion', 'must-not-leak'],
          ['X-App-Request', 'must-not-leak'],
          ['X-Runtime-Build', 'must-not-leak'],
          ['Connection', 'X-Remove-Me'],
          ['X-Remove-Me', 'hop-by-hop'],
        ],
      }),
      { bytes },
    ),
  );
  expect(await consume(reader)).toEqual(bytes);
});

test.each([false, true])(
  'form fields and binary files survive the bridge (multipart=%s)',
  async (multipart) => {
    const notes = ['空格 + & emoji 🦀', 'second=value'];
    const fileBytes = new Uint8Array(payload.subarray(0, HTTP_FRAME_LIMIT + 7));
    const form = multipart ? new FormData() : new URLSearchParams();
    for (const note of notes) form.append('note', note);
    if (form instanceof FormData) {
      form.append(
        'image',
        new File([fileBytes], 'fixture.bin', {
          type: 'application/octet-stream',
        }),
      );
    }
    const encoded = new Request(upstreamOrigin + '/form', {
      method: 'POST',
      body: form,
    });
    const bytes = new Uint8Array(await encoded.arrayBuffer());
    network.use(
      http.post(upstreamOrigin + '/form', async ({ request }) => {
        const received = await request.formData();
        expect(received.getAll('note')).toEqual(notes);
        const file = received.get('image');
        if (multipart) {
          expect(file).toBeInstanceOf(File);
          if (!(file instanceof File)) throw new Error('Missing file');
          expect(file.name).toBe('fixture.bin');
          expect(new Uint8Array(await file.arrayBuffer())).toEqual(fileBytes);
        } else {
          expect(file).toBeNull();
        }
        return HttpResponse.json({ accepted: true });
      }),
    );
    const { reader } = await framed(
      await dispatch(
        metadata('/form', {
          method: 'POST',
          hasBody: true,
          bodyLength: bytes.length,
          headers: [['Content-Type', encoded.headers.get('content-type')!]],
        }),
        { bytes },
      ),
    );
    expect(JSON.parse(new TextDecoder().decode(await consume(reader)))).toEqual(
      { accepted: true },
    );
  },
);

test('redirect targets are returned for Source handling and never followed by the bridge', async () => {
  let requests = 0;
  network.use(
    http.get(upstreamOrigin + '/redirect', () => {
      ++requests;
      return new HttpResponse('redirect', {
        status: 302,
        headers: { Location: 'http://127.0.0.1/private' },
      });
    }),
    http.get('http://127.0.0.1/private', () => {
      throw new Error('Bridge followed a private redirect');
    }),
  );
  const { reader, meta } = await framed(await dispatch(metadata('/redirect')));
  expect(meta.upstreamStatus).toBe(302);
  expect(meta.headers).toContainEqual(['location', 'http://127.0.0.1/private']);
  expect(new TextDecoder().decode(await consume(reader))).toBe('redirect');
  expect(requests).toBe(1);
});

test('auth, origin, protocol and D1 build policy failures never fetch upstream', async () => {
  let requests = 0;
  network.use(
    http.all('*', () => {
      ++requests;
      return new HttpResponse('unexpected');
    }),
  );
  const cases: Array<{
    headers: Record<string, string>;
    status: number;
    error: string;
  }> = [
    {
      headers: { 'Cf-Access-Jwt-Assertion': denied },
      status: 403,
      error: 'access_denied',
    },
    {
      headers: { 'Cf-Access-Jwt-Assertion': '' },
      status: 401,
      error: 'access_required',
    },
    {
      headers: { 'Cf-Access-Jwt-Assertion': signed + 'invalid' },
      status: 401,
      error: 'access_required',
    },
    {
      headers: { Origin: 'https://evil.example.org' },
      status: 403,
      error: 'invalid_origin',
    },
    {
      headers: { 'X-Runtime-Build': 'missing' },
      status: 404,
      error: 'build_not_found',
    },
    {
      headers: { 'Content-Type': 'application/json' },
      status: 415,
      error: 'unsupported_bridge_protocol',
    },
    {
      headers: { Accept: 'application/json' },
      status: 406,
      error: 'unsupported_bridge_response_protocol',
    },
  ];
  for (const item of cases) {
    const response = await dispatch(metadata(), { headers: item.headers });
    expect(response.status).toBe(item.status);
    expect(await response.json()).toEqual({ error: item.error });
  }
  for (const target of [
    'http://127.0.0.1/private',
    'https://other.example.org/denied',
    'https://fixture.example.org:8443/private',
    'https://user:pass@fixture.example.org/private',
  ]) {
    const response = await dispatch(metadata('/binary', { url: target }));
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: 'target_not_allowed' });
  }
  const unverifiedId = crypto.randomUUID();
  await registerBuild(
    unverifiedId,
    'compiled_unverified',
    '["fixture.example.org"]',
  );
  const unverified = await dispatch(metadata(), {
    headers: { 'X-Runtime-Build': unverifiedId },
  });
  expect(unverified.status).toBe(404);
  expect(await unverified.json()).toEqual({ error: 'build_not_found' });
  const brokenId = crypto.randomUUID();
  await registerBuild(brokenId, 'verified', '{"wrong":"shape"}');
  const broken = await dispatch(metadata(), {
    headers: { 'X-Runtime-Build': brokenId },
  });
  expect(broken.status).toBe(503);
  expect(await broken.json()).toEqual({ error: 'invalid_network_policy' });
  expect(requests).toBe(0);
});

test('declared request/response limits reject without accepting oversized content', async () => {
  let requests = 0;
  network.use(
    http.get(upstreamOrigin + '/oversized', () => {
      ++requests;
      return new HttpResponse('small fixture', {
        headers: { 'Content-Length': String(HTTP_RESPONSE_BODY_LIMIT + 1) },
      });
    }),
  );
  const invalidRequest = await dispatch(
    metadata('/oversized', {
      method: 'POST',
      hasBody: true,
      bodyLength: HTTP_REQUEST_BODY_LIMIT + 1,
    }),
  );
  expect(invalidRequest.status).toBe(400);
  expect(await invalidRequest.json()).toEqual({
    error: 'invalid_bridge_request',
  });
  expect(requests).toBe(0);
  const invalidResponse = await dispatch(metadata('/oversized'));
  expect(invalidResponse.status).toBe(413);
  expect(await invalidResponse.json()).toEqual({
    error: 'body_limit_exceeded',
  });
  expect(requests).toBe(1);
});

test('a truncated declared response emits ERROR rather than a successful END', async () => {
  network.use(
    http.get(
      upstreamOrigin + '/truncate',
      () =>
        new HttpResponse('short', {
          headers: { 'Content-Length': '20' },
        }),
    ),
  );
  const { reader } = await framed(await dispatch(metadata('/truncate')));
  await expect(consume(reader)).rejects.toMatchObject({
    code: 'upstream_body_error',
    remote: true,
  });
});

test.each([200, 302, 403])(
  'an early %i response cannot conceal a missing upload END',
  async (status) => {
    network.use(
      http.post(
        upstreamOrigin + '/early',
        () => new HttpResponse('early', { status }),
      ),
    );
    const response = await dispatch(
      metadata('/early', {
        method: 'POST',
        hasBody: true,
        bodyLength: 2,
      }),
      { bytes: new Uint8Array([0, 255]), end: false },
    );
    if (response.status === 400) {
      expect(await response.json()).toEqual({
        error: 'invalid_bridge_request',
      });
    } else {
      const { reader } = await framed(response);
      await expect(consume(reader)).rejects.toMatchObject({
        code: 'invalid_bridge_request',
        remote: true,
      });
    }
  },
);

test('an upstream network failure becomes a bounded JSON failure', async () => {
  network.use(
    http.get(upstreamOrigin + '/network-error', () => HttpResponse.error()),
  );
  const response = await dispatch(metadata('/network-error'));
  expect(response.status).toBe(502);
  expect(await response.json()).toEqual({ error: 'upstream_network_error' });
});

test('the request deadline aborts a mocked pending upstream request', async () => {
  let aborted = false;
  network.use(
    http.get(upstreamOrigin + '/delayed', async ({ request }) => {
      request.signal.addEventListener(
        'abort',
        () => {
          aborted = true;
        },
        { once: true },
      );
      await new Promise((resolve) => setTimeout(resolve, 100));
      return new HttpResponse('too late');
    }),
  );
  const response = await dispatch(metadata('/delayed', { timeoutMs: 30 }));
  expect(response.status).toBe(504);
  expect(await response.json()).toEqual({ error: 'timeout' });
  await expect.poll(() => aborted).toBe(true);
});

test('cancelling the response reader cancels the mocked upstream body', async () => {
  let cancelled = false;
  let source: ReadableStreamDefaultController<Uint8Array> | undefined;
  network.use(
    http.get(
      upstreamOrigin + '/stream',
      () =>
        new HttpResponse(
          new ReadableStream<Uint8Array>({
            start(controller) {
              source = controller;
              controller.enqueue(new Uint8Array([1, 2, 3]));
            },
            cancel() {
              cancelled = true;
            },
          }),
        ),
    ),
  );
  try {
    const { reader } = await framed(await dispatch(metadata('/stream')));
    expect(await reader.read(1)).toEqual(new Uint8Array([1]));
    await reader.cancel('test consumer cancellation');
    await expect.poll(() => cancelled).toBe(true);
  } finally {
    if (!cancelled) source?.close();
  }
});
