import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { unzipSync, zipSync } from 'fflate';
import {
  compileBridgeBootstrap,
  generateRegistries,
  prepareLibraries,
} from './build.ts';

test('bridge bootstrap javac resolves its binary HTTP source before compatibility compilation', async () => {
  const work = mkdtempSync(
    path.join(os.tmpdir(), 'karuyomi-bridge-bootstrap-'),
  );
  try {
    const source = path.join(work, 'java/src/main/java/prototype'),
      dependencies = path.join(work, 'dependencies');
    mkdirSync(source, { recursive: true });
    mkdirSync(dependencies);
    // This explicit dependency reproduces the source-list failure without the
    // runtime seed, third-party libraries or the full TeaVM compilation.
    for (const [name, declaration] of Object.entries({
      Bridge: 'static int maximum() { return HttpBodySource.MAX_CHUNK; }',
      Callbacks: 'static int maximum() { return Bridge.maximum(); }',
      JsonValues: '',
      HttpBodySource: 'static final int MAX_CHUNK = 64 * 1024;',
    })) {
      writeFileSync(
        path.join(source, name + '.java'),
        `package prototype; public final class ${name} { ${declaration} }`,
      );
    }
    const classes = await compileBridgeBootstrap(work, dependencies);
    for (const name of ['Bridge', 'Callbacks', 'JsonValues', 'HttpBodySource'])
      assert.ok(existsSync(path.join(classes, 'prototype', name + '.class')));
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});

test('registries bind exact injection references and conditional extension resources', () => {
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-aot-'));
  try {
    const runtime = path.join(work, 'public/runtime'),
      source = path.join(work, 'java/src/main/java');
    mkdirSync(runtime, { recursive: true });
    mkdirSync(path.join(source, 'prototype'), { recursive: true });
    writeFileSync(
      path.join(runtime, 'host.jar'),
      zipSync({
        'prototype/Reference.class': Buffer.from(
          'Luy/kohesive/injekt/api/FullTypeReference<Lhost/Service$Nested;>;',
        ),
      }),
    );
    writeFileSync(
      path.join(runtime, 'icu4j-79.1.jar'),
      zipSync({
        'com/ibm/icu/data/example.res': Buffer.from('resource'),
        'com/ibm/icu/Excluded.class': Buffer.from('class'),
      }),
    );
    const original = path.join(work, 'extension.jar');
    writeFileSync(
      original,
      zipSync({
        'assets/data.json': Buffer.from('{}'),
        'example/Source.class': Buffer.from('no ICU here'),
      }),
    );
    const originalHash = createHash('sha256')
      .update(readFileSync(original))
      .digest('hex');
    generateRegistries(work, source, original);
    assert.match(
      readFileSync(path.join(source, 'prototype/TypeMap.java'), 'utf8'),
      /case "prototype.Reference":return host.Service.Nested.class;/,
    );
    let resources = readFileSync(
      path.join(source, 'prototype/ResourceConfig.java'),
      'utf8',
    );
    assert.match(resources, /assets\/data.json/);
    assert.doesNotMatch(resources, /example\.res/);
    assert.equal(
      createHash('sha256').update(readFileSync(original)).digest('hex'),
      originalHash,
    );
    writeFileSync(
      original,
      zipSync({
        'example/Source.class': Buffer.from('android/icu/text/Collator'),
      }),
    );
    generateRegistries(work, source, original);
    resources = readFileSync(
      path.join(source, 'prototype/ResourceConfig.java'),
      'utf8',
    );
    assert.match(resources, /com\/ibm\/icu\/data\/example\.res/);
    assert.doesNotMatch(resources, /Excluded\.class/);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});

test('dependency adaptation removes owned classes and inners without changing original JARs', () => {
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-aot-'));
  try {
    const runtime = path.join(work, 'public/runtime'),
      source = path.join(work, 'java/src/main/java');
    mkdirSync(runtime, { recursive: true });
    mkdirSync(path.join(source, 'example'), { recursive: true });
    writeFileSync(
      path.join(source, 'example/Owned.java'),
      'package example; class Owned {}',
    );
    const dependency = path.join(runtime, 'host.jar');
    writeFileSync(
      dependency,
      zipSync({
        'example/Owned.class': Buffer.from('owned'),
        'example/Owned$Inner.class': Buffer.from('inner'),
        'example/OwnedOther.class': Buffer.from('retain'),
        'resource.bin': Buffer.from([0, 255]),
      }),
    );
    const originalHash = createHash('sha256')
      .update(readFileSync(dependency))
      .digest('hex');
    prepareLibraries(work, source);
    assert.deepEqual(
      Object.keys(
        unzipSync(readFileSync(path.join(work, 'java/libs/host.jar'))),
      ).sort(),
      ['example/OwnedOther.class', 'resource.bin'],
    );
    assert.equal(
      createHash('sha256').update(readFileSync(dependency)).digest('hex'),
      originalHash,
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
