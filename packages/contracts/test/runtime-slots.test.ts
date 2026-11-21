import { describe, expect, test } from 'vitest';
import { parseControlRequest, parseControlResponse } from '../src/index.ts';

const search = {
  requestId: 'source-search',
  sourceId: '9223372036854775806',
  generation: 'search-generation',
  search: { page: 1, query: 'query' },
};

describe('explicit runtime slot boundary', () => {
  for (const slotId of [
    undefined,
    0,
    3,
    -1,
    'RUNTIME_SLOT_UNSPECIFIED',
    'invented',
  ]) {
    test(`rejects missing or invalid slot ${String(slotId)} for both directions`, () => {
      expect(() =>
        parseControlRequest({ requestId: 'control', slotId, ready: {} }),
      ).toThrow();
      expect(() =>
        parseControlResponse({
          requestId: 'control',
          slotId,
          completed: { completed: true },
        }),
      ).toThrow();
    });
  }

  for (const slotId of ['RUNTIME_SLOT_FOREGROUND', 'RUNTIME_SLOT_SEARCH']) {
    test(`preserves ${slotId} through generated parsing`, () => {
      expect(
        parseControlRequest({ requestId: 'control', slotId, invoke: search })
          .slotId,
      ).toBe(slotId === 'RUNTIME_SLOT_FOREGROUND' ? 1 : 2);
      expect(
        parseControlResponse({
          requestId: 'control',
          slotId,
          completed: { completed: true },
        }).slotId,
      ).toBe(slotId === 'RUNTIME_SLOT_FOREGROUND' ? 1 : 2);
    });
  }

  test('search slot accepts search and thumbnail calls with a bounded lifecycle', () => {
    for (const command of [
      'fetchApi',
      'prepareBuild',
      'cancelPreparation',
      'extensionCache',
      'forgetExtensionArtifact',
      'closePageSession',
    ]) {
      expect(() =>
        parseControlRequest({
          requestId: 'control',
          slotId: 'RUNTIME_SLOT_SEARCH',
          [command]: {},
        }),
      ).toThrow(/search slot/);
    }
    const { search: _query, ...identity } = search;
    for (const operation of [
      'popular',
      'latest',
      'details',
      'chapters',
      'pages',
      'getFilters',
      'getPreferences',
      'setPreferences',
    ]) {
      expect(() =>
        parseControlRequest({
          requestId: 'control',
          slotId: 'RUNTIME_SLOT_SEARCH',
          invoke: { ...identity, [operation]: {} },
        }),
      ).toThrow();
    }
    const slotId = 'RUNTIME_SLOT_SEARCH';
    const thumbnail = {
      requestId: search.requestId,
      sourceId: search.sourceId,
      generation: search.generation,
      thumbnailUrl: 'https://source.example/cover.webp',
    };
    const request = { requestId: 'control', slotId };
    expect(
      parseControlRequest({ ...request, acquireImage: thumbnail }).command.case,
    ).toBe('acquireImage');
    expect(() =>
      parseControlRequest({
        ...request,
        acquireImage: {
          ...identity,
          pageSessionId: 'chapter',
          pageKey: 'page',
        },
      }),
    ).toThrow(/search slot/);
    expect(() =>
      parseControlRequest({
        ...request,
        acquireImage: { ...thumbnail, pageKey: 'page' },
      }),
    ).toThrow(/thumbnail request/);
    expect(() =>
      parseControlRequest({
        ...request,
        acquireImage: {
          ...thumbnail,
          thumbnailUrl: 'https://user@source.example/cover.webp',
        },
      }),
    ).toThrow(/thumbnail request/);
    expect(
      parseControlResponse({ ...request, released: { released: true } }).result
        .case,
    ).toBe('released');
    for (const result of ['api', 'preparedBuild', 'extensionCache']) {
      expect(() =>
        parseControlResponse({
          requestId: 'control',
          slotId: 'RUNTIME_SLOT_SEARCH',
          [result]: {},
        }),
      ).toThrow(/search slot/);
    }
  });
});
