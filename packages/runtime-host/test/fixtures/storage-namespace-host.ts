/** Controlled host ABI supplier: actual manager/driver/storage, never a Java or official Source oracle. */
import { openDB } from 'idb';
import {
  integer,
  object,
  text,
  workerScope,
} from '../../../../runtime/teavm/bridge/bridge-common.js';
import type { CacheSchema } from '../../../../runtime/teavm/bridge/cache-bridge.js';
import type { FileSchema } from '../../../../runtime/teavm/bridge/file-bridge.js';
declare const STORAGE_FIXTURE_BUILD: string;
declare global {
  var teaDone: ((json: string) => void) | undefined;
  var teaFail: ((error: string) => void) | undefined;
}
const scope = workerScope(),
  FILE = 64 * 1024 * 1024,
  BLOCK = 65536;
const namespace = new URL(location.href).searchParams.get('plugin');
const fsNamespace = new URL(location.href).searchParams.get('fsNamespace');
if (
  !namespace ||
  !/^[a-f0-9]{64}$/.test(namespace) ||
  namespace !== fsNamespace
)
  throw Error(
    'Manager must supply the same real 64hex namespace to both bridges',
  );
const ownNamespace = namespace;
const required = <T>(value: T | undefined): T => {
  if (value === undefined) throw Error('Required storage bridge missing');
  return value;
};
function check(value: unknown, label: string): asserts value {
  if (!value) throw Error(label);
}
const range = () => IDBKeyRange.bound([ownNamespace], [ownNamespace, []]);
const directories = [
  '/storage-seed',
  '/storage-a',
  '/storage-b',
  '/storage-spare',
];
const paths = [
  '/tmp/storage-sentinel',
  '/tmp/storage-transient',
  '/tmp/storage-a',
  '/tmp/storage-b',
  '/tmp/storage-extra',
];
const handles = new Set<string>();
async function cache(
  operation: string,
  extra: Record<string, unknown> = {},
  directory = '/storage-seed',
) {
  return object(
    JSON.parse(
      await required(scope.teaCache)(
        JSON.stringify({
          operation,
          directory,
          maxSize: FILE,
          handle: 'storage-fixture',
          url: 'https://fixture.example.org/storage',
          metadata: { status: 200 },
          ...extra,
        }),
      ),
    ) as unknown,
  );
}
async function file(operation: string, extra: Record<string, unknown> = {}) {
  return object(
    JSON.parse(
      await required(scope.teaFile)(JSON.stringify({ operation, ...extra })),
    ) as unknown,
  );
}
async function openFile(path: string, create = false) {
  if (create) await file('create', { path });
  const handle = text(
    (await file('open', { path, readable: true, writable: true })).handle,
  );
  handles.add(handle);
  return handle;
}
async function closeFile(handle: string) {
  await file('close', { handle });
  handles.delete(handle);
}
async function snapshot() {
  const c = await openDB<CacheSchema>('teavm-http-cache-v3'),
    f = await openDB<FileSchema>('teavm-java-files-v2', 1);
  try {
    const [cacheUsage, fileUsage, cacheChunks, fileChunks] = await Promise.all([
      c.get('usage', ownNamespace),
      f.get('usage', ownNamespace),
      c.count('chunks', range()),
      f.count('chunks', range()),
    ]);
    return { cache: cacheUsage, files: fileUsage, cacheChunks, fileChunks };
  } finally {
    c.close();
    f.close();
  }
}
function block(seed: number, length = BLOCK, offset = 0) {
  const bytes = new Uint8Array(length);
  for (let i = 0; i < length; i++) bytes[i] = (seed + offset + i) & 255;
  return bytes;
}
async function begin(directory: string) {
  const editor = await cache('begin', {}, directory);
  check(editor.accepted === true, 'Cache editor accepted');
  return editor;
}
async function fillCache(
  editor: Record<string, unknown>,
  length: number,
  seed: number,
) {
  const bytes = block(seed);
  let written = 0,
    sequence = 0;
  while (written < length) {
    const part = bytes.subarray(0, Math.min(BLOCK, length - written));
    check(
      await required(scope.teaCacheWrite)(
        text(editor.editor),
        'storage-fixture',
        sequence++,
        part,
      ),
      'Real bounded Cache write accepted',
    );
    written += part.length;
  }
  return written;
}
async function commit(editor: Record<string, unknown>, directory: string) {
  check(
    (
      await cache(
        'commit',
        {
          editor: editor.editor,
          expected: editor.version,
          generation: editor.generation,
        },
        directory,
      )
    ).committed === true,
    'Complete cache committed',
  );
}
async function verifyCache(
  length: number,
  seed: number,
  directory = '/storage-seed',
) {
  const entry = object((await cache('get', { raw: true }, directory)).entry),
    reader = text(entry.reader);
  let offset = 0;
  try {
    for (;;) {
      const bytes = await required(scope.teaCacheRead)(
        reader,
        'storage-fixture',
        BLOCK,
      );
      if (bytes === null) break;
      check(
        bytes.length > 0 &&
          bytes.length <= BLOCK &&
          offset + bytes.length <= length,
        'Bounded Cache prefix',
      );
      check(
        bytes.every(
          (value, index) => value === ((seed + offset + index) & 255),
        ),
        'Exact Cache bytes',
      );
      offset += bytes.length;
    }
    check(offset === length, 'Exact complete Cache EOF');
  } finally {
    await cache('reader-close', { reader }, directory);
  }
  return offset;
}
async function verifyFile(handle: string, length: number, seed: number) {
  await file('seek', { handle, position: 0 });
  let offset = 0;
  for (;;) {
    const bytes = await required(scope.teaFileRead)(handle, BLOCK);
    if (bytes === null) break;
    check(
      bytes.length > 0 &&
        bytes.length <= BLOCK &&
        offset + bytes.length <= length,
      'Bounded file prefix',
    );
    check(
      bytes.every((value, index) => value === ((seed + offset + index) & 255)),
      'Exact file bytes',
    );
    offset += bytes.length;
  }
  check(offset === length, 'Exact complete file EOF');
  return offset;
}
async function cleanup() {
  for (const handle of [...handles]) await closeFile(handle);
  for (const directory of directories) {
    await cache('close', {}, directory);
    await cache('clear', {}, directory);
  }
  for (const path of paths) await file('delete', { path });
  return snapshot();
}
async function seed(seed: number) {
  const length = 131079,
    editor = await begin('/storage-seed');
  await fillCache(editor, length, seed);
  await commit(editor, '/storage-seed');
  const handle = await openFile(paths[0]!, true);
  for (let offset = 0; offset < length; offset += BLOCK)
    check(
      await required(scope.teaFileWrite)(
        handle,
        block(seed, Math.min(BLOCK, length - offset), offset),
      ),
      'Seed file accepted',
    );
  await closeFile(handle);
  return { seed, length, ...(await snapshot()) };
}
async function verify(seed: number, absent: boolean) {
  const probe = (await cache('get')).entry,
    present = !!probe,
    stat = await file('stat', { path: paths[0] });
  if (probe)
    await cache('reader-close', { reader: text(object(probe).reader) });
  check(
    present === !absent && stat.exists === !absent,
    'Both stores share expected namespace visibility',
  );
  if (absent) return { absent: true };
  const handle = await openFile(paths[0]!); // Product open also reclaims a terminated old owner.
  try {
    await verifyFile(handle, 131079, seed);
  } finally {
    await closeFile(handle);
  }
  await verifyCache(131079, seed);
  return { verifiedBytes: 131079, ...(await snapshot()) };
}
async function stageBeforeReplacement() {
  const editor = await begin('/storage-spare');
  await fillCache(editor, 8192, 33);
  const handle = await openFile(paths[1]!, true);
  check(
    await required(scope.teaFileWrite)(handle, new Uint8Array([7])),
    'Transient write',
  );
  await file('delete', { path: paths[1] });
  return snapshot(); // Intentionally retain editor and unlinked open inode until manager terminates this Worker.
}
async function pressure() {
  await cleanup();
  const metadata = new TextEncoder().encode(
    JSON.stringify({ status: 200 }),
  ).length;
  let spare = await begin('/storage-spare');
  const a = await begin('/storage-a'),
    b = await begin('/storage-b');
  await fillCache(a, FILE - metadata, 71);
  await fillCache(b, FILE - 2 * metadata, 83);
  const first = await openFile(paths[2]!, true),
    second = await openFile(paths[3]!, true),
    extra = await openFile(paths[4]!, true);
  for (const [handle, seed] of [
    [first, 101],
    [second, 113],
  ] as const) {
    const bytes = block(seed);
    for (let i = 0; i < 1024; i++)
      check(
        await required(scope.teaFileWrite)(handle, bytes),
        'Actual 64KiB file chunk committed',
      );
  }
  const full = await snapshot();
  check(
    full.cache?.allocatedBytes === 2 * FILE &&
      full.files?.allocatedBytes === 2 * FILE &&
      full.files.logicalBytes === 2 * FILE,
    'Both real allocated partitions are full',
  );
  check(
    full.cacheChunks === 2048 && full.fileChunks === 2048,
    '4096 actual bounded IDB chunks, not sparse length or fabricated usage',
  );
  check(
    full.cache.metadataBytes <= 4 * 1024 * 1024 &&
      full.files.metadataBytes <= 2 * 1024 * 1024,
    'Independent metadata caps',
  );
  const total =
    full.cache.allocatedBytes +
    full.files.allocatedBytes +
    full.cache.metadataBytes +
    full.files.metadataBytes;
  check(
    total <= 262 * 1024 * 1024,
    'Combined logical reservation within 262MiB',
  );
  const denyFile = async () => {
    const before = await snapshot();
    let failed = false;
    try {
      await required(scope.teaFileWrite)(extra, new Uint8Array([1]));
    } catch (error) {
      failed =
        error instanceof Error &&
        error.message.includes('namespace capacity exceeded');
    }
    check(failed, 'Files reject own partition overflow');
    check(
      (await file('tell', { handle: extra })).position === 0,
      'Rejected file write leaves cursor',
    );
    const after = await snapshot();
    check(
      JSON.stringify(before) === JSON.stringify(after),
      'Rejected file write rolls back data and both ledgers',
    );
  };
  const denyCache = async () => {
    check(
      !(await required(scope.teaCacheWrite)(
        text(spare.editor),
        'storage-fixture',
        0,
        new Uint8Array([1]),
      )),
      'Cache rejects own partition overflow',
    );
    spare = await begin('/storage-spare');
    check(
      (await snapshot()).cache?.allocatedBytes === 2 * FILE,
      'Rejected Cache writer cleaned and metadata slot reusable',
    );
  };
  await denyFile();
  await denyCache();
  await file('resize', { handle: second, size: FILE - BLOCK });
  await denyCache();
  await file('seek', { handle: second, position: FILE - BLOCK });
  check(
    await required(scope.teaFileWrite)(second, block(113)),
    'Freed files block reused only by files',
  );
  await cache('abort', { editor: b.editor }, '/storage-b');
  await denyFile();
  const restored = await begin('/storage-b');
  await fillCache(restored, FILE - 2 * metadata, 83);
  check(
    (await snapshot()).cache?.allocatedBytes === 2 * FILE,
    'Freed Cache capacity reusable while files stay full',
  );
  await cache('abort', { editor: spare.editor }, '/storage-spare');
  await commit(a, '/storage-a');
  await commit(restored, '/storage-b');
  const cacheVerified =
    (await verifyCache(FILE - metadata, 71, '/storage-a')) +
    (await verifyCache(FILE - 2 * metadata, 83, '/storage-b'));
  const fileVerified =
    (await verifyFile(first, FILE, 101)) +
    (await verifyFile(second, FILE, 113));
  const after = await cleanup();
  check(
    after.cache?.allocatedBytes === 0 &&
      after.files?.allocatedBytes === 0 &&
      after.files.logicalBytes === 0,
    'Product cleanup refunds both partitions',
  );
  return {
    full,
    totalReservationBytes: total,
    cacheVerifiedBytes: cacheVerified,
    fileVerifiedBytes: fileVerified,
    after,
    checks: [
      'actual-256mib-allocated-with-4096-bounded-chunks',
      'independent-metadata-and-total-reservation',
      'full-partition-rejection-rolls-back',
      'no-cross-database-capacity-borrowing',
      'full-data-streams-verified-and-cleaned',
    ],
  };
}
async function execute(query: string) {
  const args = object(JSON.parse(query) as unknown),
    action = text(args.action);
  await file('initialize');
  if (action === 'seed') return seed(integer(args.seed, 0, 255));
  if (action === 'verify')
    return verify(integer(args.seed, 0, 255), args.absent === true);
  if (action === 'stage') return stageBeforeReplacement();
  if (action === 'pressure') return pressure();
  if (action === 'cleanup') return cleanup();
  throw Error('Unknown controlled storage fixture action');
}
Object.assign(globalThis, {
  hostInit: () => required(globalThis.teaDone)('{}'),
  hostLoad: () =>
    required(globalThis.teaDone)(
      JSON.stringify([
        { id: '1', name: 'CONTROLLED storage ABI fixture', lang: 'en' },
      ]),
    ),
  hostInvoke: (_id: string, operation: string, input: string) => {
    void (async () => {
      check(
        operation === 'search',
        'Fixture only accepts typed search commands',
      );
      const report = await execute(
        text(object(JSON.parse(input) as unknown).query),
      );
      required(globalThis.teaDone)(
        JSON.stringify({
          mangas: [
            {
              url: '/controlled-storage-result',
              title: JSON.stringify({
                controlledAbi: true,
                build: STORAGE_FIXTURE_BUILD,
                namespace: ownNamespace,
                ...report,
              }),
            },
          ],
          hasNextPage: false,
        }),
      );
    })().catch((error) => required(globalThis.teaFail)(String(error)));
  },
  hostAcquireImage: () =>
    required(globalThis.teaFail)('Controlled storage fixture has no images'),
  hostClosePageSession: () => required(globalThis.teaDone)('{"closed":true}'),
});
