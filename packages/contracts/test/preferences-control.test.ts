import { create, toJson } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { expect, test } from 'vitest';
import {
  validatePreferenceBootstrap,
  preferenceSnapshotSchema,
  preferenceEditResultSchema,
  sourceCallSchema,
  javaSourceInvocation,
  parseJavaSourcePayload,
  sourceResultFor,
} from '../src/index.ts';

const packageName = 'eu.kanade.tachiyomi.extension.test';
const scope = 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION';
const snapshot = (extra: Record<string, unknown> = {}) => ({
  snapshotId: 'prefs-1',
  nodes: [],
  ...extra,
});
const call = (request: Record<string, unknown>) =>
  sourceCallSchema.parse({
    requestId: 'preferences-call',
    generation: 'generation-1',
    sourceId: '9223372036854775806',
    ...request,
  });

test('preferences preserve Android int/long/float widths, false, empty text/set and missing text presence', () => {
  const value = preferenceSnapshotSchema.parse(
    snapshot({
      sessionValues: [
        { key: 'flag', value: { boolean: false } },
        { key: 'empty', value: { text: '' } },
        { key: 'int', value: { integer: -2147483648 } },
        { key: 'long', value: { longInteger: '9223372036854775807' } },
        { key: 'float', value: { decimal: 1.5 } },
        { key: 'set', value: { strings: {} } },
      ],
      nodes: [
        {
          key: 'flag',
          syncScope: scope,
          defaultValue: { boolean: false },
          toggle: {},
        },
        { key: 'secret', syncScope: scope, text: { secret: true } },
        {
          key: 'empty',
          syncScope: scope,
          text: {
            value: '',
            hint: 'https://example.org',
            selectAllOnOpen: true,
          },
        },
      ],
    }),
  );
  expect(value.sessionValues.map((entry) => entry.value?.value)).toEqual([
    { case: 'boolean', value: false },
    { case: 'text', value: '' },
    { case: 'integer', value: -2147483648 },
    { case: 'longInteger', value: 9223372036854775807n },
    { case: 'decimal', value: 1.5 },
    { case: 'strings', value: create(pb.PreferenceStringSetSchema) },
  ]);
  const absent = value.nodes[1]?.kind,
    empty = value.nodes[2]?.kind;
  if (absent?.case !== 'text' || empty?.case !== 'text')
    throw new Error('Expected text nodes');
  expect(absent.value.value).toBeUndefined();
  expect(empty.value.value).toBe('');
  expect(empty.value.hint).toBe('https://example.org');
  expect(empty.value.selectAllOnOpen).toBe(true);
  for (const invalid of [
    { integer: 2147483648 },
    { integer: 1.5 },
    { longInteger: '9223372036854775808' },
    { decimal: 'NaN' },
    { strings: { values: ['same', 'same'] } },
    {},
  ])
    expect(() =>
      preferenceSnapshotSchema.parse(
        snapshot({ sessionValues: [{ key: 'invalid', value: invalid }] }),
      ),
    ).toThrow();
});

test('preference partitions, secret scope, defaults and recursive descriptions are validated before use', () => {
  const group = (nodes: unknown[]) => ({ syncScope: scope, group: { nodes } });
  const leaf = { key: 'flag', syncScope: scope, toggle: {} };
  const tree = (depth: number) =>
    Array.from({ length: depth - 1 }).reduce<unknown[]>(
      (nodes) => [group(nodes)],
      [leaf],
    );
  expect(() =>
    preferenceSnapshotSchema.parse(snapshot({ nodes: tree(8) })),
  ).not.toThrow();
  expect(() =>
    preferenceSnapshotSchema.parse(snapshot({ nodes: tree(9) })),
  ).toThrow();
  expect(() =>
    preferenceSnapshotSchema.parse(
      snapshot({ nodes: Array.from({ length: 257 }, () => leaf) }),
    ),
  ).toThrow();
  expect(() =>
    preferenceSnapshotSchema.parse(
      snapshot({
        syncValues: [{ key: 'same', value: { boolean: false } }],
        sessionValues: [{ key: 'same', value: { text: 'secret' } }],
      }),
    ),
  ).toThrow();
  expect(() =>
    preferenceSnapshotSchema.parse(
      snapshot({
        nodes: [
          {
            key: 'secret',
            syncScope: 'PREFERENCE_SYNC_SCOPE_ACCOUNT',
            text: { secret: true },
          },
        ],
      }),
    ),
  ).toThrow();
  expect(() =>
    preferenceSnapshotSchema.parse(
      snapshot({ nodes: [{ ...leaf, defaultValue: { text: 'false' } }] }),
    ),
  ).toThrow();
  for (const invalidText of [
    { secret: true, hint: 'a secret hint' },
    { hint: '界'.repeat(171) },
  ]) {
    expect(() =>
      preferenceSnapshotSchema.parse(
        snapshot({
          nodes: [{ key: 'text', syncScope: scope, text: invalidText }],
        }),
      ),
    ).toThrow('Preference input hint');
  }
  expect(() => preferenceEditResultSchema.parse({ accepted: true })).toThrow();
});

test('bootstrap supports more than 512 small entries while enforcing per-source, package UTF-8 and scope budgets', () => {
  const small = create(pb.PreferenceBootstrapSchema, {
    packageName,
    sources: Array.from({ length: 8 }, (_, source) => ({
      sourceId: String(source),
      entries: Array.from({ length: 100 }, (_, key) => ({
        key: String(key),
        value: { value: { case: 'boolean', value: false } },
      })),
    })),
  });
  expect(() => validatePreferenceBootstrap(small)).not.toThrow();
  const value = create(pb.PreferenceBootstrapSchema, {
    packageName,
    sources: [
      {
        sourceId: '1',
        entries: [
          {
            key: 'set',
            value: {
              value: {
                case: 'strings',
                value: {
                  values: Array.from(
                    { length: 7 },
                    (_, index) => String(index) + '字'.repeat(1199),
                  ),
                },
              },
            },
          },
        ],
      },
    ],
  });
  expect(() => validatePreferenceBootstrap(value)).not.toThrow();
  value.sources.push(
    create(pb.SourcePreferenceValuesSchema, {
      ...value.sources[0],
      sourceId: '2',
    }),
  );
  expect(() => validatePreferenceBootstrap(value)).not.toThrow();
  value.sources.push(
    create(pb.SourcePreferenceValuesSchema, {
      ...value.sources[0],
      sourceId: '3',
    }),
  );
  expect(() => validatePreferenceBootstrap(value)).toThrow();
  for (const invalid of [
    create(pb.PreferenceBootstrapSchema, { packageName: '' }),
    create(pb.PreferenceBootstrapSchema, { packageName: 'a'.repeat(201) }),
    create(pb.PreferenceBootstrapSchema, {
      packageName,
      sources: [{ sourceId: '1' }, { sourceId: '1' }],
    }),
    create(pb.PreferenceBootstrapSchema, {
      packageName,
      sources: Array.from({ length: 65 }, (_, id) => ({
        sourceId: String(id),
      })),
    }),
  ])
    expect(() => validatePreferenceBootstrap(invalid)).toThrow();
});

test('get/edit RPC keeps oneof commands and long integer ProtoJSON, and correlates only its matching response', () => {
  const get = call({ getPreferences: {} });
  expect(javaSourceInvocation(get)).toEqual({
    operation: 'getPreferences',
    argsJson: '{}',
  });
  expect(parseJavaSourcePayload(get, snapshot()).case).toBe('preferences');
  const editing = call({
    editPreference: {
      snapshotId: 'prefs-1',
      path: [0, 1],
      change: { longInteger: '9223372036854775807' },
    },
  });
  expect(JSON.parse(javaSourceInvocation(editing).argsJson)).toEqual({
    snapshotId: 'prefs-1',
    path: [0, 1],
    change: { longInteger: '9223372036854775807' },
  });
  const click = call({
    editPreference: { snapshotId: 'prefs-1', path: [0], click: {} },
  });
  expect(JSON.parse(javaSourceInvocation(click).argsJson)).toEqual({
    snapshotId: 'prefs-1',
    path: [0],
    click: {},
  });
  const result = parseJavaSourcePayload(editing, {
    accepted: false,
    snapshot: snapshot(),
  });
  expect(
    toJson(pb.SourceResultSchema, sourceResultFor(editing, 'build-1', result)),
  ).toMatchObject({ preferenceEdit: { snapshot: { snapshotId: 'prefs-1' } } });
  expect(() => sourceResultFor(get, 'build-1', result)).toThrow();
  for (const editPreference of [
    { snapshotId: 'prefs-1', path: [], click: {} },
    { snapshotId: 'prefs-1', path: [256], click: {} },
    { snapshotId: 'prefs-1', path: [0] },
    { snapshotId: 'prefs-1', path: [0], change: { boolean: false }, click: {} },
  ])
    expect(() => call({ editPreference })).toThrow();
});
