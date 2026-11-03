import { afterEach, expect, test, vi } from 'vitest';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HttpFrameReader,
  encodeMetaFrame,
  encodePreamble,
  httpRequestMetaSchema,
  type SourceCall,
} from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { TeaVMDriver, type TeaVMGlobals } from '../src/teavm-driver.js';
import { ImageResourceStore } from '../src/image-resources.js';
import { RuntimeFailure } from '../src/errors.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { encodedBytes, manifest } from './fixtures.js';
import { deferred, pngHeader } from './image-fixtures.js';

const drivers: TeaVMDriver[] = [];
const stores: ImageResourceStore[] = [];
afterEach(async () => {
  for (const driver of drivers.splice(0)) await driver.close();
  for (const store of stores.splice(0))
    store.clear(new RuntimeFailure('runtime_lost', 'test teardown'));
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
async function setup(install: (scope: TeaVMGlobals) => void) {
  const build = await manifest();
  const scope: TeaVMGlobals = {};
  const loader = new VerifiedLoader(
    'https://reader.example',
    async () =>
      new Response(encodedBytes, {
        headers: { 'Content-Type': 'application/gzip' },
      }),
  );
  const driver = new TeaVMDriver(
    scope,
    loader,
    () => {
      scope.hostInit = () => scope.teaDone?.('"ready"');
      scope.hostLoad = () =>
        scope.teaDone?.(
          JSON.stringify([
            { id: build.sourceIds[0], name: 'Test', lang: 'en' },
          ]),
        );
      scope.hostInvoke = () =>
        scope.teaDone?.('{"mangas":[],"hasNextPage":false}');
      scope.hostClosePageSession = () => scope.teaDone?.('{"closed":true}');
      install(scope);
    },
    'https://reader.example',
  );
  drivers.push(driver);
  return { driver, scope, build };
}
const metadata = (sourceId: string): SourceCall =>
  create(pb.SourceCallSchema, {
    requestId: 'metadata',
    sourceId,
    generation: 'generation',
    request: { case: 'popular', value: { page: 1 } },
  });
function collector() {
  const store = new ImageResourceStore({
    decode: async () => ({ width: 2, height: 3, close() {} }),
  });
  stores.push(store);
  const image = store.create('generation');
  const channel = new MessageChannel();
  image.attach(channel.port1);
  return { store, image, channel };
}
test('open rejects AOT exports without the image ABI before initialization', async () => {
  const { driver, scope, build } = await setup(() => {});
  const initialized = vi.fn();
  scope.teaDone = initialized;
  await expect(
    driver.open(build, 'test', new AbortController().signal),
  ).rejects.toMatchObject({ code: 'unsupported_capability' });
  expect(initialized).not.toHaveBeenCalled();
});

test('the installed image ABI sends typed bytes and survives HTTP operation cleanup', async () => {
  const refs: string[][] = [];
  const { driver, build } = await setup((scope) => {
    scope.hostAcquireImage = (...args) => {
      refs.push(args);
      void (async () => {
        const handle = scope.teaImageOpen!('image/png');
        await scope.teaImageWrite!(handle, pngHeader());
        scope.teaDone!(await scope.teaImageClose!(handle));
      })().catch((error) => scope.teaFail!(String(error)));
    };
  });
  await driver.open(build, 'test', new AbortController().signal);
  const { store, image, channel } = collector();
  const result = await driver.acquireImage(
    build.sourceIds[0]!,
    'page-session',
    'p-0',
    channel.port2,
    image.resourceId,
    { requestId: 'image', generation: 'generation' },
  );
  const resource = await image.publish(result);
  expect(refs).toEqual([[build.sourceIds[0], 'page-session', 'p-0']]);
  await driver.invoke(metadata(build.sourceIds[0]!), {
    requestId: 'metadata',
    generation: 'generation',
  });
  await expect(
    driver.closePageSession('page-session', {
      requestId: 'close-pages',
      generation: 'generation',
    }),
  ).resolves.toEqual({ closed: true });
  expect(store.snapshot.resources).toBe(1);
  expect(
    new Uint8Array(await (await fetch(resource.url)).arrayBuffer()),
  ).toEqual(pngHeader());
  store.release(resource.resourceId, resource.generation);
});

test('image cancellation closes a pending HTTP body but waits for swallowed Java failure to unwind', async () => {
  const reading = deferred<void>();
  const caught = deferred<void>();
  const unwind = deferred<void>();
  const cancelledBody = vi.fn();
  let fetchSignal: AbortSignal | null | undefined;
  vi.stubGlobal('fetch', async (_url: unknown, init?: RequestInit) => {
    fetchSignal = init?.signal;
    expect(init?.body).toBeInstanceOf(Blob);
    if (!(init?.body instanceof Blob)) throw new Error('missing HTTP frames');
    const reader = new HttpFrameReader(init.body.stream(), 0);
    const meta = httpRequestMetaSchema.parse(await reader.meta());
    expect(await reader.read(1)).toBeNull();
    let start = true;
    return new Response(
      new ReadableStream<Uint8Array>({
        pull(controller) {
          if (start) {
            start = false;
            controller.enqueue(encodePreamble());
            controller.enqueue(
              encodeMetaFrame({
                requestId: meta.requestId,
                runtimeGeneration: meta.runtimeGeneration,
                upstreamStatus: 200,
                message: 'OK',
                url: meta.url,
                headers: [],
                hasBody: true,
                bodyLength: null,
                decoded: true,
              }),
            );
          }
        },
        cancel: cancelledBody,
      }),
      { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
    );
  });
  const { driver, build } = await setup((scope) => {
    scope.hostAcquireImage = () => {
      void (async () => {
        const handle = scope.teaHttpOpen!(
          JSON.stringify({
            url: 'https://source.example/image',
            method: 'GET',
            headers: [],
            hasBody: false,
            bodyLength: 0,
            timeoutMs: 30_000,
          }),
        );
        await scope.teaHttpFinish!(handle);
        reading.resolve();
        try {
          await scope.teaHttpRead!(handle, 64 * 1024);
        } catch {
          caught.resolve();
          await unwind.promise;
          scope.teaDone!('{}');
        }
      })().catch((error) => scope.teaFail!(String(error)));
    };
  });
  await driver.open(build, 'test', new AbortController().signal);
  const { image, channel } = collector();
  const result = driver.acquireImage(
    build.sourceIds[0]!,
    'session',
    'p-0',
    channel.port2,
    image.resourceId,
    { requestId: 'image', generation: 'generation' },
  );
  const rejected = expect(result).rejects.toMatchObject({ code: 'cancelled' });
  await reading.promise;
  image.abort(new RuntimeFailure('cancelled', 'cancelled'));
  await caught.promise;
  expect(fetchSignal?.aborted).toBe(true);
  expect(cancelledBody).toHaveBeenCalledOnce();
  await expect(
    driver.invoke(metadata(build.sourceIds[0]!)),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  unwind.resolve();
  await rejected;
  await expect(
    driver.invoke(metadata(build.sourceIds[0]!)),
  ).resolves.toMatchObject({
    case: 'mangaPage',
    value: { mangas: [], hasNextPage: false },
  });
  image.release();
});

test.each([401, 403])(
  'Access %s cannot be swallowed by image processing',
  async (status) => {
    vi.stubGlobal('fetch', async () => new Response('', { status }));
    const { driver, build } = await setup((scope) => {
      scope.hostAcquireImage = () => {
        const handle = scope.teaHttpOpen!(
          JSON.stringify({
            url: 'https://source.example/image',
            method: 'GET',
            headers: [],
            hasBody: false,
            bodyLength: 0,
            timeoutMs: 30_000,
          }),
        );
        void scope.teaHttpFinish!(handle).catch(() => scope.teaDone!('{}'));
      };
    });
    await driver.open(build, 'test', new AbortController().signal);
    const { image, channel } = collector();
    await expect(
      driver.acquireImage(
        build.sourceIds[0]!,
        'session',
        'p-0',
        channel.port2,
        image.resourceId,
        { requestId: 'image', generation: 'generation' },
      ),
    ).rejects.toMatchObject({
      code: status === 401 ? 'access_required' : 'access_denied',
    });
    image.release();
  },
);
