import { create, toJson } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { expect, test } from 'vitest';
import {
  preferenceSyncRules,
  validateSyncedPreferenceEntries,
} from '../src/source-preference-policy.ts';
import {
  sourcePreferencesMutationSchema,
  sourcePreferencesResponseSchema,
  sourcePreferencesMutationResponseSchema,
} from '../src/source-preferences-business.ts';

const komiic = 'eu.kanade.tachiyomi.extension.zh.komiic';
const fire = 'eu.kanade.tachiyomi.extension.all.mangafire';
const katana = 'eu.kanade.tachiyomi.extension.en.mangakatana';
const sourceId = '792932060924485302';
const catalog = {
  catalogUrl: 'https://read.example.com/extensions/index.json',
  repoId: 'keiyoushi',
};
const base = {
  catalog,
  schemaVersion: 1,
  mutationId: 'a281b912-5bdb-4640-b7bc-d33bd721f8c4',
  packageName: komiic,
  sourceId,
  expectedRevision: 0,
};
const entry = (key: string, value: pb.PreferenceValue['value']) =>
  create(pb.PreferenceEntrySchema, { key, value: { value } });
const jsonEntries = (entries: pb.PreferenceEntry[]) =>
  entries.map((value) => toJson(pb.PreferenceEntrySchema, value));

test('reviewed package policy preserves original keys and alias writes, and returns independent rules', () => {
  const rules = preferenceSyncRules(fire);
  expect(rules.map((rule) => rule.key)).toEqual([
    'pref_content_rating',
    'show_as_volumes',
    'merge_chapters',
    'prefer_official',
    'solve_captcha',
  ]);
  rules[0]!.key = 'token';
  expect(preferenceSyncRules(fire)[0]?.key).toBe('pref_content_rating');
  expect(preferenceSyncRules('eu.kanade.extension.unknown')).toEqual([]);
  expect(preferenceSyncRules('eu.kanade.extension.toString')).toEqual([]);
  expect(() =>
    validateSyncedPreferenceEntries(katana, sourceId, [
      entry('server_preference', { case: 'text', value: '' }),
      entry('SERVER_PREFERENCE', { case: 'text', value: 'mk' }),
    ]),
  ).not.toThrow();
  expect(() =>
    validateSyncedPreferenceEntries(fire, sourceId, [
      entry('pref_content_rating', {
        case: 'strings',
        value: create(pb.PreferenceStringSetSchema),
      }),
      entry('merge_chapters', { case: 'boolean', value: false }),
    ]),
  ).not.toThrow();
});

test('business boundary rejects unapproved secrets, wrong kinds, duplicate storage keys and malformed identities', () => {
  for (const entries of [
    [{ key: 'token', value: { text: 'secret' } }],
    [{ key: 'CHAPTER_FILTER', value: { boolean: false } }],
    [{ key: 'CHAPTER_FILTER', value: { longInteger: '9223372036854775807' } }],
    [
      { key: 'CHAPTER_FILTER', value: { text: 'all' } },
      { key: 'CHAPTER_FILTER', value: { text: 'book' } },
    ],
    [{ key: 'CHAPTER_FILTER', value: {} }],
    [{ key: 'CHAPTER_FILTER', value: { text: 'all' }, syncScope: 'ACCOUNT' }],
  ])
    expect(() =>
      sourcePreferencesMutationSchema.parse({ ...base, entries }),
    ).toThrow();
  for (const change of [
    { packageName: '' },
    { packageName: 'unknown' },
    { packageName: 'eu.kanade.' },
    { packageName: 'eu.kanade.' + 'x'.repeat(191) },
    { sourceId: '9223372036854775808' },
    { expectedRevision: -1 },
    { expectedRevision: 0.5 },
    { schemaVersion: 2 },
  ])
    expect(() =>
      sourcePreferencesMutationSchema.parse({ ...base, ...change }),
    ).toThrow();
});

test('full replacement keeps false and empty values while source and package JSON budgets stay bounded', () => {
  expect(
    sourcePreferencesMutationSchema.parse({ ...base, entries: [] }).entries,
  ).toEqual([]);
  const entries = [
    entry('pref_content_rating', {
      case: 'strings',
      value: create(pb.PreferenceStringSetSchema, {
        values: Array.from(
          { length: 9 },
          (_, index) => String(index) + 'x'.repeat(4095),
        ),
      }),
    }),
  ];
  expect(() =>
    sourcePreferencesMutationSchema.parse({
      ...base,
      packageName: fire,
      entries: jsonEntries(entries),
    }),
  ).toThrow();
  const legal = [
    entry('pref_content_rating', {
      case: 'strings',
      value: create(pb.PreferenceStringSetSchema, {
        values: Array.from(
          { length: 7 },
          (_, index) => String(index) + 'x'.repeat(3899),
        ),
      }),
    }),
  ];
  const source = {
    packageName: fire,
    sourceId,
    revision: 1,
    entries: jsonEntries(legal),
  };
  expect(() =>
    sourcePreferencesResponseSchema.parse({
      schemaVersion: 1,
      catalog,
      syncRules: preferenceSyncRules(fire).map((rule) =>
        toJson(pb.PreferenceSyncRuleSchema, rule),
      ),
      accountRevision: 1,
      packageName: fire,
      sources: [source, { ...source, sourceId: '2' }],
    }),
  ).not.toThrow();
  expect(() =>
    sourcePreferencesResponseSchema.parse({
      schemaVersion: 1,
      catalog,
      syncRules: preferenceSyncRules(fire).map((rule) =>
        toJson(pb.PreferenceSyncRuleSchema, rule),
      ),
      accountRevision: 1,
      packageName: fire,
      sources: [
        source,
        { ...source, sourceId: '2' },
        { ...source, sourceId: '3' },
      ],
    }),
  ).toThrow();
});

test('package and mutation responses enforce package identity, unique scopes and committed revisions', () => {
  const source = {
    packageName: komiic,
    sourceId,
    revision: 1,
    entries: [{ key: 'preferred_mirror', value: { text: '1' } }],
  };
  const response = {
    catalog,
    syncRules: preferenceSyncRules(komiic).map((rule) =>
      toJson(pb.PreferenceSyncRuleSchema, rule),
    ),
    schemaVersion: 1,
    accountRevision: 1,
    packageName: komiic,
    sources: [source],
  };
  expect(
    sourcePreferencesResponseSchema.parse(response).sources[0]?.sourceId,
  ).toBe(sourceId);
  for (const sources of [
    [source, source],
    [{ ...source, packageName: katana }],
    [{ ...source, revision: 2 }],
    Array.from({ length: 65 }, (_, index) => ({
      ...source,
      sourceId: String(index),
    })),
  ])
    expect(() =>
      sourcePreferencesResponseSchema.parse({ ...response, sources }),
    ).toThrow();
  expect(() =>
    sourcePreferencesMutationResponseSchema.parse({
      schemaVersion: 1,
      mutationId: base.mutationId,
      accountRevision: 1,
    }),
  ).toThrow();
  expect(() =>
    sourcePreferencesMutationResponseSchema.parse({
      schemaVersion: 1,
      mutationId: base.mutationId,
      accountRevision: 0,
      preferences: source,
    }),
  ).toThrow();
});
