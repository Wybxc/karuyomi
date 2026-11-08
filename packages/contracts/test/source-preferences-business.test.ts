import { create, toJson } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { expect, test } from 'vitest';
import {
  validatePreferenceSyncRules,
  validateSyncedPreferenceEntries,
} from '../src/preferences-control.ts';
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

const rule = (key: string, kind: pb.PreferenceValueKind, sourceId?: string) =>
  create(pb.PreferenceSyncRuleSchema, { key, kind, sourceId });
const komiicRules = [rule('preferred_mirror', pb.PreferenceValueKind.TEXT)];
const fireRules = [rule('pref_content_rating', pb.PreferenceValueKind.STRINGS)];

test('metadata rules check exact key, type, and optional Source scope', () => {
  const rules = [
    rule('display_mode', pb.PreferenceValueKind.TEXT, '123'),
    rule('show_extra', pb.PreferenceValueKind.BOOLEAN),
  ];
  const mode = entry('display_mode', { case: 'text', value: '' });
  const extra = entry('show_extra', { case: 'boolean', value: false });
  expect(() =>
    validateSyncedPreferenceEntries(komiic, '123', [mode, extra], rules),
  ).not.toThrow();
  expect(() =>
    validateSyncedPreferenceEntries(komiic, '124', [mode], rules),
  ).toThrow();
  expect(() =>
    validateSyncedPreferenceEntries(
      komiic,
      '123',
      [entry('show_extra', { case: 'text', value: 'false' })],
      rules,
    ),
  ).toThrow();
  expect(() => validatePreferenceSyncRules([...rules, rules[0]!])).toThrow();
});

test('business mutation parses only bounded typed entries and leaves policy to the current metadata', () => {
  expect(
    sourcePreferencesMutationSchema.parse({
      ...base,
      packageName: 'org.example.extension',
    }).packageName,
  ).toBe('org.example.extension');
  for (const entries of [
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
    { packageName: 42 },
    { packageName: 'x'.repeat(201) },
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
      syncRules: fireRules.map((rule) =>
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
      syncRules: fireRules.map((rule) =>
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
    syncRules: komiicRules.map((rule) =>
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
