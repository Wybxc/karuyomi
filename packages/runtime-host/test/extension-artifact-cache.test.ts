import 'fake-indexeddb/auto';
import { test } from 'vitest';
import assert from 'node:assert/strict';
import { ExtensionArtifactCache } from '../src/extension-artifact-cache.js';

const artifact = (key: string, size: number) => ({
  sha256: key.repeat(64),
  size,
  contentType: 'text/javascript',
  path: '/extensions/artifacts/' + key.repeat(64) + '.gz',
  encoding: 'gzip',
  encodedSha256: key.repeat(64),
  encodedSize: 1,
});

test('a prepared artifact survives another cache instance and returns independent bytes', async () => {
  const name = crypto.randomUUID();
  const first = new ExtensionArtifactCache(name);
  const next = new ExtensionArtifactCache(name);
  try {
    const bytes = new Uint8Array([1, 2, 3]);
    const pending = first.storeVerified(artifact('a', 3), bytes);
    bytes[0] = 99;
    await pending;
    await first.close();
    const result = await next.read(artifact('a', 3));
    assert.deepEqual(result, new Uint8Array([1, 2, 3]));
    assert(result);
    result[0] = 88;
    assert.deepEqual(
      await next.read(artifact('a', 3)),
      new Uint8Array([1, 2, 3]),
    );
    assert.deepEqual(await next.entries(), [
      { sha256: 'a'.repeat(64), byteLength: 3, contentType: 'text/javascript' },
    ]);
  } finally {
    await first.close();
    await next.close();
  }
});

test('concurrent preparation obeys a single transaction budget and does not leave partial entries', async () => {
  const name = crypto.randomUUID();
  const first = new ExtensionArtifactCache(name, 3, 2);
  const second = new ExtensionArtifactCache(name, 3, 2);
  try {
    const result = await Promise.allSettled([
      first.storeVerified(artifact('a', 2), new Uint8Array([1, 2])),
      second.storeVerified(artifact('b', 2), new Uint8Array([3, 4])),
    ]);
    assert.equal(
      result.filter((value) => value.status === 'fulfilled').length,
      1,
    );
    const rejected = result.find((value) => value.status === 'rejected');
    assert(rejected?.status === 'rejected');
    assert.equal(rejected.reason.code, 'limit_exceeded');
    const entries = await first.entries();
    assert.equal(entries.length, 1);
    const selected = entries[0];
    assert(selected);
    await first.remove(selected.sha256);
    assert.deepEqual(await second.entries(), []);
    assert.equal(await second.read(artifact('a', 2)), undefined);
    assert.equal(await second.read(artifact('b', 2)), undefined);
  } finally {
    await first.close();
    await second.close();
  }
});

test('exact size, artifact count and repeated preparation are independently bounded', async () => {
  const cache = new ExtensionArtifactCache(crypto.randomUUID(), 2, 1);
  try {
    await assert.rejects(
      cache.storeVerified(artifact('a', 2), new Uint8Array([1])),
      { code: 'integrity_error' },
    );
    await cache.storeVerified(artifact('a', 2), new Uint8Array([1, 2]));
    await cache.storeVerified(artifact('a', 2), new Uint8Array([1, 2]));
    await assert.rejects(
      cache.storeVerified(artifact('b', 1), new Uint8Array([3])),
      { code: 'limit_exceeded' },
    );
    assert.equal((await cache.entries()).length, 1);
    await assert.rejects(cache.read(artifact('a', 1)), {
      code: 'integrity_error',
    });
    await cache.remove('a'.repeat(64));
    assert.deepEqual(await cache.entries(), []);
  } finally {
    await cache.close();
  }
});

test('running readers retain a shared artifact pin until explicit release', async () => {
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  try {
    const value = artifact('c', 1);
    await cache.storeVerified(value, new Uint8Array([1]));
    const first = await cache.retain(
      value.sha256,
      new AbortController().signal,
    );
    const controller = new AbortController();
    const second = await cache.retain(value.sha256, controller.signal);
    controller.abort();
    await assert.rejects(cache.remove(value.sha256), { code: 'storage_busy' });
    first.release();
    await first.released;
    await assert.rejects(cache.remove(value.sha256), { code: 'storage_busy' });
    second.release();
    await second.released;
    await cache.remove(value.sha256);
    assert.deepEqual(await cache.entries(), []);
  } finally {
    await cache.close();
  }
});

test('an aborted preparation cannot store or read its artifact', async () => {
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  const controller = new AbortController();
  controller.abort(new Error('cancelled preparation'));
  try {
    await assert.rejects(
      cache.storeVerified(
        artifact('d', 1),
        new Uint8Array([1]),
        controller.signal,
      ),
      /cancelled preparation/,
    );
    await assert.rejects(
      cache.read(artifact('d', 1), controller.signal),
      /cancelled preparation/,
    );
    assert.deepEqual(await cache.entries(), []);
  } finally {
    await cache.close();
  }
});
