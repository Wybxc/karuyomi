import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildManifestSchema } from '@karuyomi/contracts';
import {
  collectMaterials,
  digest,
  nativeMaterialGroups,
  prepareMaterials,
} from '../materials.ts';
import { prepareImageCodecArtifacts } from '../../../tools/images/artifacts.ts';

vi.mock('../../../tools/images/artifacts.ts', () => ({
  prepareImageCodecArtifacts: vi.fn(() => {
    throw new Error('Default builds must not prepare candidate codecs');
  }),
}));

import { imageCodecMaterialFixture } from './image-codec-material-fixture.ts';
import { createNativeMaterialResolver } from '../src/native-materials.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { isNativeControlPage } from '../src/native-location.js';
import { manifest } from './fixtures.js';

const temporary: string[] = [];
afterEach(async () => {
  await Promise.all(
    temporary
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

async function codecFixture() {
  const directory = await mkdtemp(
    path.join(tmpdir(), 'karuyomi-codec-materials-'),
  );
  temporary.push(directory);
  return imageCodecMaterialFixture(directory);
}
async function currentMaterials(includeWasmBytes = true) {
  return collectMaterials({
    includeWasmBytes,
    includeImageCodecs: true,
    imageCodecArtifacts: await codecFixture(),
  });
}

describe('current runtime materials', () => {
  it('default product materials exclude candidate codecs without preparing them', async () => {
    const metadata = await collectMaterials({ includeWasmBytes: false });
    const full = await collectMaterials();
    expect(full.catalog).toEqual(metadata.catalog);
    expect(full.catalog.imageCodecs).toEqual([]);
    expect(full.catalog.sources.imageCodecs).toBeNull();
    expect(full.data.size).toBe(6);
    expect(metadata.data.size).toBe(5);
    expect(prepareImageCodecArtifacts).not.toHaveBeenCalled();
  });

  it('compiles deterministic classic JS from TS with the exact npm WASM identity', async () => {
    const metadata = await currentMaterials(false);
    const full = await currentMaterials();
    expect(full.catalog).toEqual(metadata.catalog);
    expect(full.data.size).toBe(18);
    expect(metadata.data.size).toBe(14);
    expect(full.catalog.imageCodecs.map((item) => item.logicalName)).toEqual([
      'client.js',
      'worker.js',
      'png.mjs',
      'png.wasm',
      'jpeg.mjs',
      'jpeg.wasm',
      'encoder.mjs',
      'encoder.wasm',
      'licenses/libspng-LICENSE.txt',
      'licenses/libjpeg-turbo-LICENSE.md',
      'licenses/libjpeg-turbo-README.ijg',
      'licenses/zlib-README',
    ]);
    expect(full.catalog.sources.imageCodecs).toEqual({
      buildIdentity: '1'.repeat(64),
      abi: 'karuyomi-image-strips-v1',
      encoderAbi: 'karuyomi-png-tiles-v1',
    });
    const worker = full.catalog.imageCodecs.find(
      (item) => item.logicalName === 'worker.js',
    )!;
    expect(full.data.get(worker.sha256)!.bytes.toString('utf8')).not.toMatch(
      /(?:^|;)\s*import(?:\s|\{)/m,
    );
    expect(full.catalog.hostScripts.map((item) => item.logicalName)).toEqual([
      'crypto-bridge.js',
      'zstd-bridge.js',
      'graphics-bridge.js',
      'cache-bridge.js',
      'file-bridge.js',
    ]);
    expect(full.catalog.resources).toEqual([
      expect.objectContaining({
        logicalName: 'zstd.wasm',
        size: 251806,
        sha256:
          '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
      }),
    ]);
    for (const [sha256, { bytes }] of full.data)
      expect(digest(bytes)).toBe(sha256);
    for (const artifact of full.catalog.hostScripts) {
      const text = full.data.get(artifact.sha256)!.bytes.toString('utf8');
      expect(text).not.toContain('import.meta');
      expect(text).not.toMatch(/^import\s/m);
    }
  });

  it('codec build provenance and artifact changes participate in materialVersion without entering Source preload groups', async () => {
    const imageCodecArtifacts = await codecFixture();
    const first = await collectMaterials({
      includeImageCodecs: true,
      imageCodecArtifacts,
    });
    const second = await collectMaterials({
      includeImageCodecs: true,
      imageCodecArtifacts: {
        ...imageCodecArtifacts,
        manifest: { ...imageCodecArtifacts.manifest, identity: '2'.repeat(64) },
      },
    });
    expect(second.catalog.materialVersion).not.toBe(
      first.catalog.materialVersion,
    );
    const changed = Buffer.from('Changed packaging fixture: png.mjs');
    await writeFile(
      path.join(imageCodecArtifacts.directory, 'png.mjs'),
      changed,
    );
    const third = await collectMaterials({
      includeImageCodecs: true,
      imageCodecArtifacts: {
        ...imageCodecArtifacts,
        manifest: {
          ...imageCodecArtifacts.manifest,
          artifacts: {
            ...imageCodecArtifacts.manifest.artifacts,
            'png.mjs': { size: changed.length, sha256: digest(changed) },
          },
        },
      },
    });
    expect(third.catalog.materialVersion).not.toBe(
      first.catalog.materialVersion,
    );
    expect(second.catalog.hostScripts).toEqual(first.catalog.hostScripts);
    expect(second.catalog.resources).toEqual(first.catalog.resources);
    const codecHashes = new Set(
      first.catalog.imageCodecs.map((item) => item.sha256),
    );
    expect(
      [...first.catalog.hostScripts, ...first.catalog.resources].some((item) =>
        codecHashes.has(item.sha256),
      ),
    ).toBe(false);
  });

  it('Native Source groups contain no client codec assets', async () => {
    const { catalog } = await currentMaterials();
    const native = nativeMaterialGroups(catalog);
    expect(native).toEqual({
      sourceWorker: [...catalog.hostScripts, ...catalog.resources],
    });
    const clientHashes = new Set(
      catalog.imageCodecs.map((item) => item.sha256),
    );
    expect(
      native.sourceWorker.some((item) => clientHashes.has(item.sha256)),
    ).toBe(false);
    expect(
      catalog.imageCodecs.some((item) => item.logicalName === 'client.js'),
    ).toBe(true);
  });

  it('fetches current shared materials only through static Web paths', async () => {
    const { catalog, data } = await currentMaterials();
    const build = {
      ...(await manifest()),
      hostScripts: catalog.hostScripts,
      resources: catalog.resources,
    };
    expect(buildManifestSchema.safeParse(build).success).toBe(true);
    for (const role of ['hostScripts', 'resources'] as const) {
      const material = build[role][0]!;
      expect(
        buildManifestSchema.safeParse({
          ...build,
          [role]: [
            {
              ...material,
              path: '/api/extensions/artifacts/' + material.sha256,
            },
          ],
        }).success,
      ).toBe(false);
    }
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
    for (const artifact of [
      ...catalog.hostScripts,
      ...catalog.resources,
      ...catalog.imageCodecs,
    ]) {
      const bytes = await loader.sharedArtifact(
        artifact,
        new AbortController().signal,
        artifact.contentType === 'application/javascript',
      );
      expect(digest(bytes)).toBe(artifact.sha256);
    }
    expect(requests).toHaveLength(18);
    expect(requests.every((url) => url.startsWith('/runtime/materials/'))).toBe(
      true,
    );
    const artifact = catalog.hostScripts[0]!;
    await expect(
      loader.sharedArtifact(
        { ...artifact, path: '/api/extensions/artifacts/' + artifact.sha256 },
        new AbortController().signal,
        true,
      ),
    ).rejects.toMatchObject({ code: 'integrity_error' });
    expect(requests).toHaveLength(18);
  });

  it('writes only current hash-addressed public bytes and a matching catalog', async () => {
    const directory = await mkdtemp(path.join(tmpdir(), 'karuyomi-materials-'));
    temporary.push(directory);
    const { catalog, data } = await prepareMaterials(directory, {
      includeImageCodecs: true,
      imageCodecArtifacts: await codecFixture(),
    });
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
      ...catalog.imageCodecs,
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
  it('returns owned current bytes and never falls back to HTTP for missing materials', async () => {
    const { catalog, data } = await currentMaterials();
    const supported = [
      ...catalog.hostScripts,
      ...catalog.resources,
      ...catalog.imageCodecs,
    ];
    const encoded = Object.fromEntries(
      [...data].map(([sha256, value]) => [
        sha256,
        {
          base64: value.bytes.toString('base64'),
          contentType: value.contentType,
        },
      ]),
    );
    const resolver = createNativeMaterialResolver(encoded);
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
        throw Error('Native materials must be bundled');
      },
      resolver,
    );
    for (const artifact of supported)
      expect(
        digest(
          await loader.sharedArtifact(
            artifact,
            new AbortController().signal,
            artifact.contentType === 'application/javascript',
          ),
        ),
      ).toBe(artifact.sha256);
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
