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
    expect(full.data.size).toBe(13);
    expect(metadata.data.size).toBe(12);
    expect(full.catalog.resources).toEqual([
      expect.objectContaining({
        logicalName: 'zstd.wasm',
        size: 251806,
        sha256:
          '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
      }),
    ]);
    expect(
      full.catalog.compatibility.map((item) => [
        item.logicalName,
        item.sha256,
        item.nativeSupported,
      ]),
    ).toEqual([
      [
        'release9-v1/cache-bridge.js',
        'd48b31850eca8b4ac588e7385dba9ac54dd0e189f36627b650fec336ea02c06e',
        false,
      ],
      [
        'release9-v1/file-bridge.js',
        '5fceb245573118980385044c4025100da5f4fdf9466d6f62dff52685e9672518',
        false,
      ],
      [
        'source-aot-v1/crypto-bridge.js',
        'c5c0a7f0b88ddce12e452b3e9a90db0c2640e1c6cf94b9c752229c6da575c39a',
        true,
      ],
      [
        'source-aot-v1/zstd-bridge.js',
        '9feca0b39bba3f31b52574b253a19883a49a9ad26d18f336c89101ad666828eb',
        true,
      ],
      [
        'source-aot-v1/graphics-bridge.js',
        'a892cdb8dff1380f5f3bfac63fa2b9a9d1c9030b27d56945084401a2d190fb5e',
        true,
      ],
      [
        'source-aot-v1/cache-bridge.js',
        'dad4c7d8f1cf4fac99a063bc5c231793a3d7a2bfe5dbe4e5f98b446f38199088',
        true,
      ],
      [
        'source-aot-v1/file-bridge.js',
        '525b59e229290b283bf1f243f5565bf1b9ecdc6b82bb4c35babdc44dfd96847d',
        true,
      ],
    ]);
    for (const [sha256, { bytes }] of full.data)
      expect(digest(bytes)).toBe(sha256);
  });

  it('loads all historical materials from verified Web static bytes, including old private manifest paths', async () => {
    const { catalog, data } = await collectMaterials();
    const requests: string[] = [];
    const loader = new VerifiedLoader(
      'https://read.example.com',
      async (input, options) => {
        const url = new URL(String(input));
        requests.push(url.pathname);
        expect(options).toMatchObject({
          credentials: 'omit',
          cache: 'force-cache',
          redirect: 'manual',
        });
        const material = data.get(url.pathname.split('/').pop()!)!;
        return new Response(new Uint8Array(material.bytes), {
          headers: { 'content-type': material.contentType },
        });
      },
    );
    for (const artifact of catalog.compatibility) {
      for (const prefix of [
        '/runtime/materials/',
        '/api/extensions/artifacts/',
      ]) {
        const bytes = await loader.sharedArtifact(
          { ...artifact, path: prefix + artifact.sha256 },
          new AbortController().signal,
          true,
        );
        expect(digest(bytes)).toBe(artifact.sha256);
      }
    }
    expect(requests).toHaveLength(14);
    expect(requests.every((url) => url.startsWith('/runtime/materials/'))).toBe(
      true,
    );
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
    const legacy = catalog.compatibility
      .filter((artifact) => !artifact.nativeSupported)
      .map((artifact) => artifact.sha256);
    expect(legacy).toHaveLength(2);
    const supported = [
      ...catalog.hostScripts,
      ...catalog.resources,
      ...catalog.compatibility.filter((artifact) => artifact.nativeSupported),
    ];
    expect(supported).toHaveLength(11);
    const encoded = Object.fromEntries(
      [...data]
        .filter(([sha256]) => !legacy.includes(sha256))
        .map(([sha256, value]) => [
          sha256,
          {
            base64: value.bytes.toString('base64'),
            contentType: value.contentType,
          },
        ]),
    );
    const resolver = createNativeMaterialResolver(encoded, legacy);
    for (const artifact of supported) {
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
    for (const artifact of supported) {
      const bytes = await loader.sharedArtifact(
        artifact,
        new AbortController().signal,
        artifact.contentType === 'application/javascript',
      );
      expect(digest(bytes)).toBe(artifact.sha256);
    }
    for (const artifact of catalog.compatibility.filter(
      (item) => !item.nativeSupported,
    )) {
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
