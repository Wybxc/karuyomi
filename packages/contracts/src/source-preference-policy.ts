import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { requireCondition } from './codec.ts';
import { validatePreferenceEntries } from './preferences-control.ts';
import { validSourceId, validateCatalogReference } from './static-control.ts';

type Rule = { key: string; kind: pb.PreferenceValueKind; sourceId?: string };

// Reviewed against the fixed Keiyoushi sources. This is the sole sync policy;
// Source descriptions and password/inputType flags cannot approve new keys.
const policies: Readonly<Record<string, readonly Rule[]>> = {
  'eu.kanade.tachiyomi.extension.zh.komiic': [
    { key: 'preferred_mirror', kind: pb.PreferenceValueKind.TEXT },
    { key: 'CHAPTER_FILTER', kind: pb.PreferenceValueKind.TEXT },
  ],
  'eu.kanade.tachiyomi.extension.all.mangafire': [
    { key: 'pref_content_rating', kind: pb.PreferenceValueKind.STRINGS },
    { key: 'show_as_volumes', kind: pb.PreferenceValueKind.BOOLEAN },
    { key: 'merge_chapters', kind: pb.PreferenceValueKind.BOOLEAN },
    { key: 'prefer_official', kind: pb.PreferenceValueKind.BOOLEAN },
    { key: 'solve_captcha', kind: pb.PreferenceValueKind.BOOLEAN },
  ],
  'eu.kanade.tachiyomi.extension.en.asurascans': [
    { key: 'pref_hide_premium_chapters', kind: pb.PreferenceValueKind.BOOLEAN },
  ],
  'eu.kanade.tachiyomi.extension.en.mangakatana': [
    // The listener writes SERVER_PREFERENCE; default persistence also writes
    // the UI key. Preserve both actual storage keys, including empty strings.
    { key: 'server_preference', kind: pb.PreferenceValueKind.TEXT },
    { key: 'SERVER_PREFERENCE', kind: pb.PreferenceValueKind.TEXT },
  ],
};

export function validatePreferencePackageName(packageName: string): void {
  requireCondition(
    /^eu\.kanade\.[A-Za-z0-9_.]+$/.test(packageName) &&
      packageName.length <= 200,
    'Invalid preference package identity',
  );
}

export function preferenceSyncRules(
  packageName: string,
): pb.PreferenceSyncRule[] {
  validatePreferencePackageName(packageName);
  const rules = Object.hasOwn(policies, packageName)
    ? policies[packageName]
    : undefined;
  return (rules ?? []).map((rule) => create(pb.PreferenceSyncRuleSchema, rule));
}

export function preferenceSyncRulesForCatalog(
  packageName: string,
  catalog: { catalogUrl: string; repoId: string },
  appOrigin: string,
): pb.PreferenceSyncRule[] {
  validateCatalogReference(catalog);
  return catalog.repoId === 'keiyoushi' &&
    catalog.catalogUrl === `${new URL(appOrigin).origin}/extensions/index.json`
    ? preferenceSyncRules(packageName)
    : [];
}
export function validatePreferenceSyncRuleSubset(
  packageName: string,
  rules: readonly pb.PreferenceSyncRule[],
): void {
  const reviewed = preferenceSyncRules(packageName);
  const keys = new Set<string>();
  for (const rule of rules) {
    const key = JSON.stringify([rule.key, rule.sourceId ?? null]);
    requireCondition(
      !keys.has(key) &&
        reviewed.some(
          (candidate) =>
            candidate.key === rule.key &&
            candidate.kind === rule.kind &&
            candidate.sourceId === rule.sourceId,
        ),
      'Preference sync rules exceed reviewed policy',
    );
    keys.add(key);
  }
}

function valueKind(value: pb.PreferenceValue): pb.PreferenceValueKind {
  switch (value.value.case) {
    case 'boolean':
      return pb.PreferenceValueKind.BOOLEAN;
    case 'text':
      return pb.PreferenceValueKind.TEXT;
    case 'integer':
      return pb.PreferenceValueKind.INTEGER;
    case 'longInteger':
      return pb.PreferenceValueKind.LONG_INTEGER;
    case 'decimal':
      return pb.PreferenceValueKind.DECIMAL;
    case 'strings':
      return pb.PreferenceValueKind.STRINGS;
    default:
      throw new Error('A typed preference value is required');
  }
}

export function validateSyncedPreferenceEntries(
  packageName: string,
  sourceId: string,
  entries: readonly pb.PreferenceEntry[],
  rules: readonly pb.PreferenceSyncRule[] = preferenceSyncRules(packageName),
): void {
  validatePreferenceSyncRuleSubset(packageName, rules);
  validSourceId(sourceId);
  validatePreferenceEntries(entries);
  for (const entry of entries) {
    const rule = rules.find(
      (candidate) =>
        candidate.key === entry.key &&
        (candidate.sourceId === undefined || candidate.sourceId === sourceId),
    );
    requireCondition(
      rule && entry.value && rule.kind === valueKind(entry.value),
      'Source preference key or type is not approved for account sync',
    );
  }
}
