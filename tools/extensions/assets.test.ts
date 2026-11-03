import assert from 'node:assert/strict';
import { test } from 'node:test';
import { canonical, digest } from '../lib/json.ts';
import { decodeBundle, encodeBundle, originUrl } from './assets.ts';
import { decodeBundleBytes } from './verify-manifest.ts';
test('deterministic binary and Unicode gzip roundtrip', async () => {
  const raw = Buffer.concat([
    Buffer.from(Array.from({ length: 131072 }, (_, i) => i % 256)),
    Buffer.from('漫画 🍵'),
  ]);
  const { encoded, reference } = encodeBundle(raw);
  assert.deepEqual(encodeBundle(raw), { encoded, reference });
  assert.deepEqual(await decodeBundle(reference, encoded), raw);
  assert.equal(
    reference.path,
    '/extensions/artifacts/' + reference.sha256 + '.gz',
  );
  assert.deepEqual(encoded.subarray(4, 8), Buffer.alloc(4));
  assert.equal(encoded[9], 255);
});
test('25 MiB encoded asset limit enforced before publication', () => {
  assert.throws(
    () => encodeBundle(Buffer.from('let x = 1;'), 'text/javascript', 1),
    /25 MiB/,
  );
});
test('decode reuses the shared single-pass dual-domain verifier', async () => {
  assert.equal(decodeBundle, decodeBundleBytes);
  const raw = Buffer.from('data'.repeat(100)),
    { encoded, reference } = encodeBundle(raw);
  assert.deepEqual(await decodeBundle(reference, encoded), raw);
  assert.equal(reference.sha256, digest(raw));
  assert.equal(reference.encodedSha256, digest(encoded));
});
test('encoded corruption and canonical substitution are rejected', async () => {
  const { encoded, reference } = encodeBundle(Buffer.from('original'));
  const corrupted = Buffer.from(encoded);
  corrupted[corrupted.length - 1] = 63;
  await assert.rejects(decodeBundle(reference, corrupted));
  const other = encodeBundle(Buffer.from('modified'));
  await assert.rejects(
    decodeBundle(
      { ...other.reference, sha256: reference.sha256 },
      other.encoded,
    ),
  );
});
test('bounded decode rejects bombs, truncated, concatenated and trailing streams', async () => {
  const { encoded, reference } = encodeBundle(Buffer.from('x'.repeat(100000)));
  await assert.rejects(decodeBundle({ ...reference, size: 100 }, encoded));
  for (const bytes of [
    encoded.subarray(0, encoded.length - 4),
    Buffer.concat([encoded, encoded]),
    Buffer.concat([encoded, Buffer.from('trailing')]),
  ]) {
    await assert.rejects(
      decodeBundle(
        {
          ...reference,
          encodedSize: bytes.length,
          encodedSha256: digest(bytes),
        },
        bytes,
      ),
    );
  }
});
test('static origin contract rejects credentials, traversal and non-HTTPS origins', () => {
  assert.equal(
    originUrl('https://example.com', '/extensions/index.json'),
    'https://example.com/extensions/index.json',
  );
  for (const origin of [
    'http://example.com',
    'https://user@example.com',
    'https://example.com/path',
    'https://example.com/?a=1',
  ])
    assert.throws(() => originUrl(origin, '/extensions/index.json'));
  for (const relative of [
    '/api/a',
    '/extensions/../a',
    '/extensions/index.json?q=1',
  ])
    assert.throws(() => originUrl('https://example.com', relative));
  assert.ok(canonical({ a: 1 }).length > 0);
});
