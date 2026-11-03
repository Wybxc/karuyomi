/** Real Worker/IndexedDB regression entry, driven by a browser harness. */
import {
  array,
  decodeBase64,
  encodeBase64,
  object,
  text,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type {} from '../../../runtime/teavm/bridge/crypto-bridge.js';
import type {} from '../../../runtime/teavm/bridge/zstd-bridge.js';
import type {} from '../../../runtime/teavm/bridge/graphics-bridge.js';
import type {} from '../../../runtime/teavm/bridge/cache-bridge.js';
import type {} from '../../../runtime/teavm/bridge/file-bridge.js';

function installedBridges() {
  const {
    teaCrypto,
    teaZstd,
    teaGraphicsSync,
    teaGraphicsAsync,
    teaCache,
    teaFile,
    teaFileSystemClose,
  } = workerScope();
  assert(typeof teaCrypto === 'function', 'Crypto bridge installed');
  assert(typeof teaZstd === 'function', 'Zstd bridge installed');
  assert(
    typeof teaGraphicsSync === 'function',
    'Sync graphics bridge installed',
  );
  assert(
    typeof teaGraphicsAsync === 'function',
    'Async graphics bridge installed',
  );
  assert(typeof teaCache === 'function', 'Cache bridge installed');
  assert(typeof teaFile === 'function', 'File bridge installed');
  assert(
    typeof teaFileSystemClose === 'function',
    'File close bridge installed',
  );
  return {
    teaCrypto,
    teaZstd,
    teaGraphicsSync,
    teaGraphicsAsync,
    teaCache,
    teaFile,
    teaFileSystemClose,
  };
}
const scope = installedBridges();
const binary = new Uint8Array([
  0,
  255,
  128,
  0,
  13,
  10,
  ...new TextEncoder().encode('持久化'),
]);
const encoded = encodeBase64(binary);
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw Error(message);
}
const file = async (request: unknown) =>
  object(JSON.parse(await scope.teaFile(JSON.stringify(request))) as unknown);
const cache = async (operation: string, extra: Record<string, unknown> = {}) =>
  object(
    JSON.parse(
      await scope.teaCache(
        JSON.stringify({
          directory: '/bridge-probe',
          maxSize: 1_048_576,
          handle: 'probe',
          operation,
          ...extra,
        }),
      ),
    ) as unknown,
  );

async function cryptoAndZstd(checks: string[]) {
  const signed = object(
    await scope.teaCrypto({
      algorithm: 'HMAC',
      key: encodeBase64(new Uint8Array(20).fill(0x0b)),
      body: encodeBase64(new TextEncoder().encode('Hi There')),
    }),
  );
  const hex = [...decodeBase64(text(signed.body))]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
  assert(
    hex === 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
    'HMAC vector',
  );
  checks.push('webcrypto-rfc4231');
  const compressed = object(
    JSON.parse(await scope.teaZstd('compress', encoded)) as unknown,
  );
  const plain = object(
    JSON.parse(
      await scope.teaZstd('decompress', text(compressed.body)),
    ) as unknown,
  );
  assert(plain.body === encoded, 'Zstd binary roundtrip');
  checks.push('npm-wasm-zstd-binary');
}

async function graphics(checks: string[]) {
  const pixels = new Uint8Array([
    0, 255, 128, 255, 255, 0, 0, 255, 1, 2, 3, 255, 128, 128, 128, 255,
  ]);
  const created = scope.teaGraphicsSync({ op: 'create', width: 2, height: 2 });
  scope.teaGraphicsSync({
    op: 'putPixels',
    id: created.id,
    body: encodeBase64(pixels),
  });
  assert(
    scope.teaGraphicsSync({ op: 'pixels', id: created.id }).body ===
      encodeBase64(pixels),
    'Canvas RGBA bytes',
  );
  const png = await scope.teaGraphicsAsync({
    op: 'encode',
    id: created.id,
    format: 'PNG',
    quality: 100,
  });
  assert(png.ok === true && png.mime === 'image/png', 'Canvas PNG encoding');
  const decoded = await scope.teaGraphicsAsync({
    op: 'decode',
    body: png.body,
  });
  assert(
    decoded.ok === true && decoded.width === 2 && decoded.height === 2,
    'Canvas PNG decoding',
  );
  scope.teaGraphicsSync({ op: 'recycle', id: created.id });
  scope.teaGraphicsSync({ op: 'recycle', id: decoded.id });
  let recycled = false;
  try {
    scope.teaGraphicsSync({ op: 'pixels', id: created.id });
  } catch {
    recycled = true;
  }
  assert(recycled, 'Recycled Canvas handle must fail');
  checks.push('offscreen-canvas-rgba-png-recycle');
}

async function cacheWrite(checks: string[]) {
  await cache('clear');
  const begins = await Promise.all([
    cache('begin', { url: 'source-entry' }),
    cache('begin', { url: 'source-entry' }),
  ]);
  const winners = begins.filter((value) => value.accepted === true);
  assert(winners.length === 1, 'Only one concurrent cache editor');
  const editor = winners[0]!;
  const committed = await cache('put', {
    url: 'source-entry',
    editor: editor.editor,
    expected: null,
    generation: editor.generation,
    metadata: { status: 200, headers: [['x-test', 'binary']] },
    body: encoded,
  });
  assert(committed.committed === true, 'Cache commit');
  const entry = object((await cache('get', { url: 'source-entry' })).entry);
  assert(entry.body === encoded, 'Cache binary bytes');
  const stale = await cache('update', {
    url: 'source-entry',
    expected: 'stale-version',
    generation: entry.generation,
    metadata: {},
  });
  assert(stale.committed === false, 'Cache stale version must fail');
  const updated = await cache('update', {
    url: 'source-entry',
    expected: entry.version,
    generation: entry.generation,
    metadata: { status: 304 },
  });
  assert(updated.committed === true, 'Cache conditional metadata update');
  assert(
    object((await cache('get', { url: 'source-entry' })).entry).body ===
      encoded,
    'Cache update preserves body',
  );
  assert(
    array((await cache('urls')).urls).includes('source-entry'),
    'Cache URLs',
  );
  checks.push('indexeddb-cache-editor-cas-binary');
}

const directory = '/tmp/typed-bridge-regression';
async function filesystemWrite(checks: string[]) {
  await file({ operation: 'initialize' });
  await file({ operation: 'mkdir', path: directory });
  const path = directory + '/unlinked',
    renamed = directory + '/renamed';
  await file({ operation: 'create', path });
  const opened = await file({
    operation: 'open',
    path,
    readable: true,
    writable: true,
  });
  const second = await file({ operation: 'open', path, readable: true });
  await file({ operation: 'write', handle: opened.handle, body: encoded });
  await file({ operation: 'seek', handle: opened.handle, position: 0 });
  assert(
    (
      await file({
        operation: 'read',
        handle: opened.handle,
        length: binary.length,
      })
    ).body === encoded,
    'Filesystem binary bytes',
  );
  assert(
    (await file({ operation: 'read', handle: second.handle, length: 1 }))
      .body === 'AA==',
    'Independent file cursors',
  );
  assert(
    (await file({ operation: 'rename', source: path, path: renamed }))
      .changed === true,
    'Rename open file',
  );
  assert(
    (await file({ operation: 'delete', path: renamed })).changed === true,
    'Unlink open file',
  );
  await file({ operation: 'seek', handle: opened.handle, position: 0 });
  assert(
    (
      await file({
        operation: 'read',
        handle: opened.handle,
        length: binary.length,
      })
    ).body === encoded,
    'Open inode survives unlink',
  );
  await file({ operation: 'close', handle: opened.handle });
  await file({ operation: 'close', handle: second.handle });
  assert(
    (await file({ operation: 'stat', path: renamed })).exists === false,
    'Unlinked path absent',
  );
  const persistentPath = directory + '/persisted';
  await file({ operation: 'create', path: persistentPath });
  const persistent = await file({
    operation: 'open',
    path: persistentPath,
    readable: true,
    writable: true,
  });
  await file({ operation: 'write', handle: persistent.handle, body: encoded });
  await file({ operation: 'close', handle: persistent.handle });
  checks.push('indexeddb-files-cursors-rename-unlink');
}

globalThis.onmessage = (event: MessageEvent<unknown>) => {
  void (async () => {
    const phase = text(object(event.data).phase),
      checks: string[] = [];
    try {
      if (phase === 'write') {
        await cryptoAndZstd(checks);
        await graphics(checks);
        await cacheWrite(checks);
        await filesystemWrite(checks);
      } else if (phase === 'isolation') {
        assert(
          (await file({ operation: 'stat', path: directory + '/persisted' }))
            .exists === false,
          'Filesystem namespace isolation',
        );
        assert(
          (await cache('get', { url: 'source-entry' })).entry === undefined,
          'Cache namespace isolation',
        );
        checks.push('worker-namespace-isolation');
      } else if (phase === 'reopen') {
        const entry = object(
          (await cache('get', { url: 'source-entry' })).entry,
        );
        assert(
          entry.body === encoded && object(entry.metadata).status === 304,
          'Cache persisted across Worker restart',
        );
        const opened = await file({
          operation: 'open',
          path: directory + '/persisted',
          readable: true,
        });
        assert(
          typeof opened.handle === 'string',
          'File persisted across Worker restart',
        );
        assert(
          (
            await file({
              operation: 'read',
              handle: opened.handle,
              length: binary.length,
            })
          ).body === encoded,
          'Persistent file bytes',
        );
        await file({ operation: 'close', handle: opened.handle });
        await file({ operation: 'delete', path: directory + '/persisted' });
        await file({ operation: 'delete', path: directory });
        await cache('clear');
        checks.push('indexeddb-persistence-across-worker-restart');
      } else throw Error('Unknown test phase');
      await scope.teaFileSystemClose();
      postMessage({ passed: true, phase, checks });
    } catch (error) {
      postMessage({
        passed: false,
        phase,
        checks,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  })();
};
