import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { build } from 'esbuild';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createContext, runInContext } from 'node:vm';
import type { CryptoResult } from '../../../runtime/teavm/bridge/crypto-bridge.js';

interface BridgeMethods {
  teaCrypto?: (request: unknown) => Promise<CryptoResult>;
  teaZstd?: (operation: string, payload: string) => Promise<string>;
  teaCache?: (input: string) => Promise<string>;
  teaFile?: (input: string) => Promise<string>;
}
const bundles = new Map<string, string>();
const requests: string[] = [];
let wasmUrl: string;
beforeEach(() => {
  requests.length = 0;
});
beforeAll(async () => {
  const wasm = await readFile(
    fileURLToPath(
      new URL(
        '../node_modules/@bokuweb/zstd-wasm/dist/web/zstd.wasm',
        import.meta.url,
      ),
    ),
  );
  wasmUrl = URL.createObjectURL(new Blob([wasm], { type: 'application/wasm' }));
  for (const name of ['crypto', 'zstd', 'cache', 'file']) {
    const result = await build({
      entryPoints: [
        fileURLToPath(
          new URL(
            '../../../runtime/teavm/bridge/' + name + '-bridge.ts',
            import.meta.url,
          ),
        ),
      ],
      bundle: true,
      write: false,
      platform: 'browser',
      format: 'iife',
      target: 'es2022',
      define: { 'import.meta.url': 'self.location.origin' },
    });
    bundles.set(name, result.outputFiles[0]!.text);
  }
});
afterAll(() => URL.revokeObjectURL(wasmUrl));

function sandbox(
  name: string,
  resources = true,
  namespace = true,
): BridgeMethods {
  const location = new URL('https://read.example.com/runtime/worker.js');
  if (namespace) location.searchParams.set('plugin', 'bridge-unit-test');
  const scope: BridgeMethods & Record<string, unknown> = {
    location,
    URL,
    crypto,
    atob,
    btoa,
    TextEncoder,
    TextDecoder,
    Uint8Array,
    Int8Array,
    ArrayBuffer,
    DataView,
    WebAssembly,
    setTimeout,
    clearTimeout,
    console,
    fetch: async (input: string) => {
      requests.push(input);
      return fetch(input);
    },
    karuyomiResources: resources ? { 'zstd.wasm': wasmUrl } : {},
  };
  scope.self = scope;
  const context = createContext(scope);
  runInContext(bundles.get(name)!, context);
  return scope;
}

function b64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}
function hex(value: string): string {
  return Buffer.from(value, 'base64').toString('hex');
}
function payload(value: string): Record<string, unknown> {
  const result: unknown = JSON.parse(value);
  if (!result || typeof result !== 'object' || Array.isArray(result))
    throw Error('Expected object response');
  return result as Record<string, unknown>;
}

describe('typed classic Worker bridges with real WebCrypto and npm WASM', () => {
  it('matches RFC4231 HMAC and NIST AES-GCM binary vectors', async () => {
    const bridge = sandbox('crypto').teaCrypto!;
    const hmac = await bridge({
      algorithm: 'HMAC',
      key: b64(new Uint8Array(20).fill(0x0b)),
      body: b64(new TextEncoder().encode('Hi There')),
    });
    expect('body' in hmac && hex(hmac.body)).toBe(
      'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
    );
    const fields = {
      algorithm: 'AES-GCM',
      key: b64(new Uint8Array(16)),
      iv: b64(new Uint8Array(12)),
      tagLength: 128,
      aad: '',
    };
    const encrypted = await bridge({
      ...fields,
      operation: 'encrypt',
      body: b64(new Uint8Array(16)),
    });
    expect('body' in encrypted && hex(encrypted.body)).toBe(
      '0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf',
    );
    const decrypted = await bridge({
      ...fields,
      operation: 'decrypt',
      body: 'body' in encrypted ? encrypted.body : '',
    });
    expect(decrypted).toEqual({ body: b64(new Uint8Array(16)) });
  });

  it('roundtrips AES-CBC 00/ff/UTF8 bytes and rejects invalid crypto inputs structurally', async () => {
    const bridge = sandbox('crypto').teaCrypto!;
    const fields = {
      algorithm: 'AES-CBC',
      key: b64(new Uint8Array(16).fill(7)),
      iv: b64(new Uint8Array(16).fill(3)),
    };
    const body = b64(
      new Uint8Array([0, 255, 128, ...new TextEncoder().encode('桥接')]),
    );
    const encrypted = await bridge({ ...fields, operation: 'encrypt', body });
    expect('body' in encrypted).toBe(true);
    expect(
      await bridge({
        ...fields,
        operation: 'decrypt',
        body: 'body' in encrypted ? encrypted.body : '',
      }),
    ).toEqual({ body });
    for (const request of [
      null,
      { algorithm: 'DES', key: '', body: '' },
      { ...fields, operation: 'sign', body },
      { ...fields, operation: 'encrypt', body: 0 },
    ])
      expect(await bridge(request)).toHaveProperty('error');
  });

  it('runs real npm zstd for empty, binary, UTF8 and concatenated frames using only verified WASM', async () => {
    const bridge = sandbox('zstd').teaZstd!;
    const inputs = [
      new Uint8Array(),
      new Uint8Array([0, 255, 128, 0]),
      new TextEncoder().encode('真实 WASM 二进制'),
      Uint8Array.from({ length: 65_537 }, (_, index) => (index * 37) & 255),
    ];
    const compressed: Uint8Array[] = [];
    for (const input of inputs) {
      const result = payload(await bridge('compress', b64(input)));
      expect(result.error).toBeUndefined();
      expect(typeof result.body).toBe('string');
      const bytes = Buffer.from(String(result.body), 'base64');
      compressed.push(bytes);
      expect(payload(await bridge('decompress', b64(bytes)))).toEqual({
        body: b64(input),
      });
    }
    expect(
      payload(
        await bridge(
          'decompress',
          Buffer.concat(compressed).toString('base64'),
        ),
      ),
    ).toEqual({ body: Buffer.concat(inputs).toString('base64') });
    expect(requests).toEqual([wasmUrl]);
  });

  it('rejects truncated frames, declared output bombs, frame floods and over-budget input', async () => {
    const bridge = sandbox('zstd').teaZstd!;
    const compressed = payload(
      await bridge('compress', b64(new Uint8Array([1, 2, 3]))),
    );
    const truncated = Buffer.from(String(compressed.body), 'base64').subarray(
      0,
      -1,
    );
    expect(payload(await bridge('decompress', b64(truncated))).error).toBe(
      'Truncated Zstd frame',
    );
    const outputBomb = new Uint8Array(13);
    const view = new DataView(outputBomb.buffer);
    view.setUint32(0, 0xfd2fb528, true);
    outputBomb[4] = 0xe0;
    view.setBigUint64(5, 8_388_609n, true);
    expect(payload(await bridge('decompress', b64(outputBomb))).error).toBe(
      'Zstd output limit exceeded',
    );
    const flood = new Uint8Array(1025 * 8);
    for (let index = 0; index < 1025; ++index)
      new DataView(flood.buffer).setUint32(index * 8, 0x184d2a50, true);
    expect(payload(await bridge('decompress', b64(flood))).error).toBe(
      'Zstd frame count limit exceeded',
    );
    expect(
      payload(await bridge('compress', b64(new Uint8Array(8_388_609)))).error,
    ).toBe('Zstd input limit exceeded');
    expect(payload(await bridge('unknown', '')).error).toBe(
      'Unknown Zstd operation',
    );
  });

  it('refuses missing verified WASM and missing storage namespaces without network fallback', async () => {
    const initialRequests = requests.length;
    const bridge = sandbox('zstd', false).teaZstd!;
    expect(payload(await bridge('compress', '')).error).toBe(
      'Verified zstd.wasm resource is missing',
    );
    expect(requests).toHaveLength(initialRequests);
    expect(() => sandbox('cache', true, false)).toThrow(
      'Runtime cache namespace is required',
    );
    expect(() => sandbox('file', true, false)).toThrow(
      'Runtime filesystem namespace is required',
    );
  });

  it('validates Java storage input before touching IndexedDB', async () => {
    const cache = sandbox('cache').teaCache!;
    for (const request of [
      null,
      { operation: 'unknown' },
      { operation: 'put', directory: '/cache', maxSize: 10, body: 0 },
    ])
      await expect(cache(JSON.stringify(request))).rejects.toThrow();
    const file = sandbox('file').teaFile!;
    for (const request of [
      null,
      { operation: 'unknown' },
      { operation: 'seek', position: -1 },
      { operation: 'read', length: '1' },
    ])
      await expect(file(JSON.stringify(request))).rejects.toThrow();
  });
});
