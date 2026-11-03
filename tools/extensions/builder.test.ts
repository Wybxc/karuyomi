import assert from 'node:assert/strict';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { gunzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { build, parseOfficialMetadata, put } from './builder.ts';

test('invalid descriptor records failure without an executable manifest', async () => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-builder-'));
  try {
    const descriptor = path.join(root, 'descriptor.json'),
      output = path.join(root, 'output');
    writeFileSync(
      descriptor,
      JSON.stringify({ schemaVersion: 99, packageName: 'invalid' }),
    );
    const result = await build({ descriptor, output });
    assert.equal(result.status, 'failed');
    assert.deepEqual(result.artifacts, []);
    assert.equal(result.stage, 'upstream');
    assert.throws(() => readFileSync(path.join(output, 'manifest.json')));
    assert.deepEqual(
      JSON.parse(readFileSync(path.join(output, 'build-result.json'), 'utf8')),
      result,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
test('an existing manifest cannot be replaced by a new build attempt', async () => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-builder-'));
  try {
    writeFileSync(path.join(root, 'manifest.json'), 'original');
    await assert.rejects(
      build({ descriptor: path.join(root, 'unused'), output: root }),
      /immutable manifest/,
    );
    assert.equal(
      readFileSync(path.join(root, 'manifest.json'), 'utf8'),
      'original',
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
test('builder writes exactly the declared deterministic gzip artifact', () => {
  const root = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-builder-'));
  try {
    const source = path.join(root, 'app.js'),
      output = path.join(root, 'output'),
      raw = Buffer.from("console.log('漫画');");
    writeFileSync(source, raw);
    mkdirSync(output);
    const ref = put(output, source, 'text/javascript'),
      name = ref.sha256 + '.gz',
      encoded = readFileSync(path.join(output, 'artifacts', name));
    assert.deepEqual(readdirSync(path.join(output, 'artifacts')), [name]);
    assert.deepEqual(gunzipSync(encoded), raw);
    assert.equal(ref.path, '/extensions/artifacts/' + name);
    assert.equal(ref.encoding, 'gzip');
    assert.equal(
      ref.encodedSha256,
      createHash('sha256').update(encoded).digest('hex'),
    );
    assert.equal(ref.encodedSize, encoded.length);
    assert.equal(ref.size, raw.length);
    assert.equal(ref.sha256, createHash('sha256').update(raw).digest('hex'));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
test('official 64-bit Source identifiers preserve exact JSON integer text', () => {
  const metadata = parseOfficialMetadata(
    '{"packageName":"example","versionName":"1.6.2","versionCode":106002,"sources":[{"id":6866320578550428692,"name":"MangaDraft","lang":"all"},{"id":-9223372036854775808,"name":"Signed","lang":"en"}]}',
  );
  assert.deepEqual(
    metadata.sources.map((source) => source.id),
    ['6866320578550428692', '-9223372036854775808'],
  );
  assert.equal(metadata.versionCode, 106002);
  assert.throws(() =>
    parseOfficialMetadata(
      '{"packageName":"example","versionName":"v","versionCode":9007199254740992,"sources":[]}',
    ),
  );
});
