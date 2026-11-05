import { afterEach, expect, test, vi } from 'vitest';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { type SourceCall } from '@karuyomi/contracts';
import { TeaVMDriver, type TeaVMGlobals } from '../src/teavm-driver.js';
import { HttpOwnerFailure } from '../src/http-transport.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { encodedBytes, manifest } from './fixtures.js';
import { deferred } from './image-fixtures.js';

const drivers: TeaVMDriver[] = [];
afterEach(async () => {
  for (const driver of drivers.splice(0)) await driver.close();
  vi.unstubAllGlobals();
});

async function setup() {
  const build = await manifest();
  const scope: TeaVMGlobals = {};
  const entries: {
    kind: string;
    requestId: string;
    generation: string;
    token: string;
  }[] = [];
  const driver = new TeaVMDriver(
    scope,
    new VerifiedLoader(
      'https://reader.example',
      async () =>
        new Response(encodedBytes, {
          headers: { 'Content-Type': 'application/gzip' },
        }),
    ),
    () => {
      scope.hostInit = (_agent, requestId, generation, token) => {
        entries.push({ kind: 'init', requestId, generation, token });
        scope.teaDone!('"ready"');
      };
      scope.hostLoad = (requestId, generation, token) => {
        entries.push({ kind: 'load', requestId, generation, token });
        scope.teaDone!(
          JSON.stringify([
            { id: build.sourceIds[0], name: 'Test', lang: 'en' },
          ]),
        );
      };
      scope.hostInvoke = (
        _source,
        _operation,
        _args,
        requestId,
        generation,
        token,
      ) => {
        entries.push({ kind: 'invoke', requestId, generation, token });
        scope.teaDone!('{"mangas":[],"hasNextPage":false}');
      };
      scope.hostAcquireImage = () => {};
      scope.hostClosePageSession = (_session, requestId, generation, token) => {
        entries.push({ kind: 'close', requestId, generation, token });
        scope.teaDone!('{"closed":true}');
      };
    },
    'https://reader.example',
  );
  drivers.push(driver);
  const context = { requestId: 'same-request', generation: 'same-generation' };
  await driver.open(build, 'test', new AbortController().signal, context);
  const sourceId = build.sourceIds[0];
  if (!sourceId) throw Error('Fixture must declare a Source');
  const call: SourceCall = create(pb.SourceCallSchema, {
    ...context,
    sourceId,
    request: { case: 'popular', value: { page: 1 } },
  });
  return { driver, scope, entries, context, call };
}

function metadata(
  operationRequestId: string,
  operationGeneration: string,
  operationToken: string,
) {
  return JSON.stringify({
    operationRequestId,
    operationGeneration,
    operationToken,
    url: 'https://source.example/view',
    method: 'POST',
    headers: [],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 30_000,
  });
}

test('every entry receives a fresh owner token even when its control identities repeat', async () => {
  const { driver, entries, context, call } = await setup();
  await driver.invoke(call, context);
  await driver.closePageSession('session', context);
  expect(entries.map(({ kind }) => kind)).toEqual([
    'init',
    'load',
    'invoke',
    'close',
  ]);
  for (const entry of entries) expect(entry).toMatchObject(context);
  expect(new Set(entries.map(({ token }) => token)).size).toBe(4);
  expect(entries.every(({ token }) => token.length > 0)).toBe(true);
});

test('a stale open rejected during the next entry does not replace its own Source error', async () => {
  const { driver, scope, context, call } = await setup();
  let oldMetadata = '';
  scope.hostInvoke = (
    _source,
    _operation,
    _args,
    requestId,
    generation,
    token,
  ) => {
    oldMetadata = metadata(requestId, generation, token);
    scope.teaDone!('{"mangas":[],"hasNextPage":false}');
  };
  await driver.invoke(call, context);
  scope.hostInvoke = () => {
    expect(() => scope.teaHttpOpen!(oldMetadata)).toThrow(HttpOwnerFailure);
    scope.teaFail!('java.io.IOException: current Source failed');
  };
  await expect(driver.invoke(call, context)).rejects.toMatchObject({
    code: 'source_error',
    message: 'java.io.IOException: current Source failed',
  });
});

test('an old finish rejection cannot poison a later entry with its captured bridge failure', async () => {
  const { driver, scope, context, call } = await setup();
  const oldResponse = deferred<Response>();
  const oldSettled = deferred<void>();
  vi.stubGlobal('fetch', () => oldResponse.promise);
  scope.hostInvoke = (
    _source,
    _operation,
    _args,
    requestId,
    generation,
    token,
  ) => {
    const handle = scope.teaHttpOpen!(metadata(requestId, generation, token));
    void scope.teaHttpFinish!(handle).catch(() => oldSettled.resolve());
    // Deliberately emulate an obsolete early Java completion to exercise fencing.
    scope.teaDone!('{"mangas":[],"hasNextPage":false}');
  };
  await driver.invoke(call, context);
  scope.hostInvoke = () => {};
  const next = driver.invoke(call, context);
  const failure = expect(next).rejects.toMatchObject({
    code: 'source_error',
    message: 'java.io.IOException: next Source failed',
  });
  oldResponse.resolve(new Response('', { status: 403 }));
  await oldSettled.promise;
  scope.teaFail!('java.io.IOException: next Source failed');
  await failure;
});

test.each([false, true])(
  'unfinished callback discardRuntime=%s is classified explicitly',
  async (discardRuntime) => {
    const { driver, scope, context, call } = await setup();
    scope.hostInvoke = () =>
      scope.teaFail!('callbacks exceeded drain deadline', discardRuntime);
    await expect(driver.invoke(call, context)).rejects.toMatchObject({
      code: discardRuntime ? 'runtime_lost' : 'source_error',
      message: 'callbacks exceeded drain deadline',
    });
  },
);
