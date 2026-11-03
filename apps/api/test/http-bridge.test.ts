import { expect, test, vi } from 'vitest';
import {
  allowedTarget,
  forwardLegacy,
  parseLegacyRequest,
} from '../src/http-bridge.js';

test.each([
  'http://localhost/',
  'http://127.0.0.1/',
  'http://2130706433/',
  'http://[::1]/',
  'https://user:pass@example.org/',
  'https://example.org:444/',
  'https://not-allowed.org/',
  'file:///tmp/file',
  'https://app.internal/',
])('bridge rejects private, malformed or undeclared target: %s', (url) => {
  expect(() =>
    allowedTarget(url, [
      'example.org',
      'localhost',
      '127.0.0.1',
      '[::1]',
      'app.internal',
    ]),
  ).toThrow();
});

test('original empty body differs from absent body; bytes are preserved', async () => {
  const fetcher = vi.fn(
    async () => new Response(new Uint8Array([0, 255, 128]), { status: 200 }),
  );
  const body = parseLegacyRequest({
    method: 'POST',
    url: 'https://example.org/x',
    headers: [],
    body: '',
  });
  const result = await forwardLegacy(
    body,
    ['example.org'],
    new AbortController().signal,
    fetcher as typeof fetch,
  );
  expect((fetcher.mock.calls[0]?.[1] as RequestInit).body).toEqual(
    new Uint8Array(),
  );
  expect(result.body).toBe('AP+A');
});

test('request budget checks decoded bytes at the final Base64 quantum', () => {
  const request = { method: 'POST', url: 'https://example.org/', headers: [] };
  const exact = Buffer.alloc(8 * 1024 * 1024).toString('base64');
  const over = Buffer.alloc(8 * 1024 * 1024 + 1).toString('base64');
  expect(exact.length).toBe(over.length);
  expect(parseLegacyRequest({ ...request, body: exact }).body).toBe(exact);
  expect(() => parseLegacyRequest({ ...request, body: over })).toThrow(
    'body_limit_exceeded',
  );
});

test('malformed URLs use the same fail-closed target classification', () => {
  expect(() => allowedTarget('not a URL', ['example.org'])).toThrow(
    'target_not_allowed',
  );
});

test('manual redirects and upstream 403 remain Source responses; cookies do not become app cookies', async () => {
  const headers = new Headers({ location: 'http://127.0.0.1/private' });
  headers.append('set-cookie', 'one=1; Path=/');
  headers.append('set-cookie', 'two=2; Path=/');
  const fetcher = vi.fn(async (_url, options: RequestInit) => {
    expect(options.redirect).toBe('manual');
    expect(options.cache).toBe('no-store');
    const outbound = new Headers(options.headers);
    expect(outbound.get('cf-access-jwt-assertion')).toBeNull();
    expect(outbound.get('x-app-request')).toBeNull();
    expect(outbound.get('authorization')).toBe('Bearer source-token');
    return new Response('denied by source', { status: 403, headers });
  });
  const result = await forwardLegacy(
    {
      method: 'GET',
      url: 'https://example.org/',
      headers: [
        ['Cf-Access-Jwt-Assertion', 'must-not-leak'],
        ['X-App-Request', '1'],
        ['Authorization', 'Bearer source-token'],
      ],
    },
    ['example.org'],
    new AbortController().signal,
    fetcher as typeof fetch,
  );
  expect(result.status).toBe(403);
  expect(result.headers.filter(([key]) => key === 'set-cookie')).toHaveLength(
    2,
  );
  expect(fetcher).toHaveBeenCalledTimes(1);
});

test('HEAD keeps resource length without fabricating a response body', async () => {
  const result = await forwardLegacy(
    { method: 'HEAD', url: 'https://example.org/', headers: [] },
    ['example.org'],
    new AbortController().signal,
    (async () =>
      new Response(null, {
        headers: { 'content-length': '1234' },
      })) as typeof fetch,
  );
  expect(result.body).toBe('');
  expect(result.headers).toContainEqual(['content-length', '1234']);
});

test('oversized upstream is cancelled before it becomes a Base64 string', async () => {
  const cancel = vi.fn();
  const stream = new ReadableStream({
    pull(controller) {
      controller.enqueue(new Uint8Array(1024 * 1024));
    },
    cancel,
  });
  await expect(
    forwardLegacy(
      { method: 'GET', url: 'https://example.org/', headers: [] },
      ['example.org'],
      new AbortController().signal,
      (async () => new Response(stream)) as typeof fetch,
    ),
  ).rejects.toThrow('body_limit_exceeded');
  expect(cancel).toHaveBeenCalledOnce();
});
