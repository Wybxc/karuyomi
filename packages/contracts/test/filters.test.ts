import { create, toJson } from '@bufbuild/protobuf';
import { expect, test } from 'vitest';
import * as pb from '@karuyomi/protocol';
import {
  filterSnapshotSchema,
  filterSelectionSchema,
  sourceCallSchema,
  sourceResultFor,
  javaSourceInvocation,
  parseJavaSourcePayload,
  FILTER_SNAPSHOT_JSON_LIMIT,
} from '../src/index.js';

const nodes = [
  { name: 'Filters', header: {} },
  { name: '', separator: {} },
  { name: 'Title', text: { state: '' } },
  { name: 'Available', checkBox: { state: false } },
  { name: 'Status', triState: { state: 0 } },
  { name: 'Language', select: { options: ['日本語', 'English'], state: 0 } },
  { name: 'Sort', sort: { options: ['Updated', 'Name'], state: {} } },
  {
    name: 'Tags',
    group: { nodes: [{ name: 'Fantasy', checkBox: { state: true } }] },
  },
];
const snapshot = () => ({
  snapshotId: 'filters-1',
  nodes: structuredClone(nodes),
});
const selection = () => ({
  snapshotId: 'filters-1',
  updates: [
    { path: [2], text: '' },
    { path: [3], checkBox: false },
    { path: [4], triState: 0 },
    { path: [5], select: 0 },
    { path: [6], sort: {} },
    { path: [7, 0], checkBox: true },
  ],
});
const call = (request: Record<string, unknown>) => ({
  requestId: 'request-1',
  sourceId: '9007199254740993',
  generation: 'generation-1',
  ...request,
});

test('filter RPC keeps typed leaves, explicit false/zero/null sort and retained snapshot identity', () => {
  const described = filterSnapshotSchema.parse(snapshot());
  const get = sourceCallSchema.parse(
    call({ getFilters: { retainedSnapshotId: 'filters-1' } }),
  );
  expect(javaSourceInvocation(get)).toEqual({
    operation: 'getFilters',
    argsJson: '{"retainedSnapshotId":"filters-1"}',
  });
  expect(parseJavaSourcePayload(get, snapshot())).toEqual({
    case: 'filters',
    value: described,
  });
  expect(
    sourceResultFor(get, 'build-1', { case: 'filters', value: described })
      .payload.case,
  ).toBe('filters');
  expect(() =>
    sourceResultFor(get, 'build-1', {
      case: 'mangaPage',
      value: create(pb.MangaPageSchema),
    }),
  ).toThrow();
  const search = sourceCallSchema.parse(
    call({ search: { page: 1, query: '', filters: selection() } }),
  );
  expect(JSON.parse(javaSourceInvocation(search).argsJson)).toEqual({
    page: 1,
    filters: selection(),
  });
  const value = filterSelectionSchema.parse(selection());
  expect(value.updates[1]?.state).toEqual({ case: 'checkBox', value: false });
  expect(value.updates[2]?.state).toEqual({ case: 'triState', value: 0 });
  expect(value.updates[3]?.state).toEqual({ case: 'select', value: 0 });
  expect(value.updates[4]?.state.case).toBe('sort');
  const selectedSort = filterSelectionSchema.parse({
    snapshotId: 'filters-1',
    updates: [
      { path: [6], sort: { selection: { index: 0, ascending: false } } },
    ],
  });
  expect(toJson(pb.FilterSelectionSchema, selectedSort)).toEqual({
    snapshotId: 'filters-1',
    updates: [{ path: [6], sort: { selection: {} } }],
  });
  expect(
    filterSnapshotSchema.parse({ snapshotId: 'empty', nodes: [] }).nodes,
  ).toHaveLength(0);
  expect(
    javaSourceInvocation(sourceCallSchema.parse(call({ search: { page: 1 } })))
      .argsJson,
  ).toBe('{"page":1}');
});

test('filter descriptors reject unsupported nodes, invalid state/options and excessive tree or UTF-8 budgets', () => {
  const invalid = [
    { snapshotId: '', nodes },
    { snapshotId: 'x'.repeat(201), nodes },
    { snapshotId: 'f', nodes: [{ name: 'unknown' }] },
    { snapshotId: 'f', nodes: [{ name: '', future: {} }] },
    { snapshotId: 'f', nodes: [{ name: 'x'.repeat(513), header: {} }] },
    { snapshotId: 'f', nodes: [{ text: { state: 'x'.repeat(4097) } }] },
    { snapshotId: 'f', nodes: [{ triState: { state: 3 } }] },
    { snapshotId: 'f', nodes: [{ select: { options: [], state: 0 } }] },
    { snapshotId: 'f', nodes: [{ select: { options: ['one'], state: 1 } }] },
    { snapshotId: 'f', nodes: [{ select: { options: ['x'.repeat(513)] } }] },
    {
      snapshotId: 'f',
      nodes: [{ select: { options: Array(257).fill('one') } }],
    },
    { snapshotId: 'f', nodes: [{ sort: { options: ['one'] } }] },
    { snapshotId: 'f', nodes: [{ sort: { options: [], state: {} } }] },
    {
      snapshotId: 'f',
      nodes: [
        { sort: { options: ['one'], state: { selection: { index: 1 } } } },
      ],
    },
    {
      snapshotId: 'f',
      nodes: Array.from({ length: 257 }, () => ({ header: {} })),
    },
  ];
  for (const value of invalid)
    expect(() => filterSnapshotSchema.parse(value)).toThrow();
  let leaf: pb.FilterNode = create(pb.FilterNodeSchema, {
    kind: { case: 'text', value: { state: '' } },
  });
  for (let depth = 1; depth < 8; depth++)
    leaf = create(pb.FilterNodeSchema, {
      kind: { case: 'group', value: { nodes: [leaf] } },
    });
  expect(() =>
    filterSnapshotSchema.parse({
      snapshotId: 'f',
      nodes: [toJson(pb.FilterNodeSchema, leaf)],
    }),
  ).not.toThrow();
  expect(() =>
    filterSnapshotSchema.parse({
      snapshotId: 'f',
      nodes: [{ group: { nodes: [toJson(pb.FilterNodeSchema, leaf)] } }],
    }),
  ).toThrow();
  const large = {
    snapshotId: 'f',
    nodes: [{ select: { options: Array(256).fill('界'.repeat(512)) } }],
  };
  expect(
    new TextEncoder().encode(JSON.stringify(large)).length,
  ).toBeGreaterThan(FILTER_SNAPSHOT_JSON_LIMIT);
  expect(() => filterSnapshotSchema.parse(large)).toThrow();
});

test('filter selections reject ambiguous paths, missing states, invalid values and oversized Source arguments', () => {
  const invalid = [
    { snapshotId: '', updates: [] },
    { snapshotId: 'f', updates: [{ path: [], text: '' }] },
    { snapshotId: 'f', updates: [{ path: Array(9).fill(0), text: '' }] },
    { snapshotId: 'f', updates: [{ path: [256], text: '' }] },
    { snapshotId: 'f', updates: [{ path: [-1], text: '' }] },
    { snapshotId: 'f', updates: [{ path: [1] }] },
    {
      snapshotId: 'f',
      updates: [
        { path: [1], checkBox: false },
        { path: [1], text: '' },
      ],
    },
    { snapshotId: 'f', updates: [{ path: [1], text: '', checkBox: false }] },
    { snapshotId: 'f', updates: [{ path: [1], triState: 3 }] },
    { snapshotId: 'f', updates: [{ path: [1], select: 256 }] },
    {
      snapshotId: 'f',
      updates: [{ path: [1], sort: { selection: { index: 256 } } }],
    },
    { snapshotId: 'f', updates: [{ path: [1], text: 'x'.repeat(4097) }] },
    {
      snapshotId: 'f',
      updates: Array.from({ length: 257 }, (_, i) => ({ path: [i], text: '' })),
    },
    {
      snapshotId: 'f',
      updates: Array.from({ length: 33 }, (_, i) => ({
        path: [i],
        text: 'x'.repeat(4096),
      })),
    },
  ];
  for (const value of invalid)
    expect(() =>
      sourceCallSchema.parse(call({ search: { page: 1, filters: value } })),
    ).toThrow();
  for (const retainedSnapshotId of ['', 'x'.repeat(201)])
    expect(() =>
      sourceCallSchema.parse(call({ getFilters: { retainedSnapshotId } })),
    ).toThrow();
  expect(() =>
    sourceCallSchema.parse(
      call({
        search: {
          page: 1,
          query: 'x'.repeat(128 * 1024),
          filters: selection(),
        },
      }),
    ),
  ).toThrow();
});
