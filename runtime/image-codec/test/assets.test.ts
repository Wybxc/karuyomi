import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import {
  createImageCodecAssetProvider,
  prepareImageCodecAssets,
  type ImageCodecMaterial,
  type ImageCodecObjectUrls,
} from '../assets.ts';
import { createNativeMaterialResolver } from '../../../packages/runtime-host/src/native-materials.ts';
import { VerifiedLoader } from '../../../packages/runtime-host/src/verified-loader.ts';

function fixture() {
  const values = new Map<string, { bytes: Uint8Array; contentType: string }>();
  const materials: ImageCodecMaterial[] = [];
  for (const name of [
    'worker.js',
    'png.mjs',
    'png.wasm',
    'jpeg.mjs',
    'jpeg.wasm',
    'encoder.mjs',
    'encoder.wasm',
  ]) {
    const bytes = new TextEncoder().encode('Fixture ' + name);
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const contentType = name.endsWith('.wasm')
      ? 'application/wasm'
      : 'application/javascript';
    materials.push({
      logicalName: name,
      path: '/runtime/materials/' + sha256,
      sha256,
      size: bytes.length,
      contentType,
    });
    values.set(sha256, { bytes, contentType });
  }
  const created: Blob[] = [];
  const revoked: string[] = [];
  const objectUrls: ImageCodecObjectUrls = {
    createObjectURL: (blob) => {
      created.push(blob);
      return 'blob:https://reader.example/' + created.length;
    },
    revokeObjectURL: (url) => {
      revoked.push(url);
    },
  };
  return { materials, values, objectUrls, created, revoked };
}

describe('image codec material leases', () => {
  it('uses only same-origin verified static bytes and keeps URLs until the owner releases them', async () => {
    const f = fixture();
    const requests: string[] = [];
    const loader = new VerifiedLoader(
      'https://reader.example',
      async (input, options) => {
        const url = new URL(String(input));
        requests.push(url.pathname);
        expect(options).toMatchObject({
          credentials: 'omit',
          cache: 'force-cache',
          redirect: 'manual',
        });
        const value = f.values.get(url.pathname.split('/').pop()!)!;
        return new Response(new Uint8Array(value.bytes), {
          headers: { 'content-type': value.contentType },
        });
      },
    );
    const lease = await prepareImageCodecAssets(
      f.materials,
      'jpeg',
      loader,
      new AbortController().signal,
      f.objectUrls,
    );
    expect(requests).toHaveLength(5);
    expect(
      requests.every((item) => item.startsWith('/runtime/materials/')),
    ).toBe(true);
    expect(new TextDecoder().decode(lease.decoder.wasmBinary)).toBe(
      'Fixture jpeg.wasm',
    );
    expect(new TextDecoder().decode(lease.encoder.wasmBinary)).toBe(
      'Fixture encoder.wasm',
    );
    expect(f.created).toHaveLength(3);
    expect(await f.created[0]!.text()).toBe('Fixture worker.js');
    expect(f.revoked).toEqual([]);
    lease.release();
    expect(f.revoked).toEqual([
      'blob:https://reader.example/1',
      'blob:https://reader.example/2',
      'blob:https://reader.example/3',
    ]);
    lease.release();
    expect(f.revoked).toHaveLength(3);
  });

  it('native providers obtain codec bytes only from the bundled resolver, with no HTTP fallback', async () => {
    const f = fixture();
    const resolver = createNativeMaterialResolver(
      Object.fromEntries(
        [...f.values].map(([sha256, value]) => [
          sha256,
          {
            base64: Buffer.from(value.bytes).toString('base64'),
            contentType: value.contentType,
          },
        ]),
      ),
    );
    let requests = 0;
    const loader = new VerifiedLoader(
      'https://reader.example',
      async () => {
        ++requests;
        throw new Error('Native must not use network for codec materials');
      },
      resolver,
    );
    const provider = createImageCodecAssetProvider(f.materials, loader);
    const lease = await provider.prepare('png', new AbortController().signal);
    expect(lease.workerUrl.protocol).toBe('blob:');
    expect(new TextDecoder().decode(lease.decoder.wasmBinary)).toBe(
      'Fixture png.wasm',
    );
    lease.release();
    const withoutPng = createNativeMaterialResolver({});
    await expect(
      prepareImageCodecAssets(
        f.materials,
        'png',
        new VerifiedLoader('https://reader.example', undefined, withoutPng),
        new AbortController().signal,
        f.objectUrls,
      ),
    ).rejects.toMatchObject({ code: 'unsupported_capability' });
    expect(requests).toBe(0);
  });

  it('corrupt bytes or cancellation never create an executable URL', async () => {
    const f = fixture();
    const loader = new VerifiedLoader(
      'https://reader.example',
      async (input) => {
        const value = f.values.get(
          new URL(String(input)).pathname.split('/').pop()!,
        )!;
        const bytes = new Uint8Array(value.bytes);
        const first = bytes[0];
        if (first === undefined)
          throw new Error('Expected nonempty material fixture');
        bytes[0] = first ^ 1;
        return new Response(bytes, {
          headers: { 'content-type': value.contentType },
        });
      },
    );
    await expect(
      prepareImageCodecAssets(
        f.materials,
        'png',
        loader,
        new AbortController().signal,
        f.objectUrls,
      ),
    ).rejects.toMatchObject({ code: 'integrity_error' });
    const abort = new AbortController();
    abort.abort();
    await expect(
      prepareImageCodecAssets(
        f.materials,
        'png',
        loader,
        abort.signal,
        f.objectUrls,
      ),
    ).rejects.toMatchObject({ name: 'AbortError' });
    expect(f.created).toEqual([]);
  });

  it('releases every URL already created if a later URL creation fails', async () => {
    const f = fixture();
    const resolver = (sha256: string) => f.values.get(sha256);
    const loader = new VerifiedLoader(
      'https://reader.example',
      undefined,
      resolver,
    );
    let calls = 0;
    const objectUrls: ImageCodecObjectUrls = {
      createObjectURL: (blob) => {
        if (++calls === 3) throw new Error('Fixture object URL quota');
        return f.objectUrls.createObjectURL(blob);
      },
      revokeObjectURL: f.objectUrls.revokeObjectURL,
    };
    await expect(
      prepareImageCodecAssets(
        f.materials,
        'png',
        loader,
        new AbortController().signal,
        objectUrls,
      ),
    ).rejects.toThrow('Fixture object URL quota');
    expect(f.revoked).toEqual([
      'blob:https://reader.example/1',
      'blob:https://reader.example/2',
    ]);
  });
});
