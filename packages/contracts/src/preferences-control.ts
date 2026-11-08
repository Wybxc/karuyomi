import * as pb from '@karuyomi/protocol';
import {
  codec,
  jsonText,
  messageJson,
  parseMessage,
  requireCondition,
  SOURCE_ARGUMENT_LIMIT,
  validId,
  validSourceId,
} from './codec.ts';

export const PREFERENCE_DEPTH_LIMIT = 8;
export const PREFERENCE_NODE_LIMIT = 256;
export const PREFERENCE_OPTION_LIMIT = 256;
export const PREFERENCE_KEY_LIMIT = 200;
export const PREFERENCE_LABEL_LIMIT = 512;
export const PREFERENCE_SUMMARY_LIMIT = 2048;
export const PREFERENCE_TEXT_LIMIT = 4096;
export const PREFERENCE_ENTRY_LIMIT = 128;
export const PREFERENCE_VALUES_LIMIT = 32 * 1024;
export const PREFERENCE_BOOTSTRAP_LIMIT = 128 * 1024;
export const PREFERENCE_SNAPSHOT_LIMIT = 256 * 1024;

function key(value: string): void {
  requireCondition(
    value.length > 0 && value.length <= PREFERENCE_KEY_LIMIT,
    'Invalid preference storage key',
  );
}
function text(value: string): void {
  requireCondition(
    value.length <= PREFERENCE_TEXT_LIMIT,
    'Preference text exceeds its budget',
  );
}
function strings(values: readonly string[]): void {
  requireCondition(
    values.length <= PREFERENCE_OPTION_LIMIT &&
      new Set(values).size === values.length,
    'Preference string set must be bounded and unique',
  );
  values.forEach(text);
}
export function validatePreferenceValue(value: pb.PreferenceValue): void {
  switch (value.value.case) {
    case 'boolean':
      break;
    case 'text':
      text(value.value.value);
      break;
    case 'integer':
      requireCondition(
        Number.isInteger(value.value.value) &&
          value.value.value >= -2147483648 &&
          value.value.value <= 2147483647,
        'Preference integer exceeds int32',
      );
      break;
    case 'longInteger':
      requireCondition(
        value.value.value >= -9223372036854775808n &&
          value.value.value <= 9223372036854775807n,
        'Preference long integer exceeds int64',
      );
      break;
    case 'decimal':
      requireCondition(
        Number.isFinite(value.value.value) &&
          Math.abs(value.value.value) <= 3.4028234663852886e38,
        'Preference decimal must be a finite float',
      );
      break;
    case 'strings':
      strings(value.value.value.values);
      break;
    default:
      throw new Error('A preference storage value must select its type');
  }
}
export function validatePreferenceEntries(
  entries: readonly pb.PreferenceEntry[],
  maximumBytes = PREFERENCE_VALUES_LIMIT,
): void {
  requireCondition(
    entries.length <= PREFERENCE_ENTRY_LIMIT &&
      new Set(entries.map((entry) => entry.key)).size === entries.length,
    'Preference entries must be bounded and unique',
  );
  for (const entry of entries) {
    key(entry.key);
    requireCondition(entry.value !== undefined, 'Preference value is required');
    validatePreferenceValue(entry.value);
  }
  jsonText(
    entries.map((entry) => messageJson(pb.PreferenceEntrySchema, entry)),
    maximumBytes,
  );
}
export function validatePreferencePackageName(packageName: string): void {
  requireCondition(
    /^eu\.kanade\.[A-Za-z0-9_.]+$/.test(packageName) &&
      packageName.length <= 200,
    'Invalid preference package identity',
  );
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

export function validatePreferenceSyncRules(
  rules: readonly pb.PreferenceSyncRule[],
): void {
  requireCondition(
    rules.length <= PREFERENCE_ENTRY_LIMIT,
    'Too many preference sync rules',
  );
  const keys = new Set<string>();
  for (const rule of rules) {
    key(rule.key);
    if (rule.sourceId !== undefined) validSourceId(rule.sourceId);
    const identity = JSON.stringify([rule.key, rule.sourceId ?? null]);
    requireCondition(
      !keys.has(identity) &&
        Number.isInteger(rule.kind) &&
        rule.kind >= pb.PreferenceValueKind.BOOLEAN &&
        rule.kind <= pb.PreferenceValueKind.LONG_INTEGER,
      'Invalid or duplicate preference sync rule',
    );
    keys.add(identity);
  }
}

export function preferenceEntryMatchesRule(
  sourceId: string,
  entry: pb.PreferenceEntry,
  rules: readonly pb.PreferenceSyncRule[],
): boolean {
  const value = entry.value;
  return (
    value !== undefined &&
    rules.some(
      (rule) =>
        rule.key === entry.key &&
        (rule.sourceId === undefined || rule.sourceId === sourceId) &&
        rule.kind === valueKind(value),
    )
  );
}

export function validateSyncedPreferenceEntries(
  packageName: string,
  sourceId: string,
  entries: readonly pb.PreferenceEntry[],
  rules: readonly pb.PreferenceSyncRule[],
): void {
  validatePreferencePackageName(packageName);
  validSourceId(sourceId);
  validatePreferenceEntries(entries);
  requireCondition(
    entries.every((entry) =>
      preferenceEntryMatchesRule(sourceId, entry, rules),
    ),
    'Source preference key or type is not approved for account sync',
  );
}

export function validatePreferenceBootstrap(
  value: pb.PreferenceBootstrap,
): void {
  validatePreferencePackageName(value.packageName);
  validatePreferenceSyncRules(value.syncRules);
  requireCondition(
    value.sources.length <= 64 &&
      new Set(value.sources.map((source) => source.sourceId)).size ===
        value.sources.length,
    'Preference bootstrap Sources must be bounded and unique',
  );
  let bytes = 0;
  for (const source of value.sources) {
    validSourceId(source.sourceId);
    validatePreferenceEntries(source.entries);
    bytes += new TextEncoder().encode(
      JSON.stringify(
        source.entries.map((entry) =>
          messageJson(pb.PreferenceEntrySchema, entry),
        ),
      ),
    ).byteLength;
  }
  requireCondition(
    bytes <= 64 * 1024,
    'Preference bootstrap exceeds its values budget',
  );
  jsonText(
    messageJson(pb.PreferenceBootstrapSchema, value),
    PREFERENCE_BOOTSTRAP_LIMIT,
  );
}
function options(values: readonly pb.PreferenceOption[]): void {
  requireCondition(
    values.length <= PREFERENCE_OPTION_LIMIT &&
      new Set(values.map((value) => value.value)).size === values.length,
    'Preference options must be bounded and unique',
  );
  for (const value of values) {
    requireCondition(
      value.label.length <= PREFERENCE_LABEL_LIMIT,
      'Preference option label exceeds its budget',
    );
    text(value.value);
  }
}
export function validatePreferenceSnapshot(value: pb.PreferenceSnapshot): void {
  validId(value.snapshotId);
  validatePreferenceEntries([...value.syncValues, ...value.sessionValues]);
  let count = 0;
  function visit(nodes: readonly pb.PreferenceNode[], depth: number): void {
    requireCondition(
      depth <= PREFERENCE_DEPTH_LIMIT,
      'Preference tree exceeds its depth budget',
    );
    for (const node of nodes) {
      requireCondition(
        ++count <= PREFERENCE_NODE_LIMIT,
        'Preference tree exceeds its node budget',
      );
      requireCondition(
        node.key.length <= PREFERENCE_KEY_LIMIT &&
          node.title.length <= PREFERENCE_LABEL_LIMIT &&
          node.summary.length <= PREFERENCE_SUMMARY_LIMIT,
        'Preference description exceeds its text budget',
      );
      requireCondition(
        node.syncScope === pb.PreferenceSyncScope.CLIENT_SESSION ||
          node.syncScope === pb.PreferenceSyncScope.ACCOUNT,
        'Preference synchronization scope is required',
      );
      if (node.defaultValue) validatePreferenceValue(node.defaultValue);
      let expectedDefault: pb.PreferenceValue['value']['case'] = undefined;
      switch (node.kind.case) {
        case 'toggle':
          expectedDefault = 'boolean';
          key(node.key);
          break;
        case 'text':
          expectedDefault = 'text';
          key(node.key);
          if (node.kind.value.value !== undefined) text(node.kind.value.value);
          const hint = node.kind.value.hint;
          if (hint !== undefined)
            requireCondition(
              !node.kind.value.secret &&
                new TextEncoder().encode(hint).byteLength <=
                  PREFERENCE_LABEL_LIMIT,
              'Preference input hint is secret or exceeds its text budget',
            );
          requireCondition(
            !node.kind.value.secret ||
              node.syncScope === pb.PreferenceSyncScope.CLIENT_SESSION,
            'Secret preferences cannot use account synchronization',
          );
          break;
        case 'choice':
          expectedDefault = 'text';
          key(node.key);
          options(node.kind.value.options);
          if (node.kind.value.value !== undefined) text(node.kind.value.value);
          break;
        case 'multiChoice':
          expectedDefault = 'strings';
          key(node.key);
          options(node.kind.value.options);
          strings(node.kind.value.values);
          break;
        case 'group':
          if (node.kind.value.nodes.length)
            visit(node.kind.value.nodes, depth + 1);
          break;
        case 'action':
          break;
        case 'unsupported':
          requireCondition(
            node.kind.value.reason.length > 0 &&
              node.kind.value.reason.length <= PREFERENCE_SUMMARY_LIMIT,
            'Unsupported preference requires a bounded explanation',
          );
          break;
        default:
          throw new Error('A preference node must select a kind');
      }
      if (node.defaultValue && expectedDefault !== undefined)
        requireCondition(
          node.defaultValue.value.case === expectedDefault,
          'Preference default has the wrong type',
        );
    }
  }
  visit(value.nodes, 1);
  jsonText(
    messageJson(pb.PreferenceSnapshotSchema, value),
    PREFERENCE_SNAPSHOT_LIMIT,
  );
}
export function validatePreferenceEditRequest(
  value: pb.PreferenceEditRequest,
): void {
  validId(value.snapshotId);
  requireCondition(
    value.path.length > 0 &&
      value.path.length <= PREFERENCE_DEPTH_LIMIT &&
      value.path.every(
        (part) =>
          Number.isInteger(part) && part >= 0 && part < PREFERENCE_NODE_LIMIT,
      ),
    'Preference edit path exceeds its budget',
  );
  switch (value.command.case) {
    case 'change':
      validatePreferenceValue(value.command.value);
      break;
    case 'click':
      break;
    default:
      throw new Error('A preference edit must select change or click');
  }
  jsonText(
    messageJson(pb.PreferenceEditRequestSchema, value),
    SOURCE_ARGUMENT_LIMIT,
  );
}
export function validatePreferenceEditResult(
  value: pb.PreferenceEditResult,
): void {
  requireCondition(
    value.snapshot !== undefined,
    'Preference edit snapshot is required',
  );
  validatePreferenceSnapshot(value.snapshot);
}
export const preferenceSnapshotSchema = codec((input) => {
  const value = parseMessage(
    pb.PreferenceSnapshotSchema,
    input,
    PREFERENCE_SNAPSHOT_LIMIT,
  );
  validatePreferenceSnapshot(value);
  return value;
});
export const preferenceEditResultSchema = codec((input) => {
  const value = parseMessage(
    pb.PreferenceEditResultSchema,
    input,
    PREFERENCE_SNAPSHOT_LIMIT,
  );
  validatePreferenceEditResult(value);
  return value;
});
