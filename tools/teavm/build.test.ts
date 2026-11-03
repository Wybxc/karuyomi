import assert from 'node:assert/strict';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { readZip, writeZip } from '../lib/archive.ts';
import { digest } from '../lib/json.ts';
import { generateRegistries, prepareLibraries } from './build.ts';

test('registries bind exact injection references and conditional extension resources', () => {
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-aot-'));
  try {
    const runtime = path.join(work, 'public/runtime'),
      source = path.join(work, 'java/src/main/java');
    mkdirSync(runtime, { recursive: true });
    mkdirSync(path.join(source, 'prototype'), { recursive: true });
    writeZip(path.join(runtime, 'host.jar'), {
      'prototype/Reference.class': Buffer.from(
        'Luy/kohesive/injekt/api/FullTypeReference<Lhost/Service$Nested;>;',
      ),
    });
    writeZip(path.join(runtime, 'icu4j-79.1.jar'), {
      'com/ibm/icu/data/example.res': Buffer.from('resource'),
      'com/ibm/icu/Excluded.class': Buffer.from('class'),
    });
    const original = path.join(work, 'extension.jar');
    writeZip(original, {
      'assets/data.json': Buffer.from('{}'),
      'example/Source.class': Buffer.from('no ICU here'),
    });
    const originalHash = digest(readFileSync(original));
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
    assert.equal(digest(readFileSync(original)), originalHash);
    writeZip(original, {
      'example/Source.class': Buffer.from('android/icu/text/Collator'),
    });
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
    writeZip(dependency, {
      'example/Owned.class': Buffer.from('owned'),
      'example/Owned$Inner.class': Buffer.from('inner'),
      'example/OwnedOther.class': Buffer.from('retain'),
      'resource.bin': Buffer.from([0, 255]),
    });
    const originalHash = digest(readFileSync(dependency));
    prepareLibraries(work, source);
    assert.deepEqual(
      Object.keys(readZip(path.join(work, 'java/libs/host.jar'))).sort(),
      ['example/OwnedOther.class', 'resource.bin'],
    );
    assert.equal(digest(readFileSync(dependency)), originalHash);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
