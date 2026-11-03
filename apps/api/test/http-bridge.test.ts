import { expect, test } from 'vitest';
import { allowedTarget } from '../src/http-bridge.js';

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

test('malformed URLs use the same fail-closed target classification', () => {
  expect(() => allowedTarget('not a URL', ['example.org'])).toThrow(
    'target_not_allowed',
  );
});
