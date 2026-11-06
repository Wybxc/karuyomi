import { toJson } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { z } from 'zod';
import {
  businessSchemaVersion,
  BUSINESS_REQUEST_LIMIT,
} from './business-state.ts';
import {
  codec,
  parseMessage,
  requireCondition,
  requireFields,
} from './codec.ts';
import { validSourceId, validateCatalogReference } from './static-control.ts';
import {
  validatePreferencePackageName,
  validateSyncedPreferenceEntries,
  validatePreferenceSyncRuleSubset,
} from './source-preference-policy.ts';

export const SOURCE_PREFERENCES_PACKAGE_LIMIT = 64;
export const SOURCE_PREFERENCES_PACKAGE_BYTES = 64 * 1024;
export const SOURCE_PREFERENCES_RESPONSE_LIMIT = 128 * 1024;
const uuid = z.uuid();

export function sourcePreferenceEntriesJson(
  entries: readonly pb.PreferenceEntry[],
): string {
  return JSON.stringify(
    entries.map((entry) => toJson(pb.PreferenceEntrySchema, entry)),
  );
}

function uint32(value: number): void {
  requireCondition(
    Number.isInteger(value) && value >= 0 && value <= 0xffff_ffff,
    'Source preferences revision exceeds uint32',
  );
}

export function validateSourcePreferences(
  value: pb.SourcePreferences,
  rules?: readonly pb.PreferenceSyncRule[],
): void {
  validatePreferencePackageName(value.packageName);
  validSourceId(value.sourceId);
  uint32(value.revision);
  validateSyncedPreferenceEntries(
    value.packageName,
    value.sourceId,
    value.entries,
    rules,
  );
}

function validateEnvelope(value: {
  schemaVersion: number;
  accountRevision: number;
  error?: pb.BusinessStateError | undefined;
}): void {
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  uint32(value.accountRevision);
  if (value.error)
    requireCondition(
      Number.isInteger(value.error.code) &&
        value.error.code >= pb.BusinessStateErrorCode.INVALID_INPUT &&
        value.error.code <= pb.BusinessStateErrorCode.LIMIT_EXCEEDED &&
        value.error.message.length > 0 &&
        value.error.message.length <= 1024,
      'Invalid business state error',
    );
}

export const sourcePreferencesMutationSchema =
  codec<pb.SourcePreferencesMutation>((input) => {
    const value = parseMessage(
      pb.SourcePreferencesMutationSchema,
      input,
      BUSINESS_REQUEST_LIMIT,
    );
    requireCondition(
      value.schemaVersion === businessSchemaVersion,
      'Unsupported business state schema',
    );
    requireFields(value, ['catalog']);
    validateCatalogReference(value.catalog);
    uuid.parse(value.mutationId);
    uint32(value.expectedRevision);
    validateSyncedPreferenceEntries(
      value.packageName,
      value.sourceId,
      value.entries,
    );
    return value;
  });

export const sourcePreferencesResponseSchema =
  codec<pb.SourcePreferencesResponse>((input) => {
    const value = parseMessage(
      pb.SourcePreferencesResponseSchema,
      input,
      SOURCE_PREFERENCES_RESPONSE_LIMIT,
    );
    validateEnvelope(value);
    if (!value.error) requireFields(value, ['catalog']);
    if (value.catalog) validateCatalogReference(value.catalog);
    if (!value.error || value.packageName !== '')
      validatePreferenceSyncRuleSubset(value.packageName, value.syncRules);
    if (!value.error || value.packageName !== '')
      validatePreferencePackageName(value.packageName);
    requireCondition(
      value.sources.length <= SOURCE_PREFERENCES_PACKAGE_LIMIT,
      'Too many Source preferences in one package',
    );
    const identities = new Set<string>();
    let bytes = 0;
    for (const source of value.sources) {
      validateSourcePreferences(source, value.syncRules);
      requireCondition(
        source.packageName === value.packageName &&
          source.revision <= value.accountRevision &&
          !identities.has(source.sourceId),
        'Source preferences do not match their package or account revision',
      );
      identities.add(source.sourceId);
      bytes += new TextEncoder().encode(
        sourcePreferenceEntriesJson(source.entries),
      ).byteLength;
    }
    requireCondition(
      bytes <= SOURCE_PREFERENCES_PACKAGE_BYTES,
      'Source package preference entries exceed their size budget',
    );
    return value;
  });

export const sourcePreferencesMutationResponseSchema =
  codec<pb.SourcePreferencesMutationResponse>((input) => {
    const value = parseMessage(
      pb.SourcePreferencesMutationResponseSchema,
      input,
      SOURCE_PREFERENCES_RESPONSE_LIMIT,
    );
    validateEnvelope(value);
    if (!value.error) requireFields(value, ['catalog']);
    if (value.catalog) validateCatalogReference(value.catalog);
    if (value.preferences)
      validatePreferenceSyncRuleSubset(
        value.preferences.packageName,
        value.syncRules,
      );
    if (!value.error || value.mutationId !== '') uuid.parse(value.mutationId);
    if (!value.error) requireFields(value, ['preferences']);
    if (value.preferences) {
      validateSourcePreferences(value.preferences, value.syncRules);
      requireCondition(
        value.preferences.revision <= value.accountRevision,
        'Source preferences exceed account revision',
      );
    }
    return value;
  });
