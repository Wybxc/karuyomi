import { catalog } from './fixtures.js';
import { afterEach, expect, test, vi } from 'vitest';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { type BuildManifest, type SourceCall } from '@karuyomi/contracts';
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

async function setup(
  buildOverride?: BuildManifest,
  preferences?: pb.PreferenceBootstrap,
  catalogOverride?: { catalogUrl: string; repoId: string },
) {
  const build = buildOverride ?? (await manifest());
  const configurations: string[] = [];
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
      scope.hostLoad = (configuration, requestId, generation, token) => {
        configurations.push(configuration);
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
  await driver.open(
    build,
    'test',
    new AbortController().signal,
    catalogOverride ?? {
      catalogUrl: 'https://reader.example/extensions/index.json',
      repoId: build.repoId,
    },
    context,
    preferences,
  );
  const sourceId = build.sourceIds[0];
  if (!sourceId) throw Error('Fixture must declare a Source');
  const call: SourceCall = create(pb.SourceCallSchema, {
    ...context,
    sourceId,
    request: { case: 'popular', value: { page: 1 } },
  });
  return { driver, scope, entries, context, call, configurations };
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

test('typed filter snapshots pass through the owned Java entry with the retained query identity', async () => {
  const { driver, scope, context, call } = await setup();
  const entries: { source: string; operation: string; args: string }[] = [];
  scope.hostInvoke = (
    source,
    operation,
    args,
    requestId,
    generation,
    token,
  ) => {
    expect({ requestId, generation }).toEqual(context);
    expect(token).not.toBe('');
    entries.push({ source, operation, args });
    scope.teaDone!(
      JSON.stringify({
        snapshotId: 'filters-current',
        nodes: [
          {
            name: 'Order',
            sort: { options: ['Recent', 'Popular'], state: {} },
          },
          {
            name: 'Tags',
            group: { nodes: [{ name: 'Fantasy', checkBox: { state: false } }] },
          },
        ],
      }),
    );
  };
  const result = await driver.invoke(
    create(pb.SourceCallSchema, {
      ...context,
      sourceId: call.sourceId,
      request: {
        case: 'getFilters',
        value: { retainedSnapshotId: 'filters-applied' },
      },
    }),
    context,
  );
  expect(entries).toEqual([
    {
      source: call.sourceId,
      operation: 'getFilters',
      args: JSON.stringify({ retainedSnapshotId: 'filters-applied' }),
    },
  ]);
  expect(result.case).toBe('filters');
  if (result.case !== 'filters')
    throw new Error('Expected the filter snapshot payload');
  expect(result.value.snapshotId).toBe('filters-current');
  expect(result.value.nodes[0]?.kind.case).toBe('sort');
  expect(result.value.nodes[1]?.kind.case).toBe('group');
});

test('filtered search preserves explicit false, null sorting and nested paths in Java arguments', async () => {
  const { driver, scope, context, call } = await setup();
  let argumentsJson = '';
  scope.hostInvoke = (_source, operation, args) => {
    expect(operation).toBe('search');
    argumentsJson = args;
    scope.teaDone!('{"mangas":[],"hasNextPage":true}');
  };
  const result = await driver.invoke(
    create(pb.SourceCallSchema, {
      ...context,
      sourceId: call.sourceId,
      request: {
        case: 'search',
        value: {
          page: 2,
          query: '',
          filters: {
            snapshotId: 'filters-applied',
            updates: [
              { path: [0], state: { case: 'sort', value: {} } },
              { path: [1, 0], state: { case: 'checkBox', value: false } },
            ],
          },
        },
      },
    }),
    context,
  );
  expect(JSON.parse(argumentsJson)).toEqual({
    page: 2,
    filters: {
      snapshotId: 'filters-applied',
      updates: [
        { path: [0], sort: {} },
        { path: [1, 0], checkBox: false },
      ],
    },
  });
  expect(result.case).toBe('mangaPage');
  if (result.case !== 'mangaPage')
    throw new Error('Expected filtered search results');
  expect(result.value.hasNextPage).toBe(true);
});

test('hostLoad receives confirmed and session bootstrap before source construction and the owned package sync policy', async () => {
  const build = {
    ...(await manifest()),
    packageName: 'eu.kanade.tachiyomi.extension.zh.komiic',
    repoId: 'keiyoushi',
  };
  const bootstrap = create(pb.PreferenceBootstrapSchema, {
    packageName: build.packageName,
    sources: [
      {
        sourceId: build.sourceIds[0],
        entries: [
          {
            key: 'preferred_mirror',
            value: { value: { case: 'text', value: '1' } },
          },
          {
            key: 'session-long',
            value: {
              value: { case: 'longInteger', value: 9223372036854775807n },
            },
          },
        ],
      },
    ],
  });
  const { configurations, entries } = await setup(build, bootstrap);
  expect(entries.map((entry) => entry.kind)).toEqual(['init', 'load']);
  expect(configurations).toHaveLength(1);
  expect(JSON.parse(configurations[0]!)).toEqual({
    bootstrap: {
      packageName: build.packageName,
      sources: [
        {
          sourceId: build.sourceIds[0],
          entries: [
            { key: 'preferred_mirror', value: { text: '1' } },
            {
              key: 'session-long',
              value: { longInteger: '9223372036854775807' },
            },
          ],
        },
      ],
    },
    syncRules: [
      { key: 'preferred_mirror', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
      { key: 'CHAPTER_FILTER', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
    ],
  });
});

test('typed preference edits invoke Java once and reject Source claims that unapproved secrets are synchronized', async () => {
  const build = {
    ...(await manifest()),
    packageName: 'eu.kanade.tachiyomi.extension.en.mangakatana',
    repoId: 'keiyoushi',
  };
  const { driver, scope, context, call } = await setup(build);
  const invoked = vi.fn((_source: string, operation: string, args: string) => {
    expect(operation).toBe('editPreference');
    expect(JSON.parse(args)).toEqual({
      snapshotId: 'prefs-1',
      path: [0],
      change: { text: '' },
    });
    scope.teaDone!(
      JSON.stringify({
        accepted: false,
        snapshot: {
          snapshotId: 'prefs-2',
          nodes: [],
          syncValues: [{ key: 'SERVER_PREFERENCE', value: { text: 'mk' } }],
          sessionValues: [{ key: 'token', value: { text: 'secret' } }],
        },
      }),
    );
  });
  scope.hostInvoke = invoked;
  const editing = create(pb.SourceCallSchema, {
    ...context,
    sourceId: call.sourceId,
    request: {
      case: 'editPreference',
      value: {
        snapshotId: 'prefs-1',
        path: [0],
        command: {
          case: 'change',
          value: { value: { case: 'text', value: '' } },
        },
      },
    },
  });
  const result = await driver.invoke(editing, context);
  expect(invoked).toHaveBeenCalledOnce();
  expect(result.case).toBe('preferenceEdit');
  if (result.case !== 'preferenceEdit' || !result.value.snapshot)
    throw new Error('Expected edit snapshot');
  expect(result.value.accepted).toBe(false);
  expect(result.value.snapshot.syncValues[0]?.key).toBe('SERVER_PREFERENCE');
  scope.hostInvoke = vi.fn(() =>
    scope.teaDone!(
      JSON.stringify({
        snapshotId: 'invalid',
        nodes: [],
        syncValues: [{ key: 'token', value: { text: 'secret' } }],
      }),
    ),
  );
  await expect(
    driver.invoke(
      create(pb.SourceCallSchema, {
        ...context,
        sourceId: call.sourceId,
        request: { case: 'getPreferences', value: {} },
      }),
      context,
    ),
  ).rejects.toThrow('not approved');
  expect(scope.hostInvoke).toHaveBeenCalledOnce();
});

test('foreign-package and undeclared-source bootstrap fail before importing or running the extension', async () => {
  for (const bootstrap of [
    create(pb.PreferenceBootstrapSchema, { packageName: 'eu.kanade.other' }),
    create(pb.PreferenceBootstrapSchema, {
      packageName: 'eu.kanade.tachiyomi.extension.test',
      sources: [{ sourceId: '1' }],
    }),
  ]) {
    const importer = vi.fn();
    const driver = new TeaVMDriver(
      {},
      new VerifiedLoader('https://reader.example', vi.fn()),
      importer,
      'https://reader.example',
    );
    drivers.push(driver);
    await expect(
      driver.open(
        await manifest(),
        'test',
        new AbortController().signal,
        catalog,
        undefined,
        bootstrap,
      ),
    ).rejects.toMatchObject({ code: 'protocol_error' });
    expect(importer).not.toHaveBeenCalled();
  }
});

test('an external catalog claiming the official package and repo ID cannot approve account preferences', async () => {
  const build = {
    ...(await manifest()),
    repoId: 'keiyoushi',
    packageName: 'eu.kanade.tachiyomi.extension.zh.komiic',
  };
  const { driver, scope, context, call, configurations } = await setup(
    build,
    undefined,
    {
      catalogUrl: 'https://foreign.example/extensions/index.json',
      repoId: 'keiyoushi',
    },
  );
  expect(JSON.parse(configurations[0]!).syncRules).toBeUndefined();
  scope.hostInvoke = () =>
    scope.teaDone!(
      JSON.stringify({
        snapshotId: 'external-preferences',
        nodes: [],
        syncValues: [{ key: 'preferred_mirror', value: { text: '1' } }],
      }),
    );
  await expect(
    driver.invoke(
      create(pb.SourceCallSchema, {
        ...context,
        sourceId: call.sourceId,
        request: { case: 'getPreferences', value: {} },
      }),
      context,
    ),
  ).rejects.toThrow('not approved');
});
