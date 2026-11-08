import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HttpFrameReader,
  encodeEndFrame,
  encodeMetaFrame,
  encodePreamble,
  httpResponseMetaSchema,
  type HttpRequestMeta,
} from '@karuyomi/contracts';
import { setupNetwork } from '@msw/cloudflare';
import { createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { http, HttpResponse } from 'msw';
import { afterAll, beforeAll, expect, test } from 'vitest';
import {
  bridgeErrorAttempts,
  prepareBridgeError,
} from './acceptance-bridge-error.ts';
import acceptance from './acceptance-entry.ts';

const origin = 'http://127.0.0.1:44123';
const target = 'https://fixture.example.org/chapter/';
const network = setupNetwork();
let credentials: {
  PROBE_ACCESS_JWKS: string;
  ACCEPTANCE_PRIVATE_KEY: string;
};

beforeAll(async () => {
  const keys = await generateKeyPair('RS256', { extractable: true });
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'acceptance';
  credentials = {
    PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
    ACCEPTANCE_PRIVATE_KEY: await exportPKCS8(keys.privateKey),
  };
  network.enable();
  network.use(http.all('*', () => HttpResponse.error()));
}, 30_000);
afterAll(() => network.disable());

function send(
  requestId: string,
  options: { enabled?: boolean; url?: string; origin?: string } = {},
) {
  const metadata: HttpRequestMeta = {
    requestId,
    runtimeGeneration: 'bridge-error-fixture',
    url: options.url ?? target,
    method: 'GET',
    headers: [],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 5000,
  };
  return acceptance.fetch(
    new Request(origin + '/api/bridge/http', {
      method: 'POST',
      headers: {
        Origin: options.origin ?? origin,
        'X-App-Request': '1',
        'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
        Accept: HTTP_BRIDGE_MEDIA_TYPE,
      },
      body: new Blob([
        encodePreamble(),
        encodeMetaFrame(metadata),
        encodeEndFrame(0),
      ]),
    }),
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: 'acceptance-owner',
      ...(options.enabled ? { ACCEPTANCE_BRIDGE_ERROR_URL: target } : {}),
    },
    createExecutionContext(),
  );
}

async function expectForwarded(
  response: Response,
  requestId: string,
  upstreamStatus: number,
) {
  expect(response.status).toBe(200);
  expect(response.body).not.toBeNull();
  const reader = new HttpFrameReader(response.body!, 64);
  expect(httpResponseMetaSchema.parse(await reader.meta())).toMatchObject({
    requestId,
    runtimeGeneration: 'bridge-error-fixture',
    upstreamStatus,
  });
  const chunks: string[] = [];
  const decoder = new TextDecoder();
  for (
    let chunk = await reader.read(HTTP_FRAME_LIMIT);
    chunk !== null;
    chunk = await reader.read(HTTP_FRAME_LIMIT)
  ) {
    chunks.push(decoder.decode(chunk, { stream: true }));
  }
  chunks.push(decoder.decode());
  expect(chunks.join('')).toBe('chapter document');
}

test('only the first successful opted-in exact chapter request is interrupted', async () => {
  let upstreamStatus = 200;
  let upstreamCalls = 0;
  network.use(
    http.get('https://fixture.example.org/*', () => {
      upstreamCalls++;
      return HttpResponse.text('chapter document', { status: upstreamStatus });
    }),
  );

  await expectForwarded(await send('default'), 'default', 200);
  await prepareBridgeError(env.DB);
  const enabled = true;
  await expectForwarded(
    await send('different-target', { enabled, url: target + '?variant=1' }),
    'different-target',
    200,
  );
  const rejected = await send('wrong-origin', {
    enabled,
    origin: 'https://another.example.org',
  });
  expect(rejected.status).toBe(403);
  expect(await rejected.json()).toEqual({ error: 'invalid_origin' });
  expect(await bridgeErrorAttempts(env.DB)).toEqual([]);

  upstreamStatus = 503;
  await expectForwarded(
    await send('upstream-503', { enabled }),
    'upstream-503',
    503,
  );
  upstreamStatus = 200;
  const failure = await send('first-success', { enabled });
  expect(failure.status).toBe(502);
  expect(await failure.json()).toEqual({ error: 'upstream_body_error' });
  await expectForwarded(
    await send('explicit-retry', { enabled }),
    'explicit-retry',
    200,
  );
  expect(upstreamCalls).toBe(5);
  expect(await bridgeErrorAttempts(env.DB)).toEqual(
    [
      ['upstream-503', 503, 0],
      ['first-success', 200, 1],
      ['explicit-retry', 200, 0],
    ].map(([request_id, upstream_status, injected], index) => ({
      sequence: index + 1,
      request_id,
      runtime_generation: 'bridge-error-fixture',
      bridge_status: 200,
      upstream_status,
      injected,
    })),
  );
});
