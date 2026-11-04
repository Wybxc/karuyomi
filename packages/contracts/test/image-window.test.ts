import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { expect, test } from 'vitest';
import {
  encodeControlResponse,
  imagePageSchema,
  imageTileHeaderSchema,
  imageTileSchema,
  imageWindowSnapshotSchema,
  parseControlRequest,
  parseControlResponse,
} from '../src/index.js';

const generation = 'generation';
const page = {
  pageId: 'page',
  generation,
  encoded: {
    resourceId: 'encoded',
    generation,
    mimeType: 'image/jpeg',
    byteLength: 1000,
    rawWidth: 1081,
    rawHeight: 40001,
    orientation: 8,
  },
};
const header = {
  width: 541,
  height: 20001,
  sourceWidth: 1081,
  sourceHeight: 40001,
  denominator: 2,
};
const tile = {
  leaseId: 'tile',
  sessionId: 'codec',
  index: 78,
  sourceRect: { x: 0, y: 39936, width: 1081, height: 65 },
  denominator: 2,
  provisional: false,
  resource: {
    resourceId: 'tile',
    generation,
    mimeType: 'image/png',
    byteLength: 65536,
    width: 541,
    height: 33,
    url: 'blob:https://reader.invalid/tile',
  },
};
const snapshot = {
  pageId: 'page',
  generation,
  windowId: 'window',
  revision: 12,
  state: 'IMAGE_WINDOW_STATE_COMPLETE',
  header,
  tiles: [tile],
  invalidatedLeaseIds: ['old-tile'],
};
const error = {
  code: 'RUNTIME_ERROR_CODE_SOURCE_ERROR',
  message: 'Invalid image tail',
};

test('formal image-page controls carry raw windows and bounded polling identities', () => {
  for (const [command, value] of [
    ['openImagePage', { resourceId: 'encoded', generation }],
    [
      'requestImageWindow',
      {
        pageId: 'page',
        generation,
        windowId: 'window',
        sourceY: 39936,
        sourceEndY: 40001,
        denominator: 2,
      },
    ],
    [
      'waitImageWindow',
      {
        pageId: 'page',
        generation,
        windowId: 'window',
        afterRevision: 12,
        timeoutMs: 25000,
      },
    ],
    ['releaseImageTile', { leaseId: 'tile', generation }],
    ['closeImagePage', { pageId: 'page', generation }],
  ])
    expect(
      parseControlRequest({ requestId: 'control', [String(command)]: value })
        .command.case,
    ).toBe(command);
  const window = {
    pageId: 'page',
    generation,
    windowId: 'window',
    sourceY: 0,
    sourceEndY: 100,
    denominator: 1,
  };
  for (const change of [
    { pageId: '' },
    { generation: '' },
    { windowId: '' },
    { sourceY: 100 },
    { sourceEndY: 100001 },
    { sourceY: -1 },
    { denominator: 3 },
    { denominator: 1.5 },
  ])
    expect(() =>
      parseControlRequest({
        requestId: 'control',
        requestImageWindow: { ...window, ...change },
      }),
    ).toThrow();
  for (const timeoutMs of [0, 25001, -1, 1.5])
    expect(() =>
      parseControlRequest({
        requestId: 'control',
        waitImageWindow: {
          pageId: 'page',
          generation,
          windowId: 'window',
          afterRevision: 12,
          timeoutMs,
        },
      }),
    ).toThrow();
  expect(() =>
    parseControlRequest({
      requestId: 'control',
      releaseImageTile: { resourceId: 'tile', generation },
    }),
  ).toThrow();
});

test('page ownership requires the Source descriptor and its original generation', () => {
  expect(imagePageSchema.parse(page).encoded.orientation).toBe(8);
  expect(
    parseControlResponse({ requestId: 'control', imagePage: page }).result.case,
  ).toBe('imagePage');
  for (const invalid of [
    { ...page, encoded: undefined },
    { ...page, generation: 'foreign' },
    { ...page, encoded: { ...page.encoded, url: 'blob:forbidden' } },
  ])
    expect(() => imagePageSchema.parse(invalid)).toThrow();
});

test('tile metadata preserves odd JPEG downsampling and bounds each display surface', () => {
  expect(imageTileHeaderSchema.parse(header)).toEqual(header);
  expect(imageTileSchema.parse(tile).sourceRect).toEqual(tile.sourceRect);
  expect(
    parseControlResponse({ requestId: 'control', imageWindow: snapshot }).result
      .case,
  ).toBe('imageWindow');
  for (const change of [
    { denominator: 3 },
    { width: 540 },
    { height: 20000 },
    { sourceWidth: 4097 },
    { sourceHeight: 100001 },
  ])
    expect(() =>
      imageTileHeaderSchema.parse({ ...header, ...change }),
    ).toThrow();
  for (const resource of [
    { ...tile.resource, resourceId: 'foreign' },
    { ...tile.resource, mimeType: 'image/jpeg' },
    { ...tile.resource, url: 'https://raw.invalid/image' },
    { ...tile.resource, byteLength: 8 * 1024 * 1024 + 1 },
    { ...tile.resource, height: 257 },
    { ...tile.resource, width: 540 },
  ])
    expect(() => imageTileSchema.parse({ ...tile, resource })).toThrow();
  for (const change of [
    { index: 77 },
    { sourceRect: { ...tile.sourceRect, x: 1 } },
    { resource: undefined },
    { sourceRect: undefined },
  ])
    expect(() => imageTileSchema.parse({ ...tile, ...change })).toThrow();
});

test('window envelopes bind tile generations, raw bounds, indices and invalidation leases', () => {
  for (const invalid of [
    { ...snapshot, generation: 'foreign' },
    { ...snapshot, header: undefined },
    { ...snapshot, header: { ...header, sourceHeight: 40002, height: 20001 } },
    {
      ...snapshot,
      tiles: [
        tile,
        {
          ...tile,
          leaseId: 'second',
          resource: { ...tile.resource, resourceId: 'second' },
        },
      ],
    },
    { ...snapshot, invalidatedLeaseIds: ['tile'] },
    { ...snapshot, invalidatedLeaseIds: ['old', 'old'] },
    { ...snapshot, tiles: [{ ...tile, denominator: 1 }] },
  ])
    expect(() => imageWindowSnapshotSchema.parse(invalid)).toThrow();
});

test('window state distinguishes provisional display from the real terminal and tail failure', () => {
  expect(
    imageWindowSnapshotSchema.parse({
      ...snapshot,
      state: 'IMAGE_WINDOW_STATE_PENDING',
      tiles: [{ ...tile, provisional: true }],
    }).tiles[0]?.provisional,
  ).toBe(true);
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...snapshot,
      tiles: [{ ...tile, provisional: true }],
    }),
  ).toThrow();
  expect(() =>
    imageWindowSnapshotSchema.parse({ ...snapshot, error }),
  ).toThrow();
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...snapshot,
      state: 'IMAGE_WINDOW_STATE_FAILED',
    }),
  ).toThrow();
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...snapshot,
      state: 'IMAGE_WINDOW_STATE_UNSPECIFIED',
    }),
  ).toThrow();
  const failed = imageWindowSnapshotSchema.parse({
    ...snapshot,
    state: 'IMAGE_WINDOW_STATE_FAILED',
    tiles: [],
    invalidatedLeaseIds: ['tile'],
    error,
  });
  expect(failed.invalidatedLeaseIds).toEqual(['tile']);
  expect(failed.error?.code).toBe(pb.RuntimeErrorCode.SOURCE_ERROR);
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...snapshot,
      state: 'IMAGE_WINDOW_STATE_FAILED',
      tiles: [],
      error: { ...error, code: 'RUNTIME_ERROR_CODE_UNSPECIFIED' },
    }),
  ).toThrow();
});

test('a window accepts the exact display and PNG-cache budgets and rejects aggregate overflow', () => {
  const tiles = Array.from({ length: 64 }, (_, index) => ({
    ...tile,
    leaseId: 'tile-' + index,
    index,
    denominator: 1,
    sourceRect: { x: 0, y: index * 256, width: 2048, height: 256 },
    resource: {
      ...tile.resource,
      resourceId: 'tile-' + index,
      width: 2048,
      height: 256,
      byteLength: 256 * 1024,
    },
  }));
  const full = {
    ...snapshot,
    header: {
      width: 2048,
      height: 16384,
      sourceWidth: 2048,
      sourceHeight: 16384,
      denominator: 1,
    },
    tiles,
    invalidatedLeaseIds: [],
  };
  expect(imageWindowSnapshotSchema.parse(full).tiles).toHaveLength(64);
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...full,
      invalidatedLeaseIds: ['retiring'],
    }),
  ).toThrow();
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...full,
      tiles: tiles.map((value) => ({
        ...value,
        resource: {
          ...value.resource,
          byteLength: value.resource.byteLength + 1,
        },
      })),
    }),
  ).toThrow();
  expect(() =>
    imageWindowSnapshotSchema.parse({
      ...full,
      header: { ...full.header, width: 2049, sourceWidth: 2049 },
      tiles: tiles.map((value) => ({
        ...value,
        sourceRect: { ...value.sourceRect, width: 2049 },
        resource: { ...value.resource, width: 2049 },
      })),
    }),
  ).toThrow();
});

test('generated messages cannot bypass semantic validation on encode', () => {
  const response = create(pb.ControlResponseSchema, {
    requestId: 'control',
    result: {
      case: 'imageWindow',
      value: create(pb.ImageWindowSnapshotSchema, {
        pageId: 'page',
        generation,
        windowId: 'window',
        state: pb.ImageWindowState.COMPLETE,
      }),
    },
  });
  expect(() => encodeControlResponse(response)).toThrow();
});
