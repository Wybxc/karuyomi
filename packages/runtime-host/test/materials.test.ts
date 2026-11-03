import { afterEach, describe, expect, it } from 'vitest';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { collectMaterials, digest, prepareMaterials } from '../materials.mjs';
import { createNativeMaterialResolver } from '../src/native-materials.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { isNativeControlPage } from '../src/native-location.js';

const temporary: string[] = [];
afterEach(async () => {
  await Promise.all(
    temporary
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

describe('shared material preparation', () => {
  it('metadata-only catalog agrees with the exact npm WASM and keeps published Web compatibility bytes', async () => {
    const metadata = await collectMaterials({ includeWasmBytes: false });
    const full = await collectMaterials();
    expect(full.catalog).toEqual(metadata.catalog);
    expect(full.data.size).toBe(8);
    expect(metadata.data.size).toBe(7);
    expect(full.catalog.resources).toEqual([
      expect.objectContaining({
        logicalName: 'zstd.wasm',
        size: 251806,
        sha256:
          '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
      }),
    ]);
    expect(full.catalog.compatibility.map((item) => item.sha256)).toEqual([
      'd48b31850eca8b4ac588e7385dba9ac54dd0e189f36627b650fec336ea02c06e',
      '5fceb245573118980385044c4025100da5f4fdf9466d6f62dff52685e9672518',
    ]);
    for (const [sha256, { bytes }] of full.data)
      expect(digest(bytes)).toBe(sha256);
  });

  it('writes only bounded hash-addressed public material files and a matching catalog', async () => {
    const directory = await mkdtemp(path.join(tmpdir(), 'karuyomi-materials-'));
    temporary.push(directory);
    const { catalog, data } = await prepareMaterials(directory);
    expect((await readdir(directory)).sort()).toEqual([
      'materials',
      'materials.json',
    ]);
    expect(
      JSON.parse(
        await readFile(path.join(directory, 'materials.json'), 'utf8'),
      ),
    ).toEqual(catalog);
    expect((await readdir(path.join(directory, 'materials'))).sort()).toEqual(
      [...data.keys()].sort(),
    );
    for (const artifact of [
      ...catalog.hostScripts,
      ...catalog.resources,
      ...catalog.compatibility,
    ]) {
      const bytes = await readFile(
        path.join(directory, 'materials', artifact.sha256),
      );
      expect(bytes.length).toBe(artifact.size);
      expect(digest(bytes)).toBe(artifact.sha256);
      expect(artifact.path).toBe('/runtime/materials/' + artifact.sha256);
    }
  });
});

describe('native material resolver', () => {
  it('returns the same bytes with independent ownership and rejects legacy storage builds without HTTP', async () => {
    const { catalog, data } = await collectMaterials();
    const legacy = catalog.compatibility.map((artifact) => artifact.sha256);
    const encoded = Object.fromEntries(
      [...data].map(([sha256, value]) => [
        sha256,
        {
          base64: value.bytes.toString('base64'),
          contentType: value.contentType,
        },
      ]),
    );
    const resolver = createNativeMaterialResolver(encoded, legacy);
    for (const artifact of [...catalog.hostScripts, ...catalog.resources]) {
      const material = resolver(artifact.sha256)!;
      expect(digest(material.bytes)).toBe(artifact.sha256);
      material.bytes[0] ^= 1;
      expect(digest(resolver(artifact.sha256)!.bytes)).toBe(artifact.sha256);
    }
    let requests = 0;
    const loader = new VerifiedLoader(
      'https://read.example.com',
      async () => {
        ++requests;
        throw Error('Native shared materials must not use the network');
      },
      resolver,
    );
    for (const artifact of catalog.compatibility) {
      await expect(
        loader.sharedArtifact(artifact, new AbortController().signal, true),
      ).rejects.toMatchObject({
        code: 'unsupported_capability',
        message: expect.stringContaining('update the extension build'),
      });
    }
    await expect(
      loader.sharedArtifact(
        {
          path: '/runtime/materials/' + '0'.repeat(64),
          sha256: '0'.repeat(64),
          size: 1,
          contentType: 'application/wasm',
        },
        new AbortController().signal,
      ),
    ).rejects.toMatchObject({ code: 'unsupported_capability' });
    expect(requests).toBe(0);
  });
});

describe('native control page location', () => {
  it('accepts HTTPS host.html and its Cloudflare canonical path, rejecting other pages', () => {
    expect(
      isNativeControlPage(
        new URL('https://read.example.com/runtime/host.html'),
      ),
    ).toBe(true);
    expect(
      isNativeControlPage(new URL('https://read.example.com/runtime/host')),
    ).toBe(true);
    for (const url of [
      'http://read.example.com/runtime/host',
      'https://read.example.com/',
      'https://read.example.com/runtime/worker.js',
      'https://read.example.com/runtime/host/',
      'https://read.example.com/api/auth/login',
    ])
      expect(isNativeControlPage(new URL(url))).toBe(false);
  });
});
