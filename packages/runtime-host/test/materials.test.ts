import { beforeAll, describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Script } from 'node:vm';
import { z } from 'zod';
import {
  buildManifestSchema,
  runtimeMaterialCatalogSchema,
  type RuntimeMaterialCatalog,
} from '@karuyomi/contracts';
import { createNativeMaterialResolver } from '../src/native-materials.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { isNativeControlPage } from '../src/native-location.js';
import { manifest } from './fixtures.js';

let catalog: RuntimeMaterialCatalog;
const data = new Map<string, Buffer>();
beforeAll(async () => {
  catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      await readFile(
        new URL('../dist/materials.json', import.meta.url),
        'utf8',
      ),
    ),
  );
  for (const artifact of [...catalog.hostScripts, ...catalog.resources])
    data.set(
      artifact.sha256,
      await readFile(
        new URL('../dist/materials/' + artifact.sha256, import.meta.url),
      ),
    );
});

describe('Vite runtime material output', () => {
  it('contains five classic bridges and the exact npm WASM', () => {
    expect(catalog.hostScripts.map((item) => item.logicalName)).toEqual([
      'crypto-bridge.js',
      'zstd-bridge.js',
      'graphics-bridge.js',
      'cache-bridge.js',
      'file-bridge.js',
    ]);
    expect(catalog.resources).toEqual([
      expect.objectContaining({
        logicalName: 'zstd.wasm',
        size: 251806,
        sha256:
          '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
        contentType: 'application/wasm',
      }),
    ]);
    expect(catalog.sources.zstd).toEqual({
      packageName: '@bokuweb/zstd-wasm',
      version: '0.0.27',
      file: 'dist/web/zstd.wasm',
      sha256:
        '80260eee5795ee8072bb5821e203730c74dca3909938f5ac1128da67f96223df',
      size: 251806,
    });
    expect(data.size).toBe(6);
  });

  it('emits exactly six hash-addressed files whose bytes match the catalog', async () => {
    expect(
      (await readdir(new URL('../dist/materials', import.meta.url))).sort(),
    ).toEqual([...data.keys()].sort());
    for (const artifact of [...catalog.hostScripts, ...catalog.resources]) {
      const bytes = data.get(artifact.sha256);
      if (!bytes)
        throw new Error('Missing generated material: ' + artifact.logicalName);
      expect(bytes.length).toBe(artifact.size);
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(
        artifact.sha256,
      );
      expect(artifact.path).toBe('/runtime/materials/' + artifact.sha256);
      if (artifact.contentType === 'application/javascript') {
        const script = bytes.toString('utf8');
        expect(script).not.toContain('import.meta');
        expect(script).not.toContain('data:application/wasm');
        expect(() => new Script(script)).not.toThrow();
      }
    }
  });

  it('embeds the same six materials into the Native Worker and binds both scripts in its manifest', async () => {
    const nativeManifest: unknown = JSON.parse(
      await readFile(
        new URL('../dist/native/manifest.json', import.meta.url),
        'utf8',
      ),
    );
    const outputFile = z.object({
      path: z.string(),
      sha256: z.string().regex(/^[0-9a-f]{64}$/),
      size: z.number().int().positive(),
    });
    const { files } = z
      .object({
        files: z.object({
          host: outputFile.extend({ path: z.literal('host.js') }),
          worker: outputFile.extend({ path: z.literal('worker.js') }),
        }),
      })
      .parse(nativeManifest);
    expect(nativeManifest).toEqual({
      schemaVersion: 1,
      protocolVersion: catalog.protocolVersion,
      hostAbi: catalog.hostAbi,
      runtimeBaseline: catalog.runtimeBaseline,
      materialVersion: catalog.materialVersion,
      files,
      materials: [...catalog.hostScripts, ...catalog.resources],
      sources: catalog.sources,
    });
    for (const [name, file] of Object.entries(files)) {
      const bytes = await readFile(
        new URL('../dist/native/' + file.path, import.meta.url),
      );
      expect(bytes.length).toBe(file.size);
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(
        file.sha256,
      );
      const script = bytes.toString('utf8');
      expect(script).not.toContain('import.meta');
      expect(() => new Script(script)).not.toThrow();
      if (name === 'host') expect(script).toContain(catalog.materialVersion);
      else
        for (const material of data.values())
          expect(script).toContain(material.toString('base64'));
    }
  });

  it('fetches current shared materials only through static Web paths', async () => {
    const build = {
      ...(await manifest()),
      hostScripts: catalog.hostScripts,
      resources: catalog.resources,
    };
    expect(buildManifestSchema.safeParse(build).success).toBe(true);
    for (const role of ['hostScripts', 'resources'] as const) {
      const material = build[role][0];
      if (!material) throw new Error('Expected product material');
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
        const artifact = [...catalog.hostScripts, ...catalog.resources].find(
          (entry) => entry.path === url.pathname,
        );
        const bytes = artifact && data.get(artifact.sha256);
        if (!artifact || !bytes) throw new Error('Unexpected material request');
        return new Response(new Uint8Array(bytes), {
          headers: { 'content-type': artifact.contentType },
        });
      },
    );
    for (const artifact of [...catalog.hostScripts, ...catalog.resources]) {
      const bytes = await loader.sharedArtifact(
        artifact,
        new AbortController().signal,
        artifact.contentType === 'application/javascript',
      );
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(
        artifact.sha256,
      );
    }
    expect(requests).toHaveLength(6);
    expect(requests.every((url) => url.startsWith('/runtime/materials/'))).toBe(
      true,
    );
    const artifact = catalog.hostScripts[0];
    if (!artifact) throw new Error('Expected classic bridge');
    await expect(
      loader.sharedArtifact(
        { ...artifact, path: '/api/extensions/artifacts/' + artifact.sha256 },
        new AbortController().signal,
        true,
      ),
    ).rejects.toMatchObject({ code: 'integrity_error' });
    expect(requests).toHaveLength(6);
  });
});

describe('native material resolver', () => {
  it('returns owned current bytes and never falls back to HTTP for missing materials', async () => {
    const supported = [...catalog.hostScripts, ...catalog.resources];
    const encoded = Object.fromEntries(
      supported.map((artifact) => {
        const bytes = data.get(artifact.sha256);
        if (!bytes) throw new Error('Missing generated material');
        return [
          artifact.sha256,
          {
            base64: bytes.toString('base64'),
            contentType: artifact.contentType,
          },
        ];
      }),
    );
    const resolver = createNativeMaterialResolver(encoded);
    for (const artifact of supported) {
      const material = resolver(artifact.sha256);
      if (!material) throw new Error('Missing bundled material');
      expect(createHash('sha256').update(material.bytes).digest('hex')).toBe(
        artifact.sha256,
      );
      const first = material.bytes[0];
      if (first === undefined) throw new Error('Expected nonempty material');
      material.bytes[0] = first ^ 1;
      const next = resolver(artifact.sha256);
      if (!next) throw new Error('Missing bundled material');
      expect(createHash('sha256').update(next.bytes).digest('hex')).toBe(
        artifact.sha256,
      );
    }
    let requests = 0;
    const loader = new VerifiedLoader(
      'https://read.example.com',
      async () => {
        ++requests;
        throw new Error('Native materials must be bundled');
      },
      resolver,
    );
    for (const artifact of supported) {
      const bytes = await loader.sharedArtifact(
        artifact,
        new AbortController().signal,
        artifact.contentType === 'application/javascript',
      );
      expect(createHash('sha256').update(bytes).digest('hex')).toBe(
        artifact.sha256,
      );
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
