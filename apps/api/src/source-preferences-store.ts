import { create, fromJsonString, toJsonString } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  SourcePreferencesSchema,
  SourcePreferencesMutationSchema,
  SourcePreferencesMutationResponseSchema,
  type SourcePreferences,
  type SourcePreferencesMutation,
  type SourcePreferencesMutationResponse,
  type SourcePreferencesResponse,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  SOURCE_PREFERENCES_PACKAGE_LIMIT,
  SOURCE_PREFERENCES_PACKAGE_BYTES,
  sourcePreferenceEntriesJson,
  sourcePreferencesResponseSchema,
  sourcePreferencesMutationResponseSchema,
} from '@karuyomi/contracts';
import { hashText, StateError } from './state-store.js';

const MAX_REVISION = 0xffff_ffff;
const KIND = 'source_preferences';
const preferencesSql = `json_object('packageName', ?2, 'sourceId', ?3,
  'revision', COALESCE((SELECT revision FROM source_preferences WHERE subject = ?1 AND package_name = ?2 AND source_id = ?3), 0),
  'entries', json(COALESCE((SELECT entries_json FROM source_preferences WHERE subject = ?1 AND package_name = ?2 AND source_id = ?3), '[]')))`;

export async function readSourcePreferences(
  db: D1Database,
  subject: string,
  packageName: string,
): Promise<SourcePreferencesResponse> {
  // One statement captures account revision and every returned source together.
  // LIMIT also bounds unexpected/corrupted storage before decoding the reply.
  const row = await db
    .prepare(
      `SELECT json_object(
    'schemaVersion', ${businessSchemaVersion},
    'accountRevision', COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0),
    'packageName', ?2,
    'sources', json(COALESCE((SELECT json_group_array(json_object(
      'packageName', package_name, 'sourceId', source_id, 'revision', revision, 'entries', json(entries_json)))
      FROM (SELECT * FROM source_preferences WHERE subject = ?1 AND package_name = ?2 ORDER BY source_id LIMIT ?3)), '[]'))
  ) response_json`,
    )
    .bind(subject, packageName, SOURCE_PREFERENCES_PACKAGE_LIMIT + 1)
    .first<{ response_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Source preferences are unavailable',
      503,
    );
  return sourcePreferencesResponseSchema.parse(JSON.parse(row.response_json));
}

async function currentPreferences(
  db: D1Database,
  subject: string,
  packageName: string,
  sourceId: string,
): Promise<{ accountRevision: number; preferences: SourcePreferences }> {
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    ${preferencesSql} preferences_json`,
    )
    .bind(subject, packageName, sourceId)
    .first<{ account_revision: number; preferences_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Source preferences are unavailable',
      503,
    );
  return {
    accountRevision: row.account_revision,
    preferences: fromJsonString(SourcePreferencesSchema, row.preferences_json),
  };
}

async function packageHasCapacity(
  db: D1Database,
  subject: string,
  packageName: string,
  sourceId: string,
  entriesJson: string,
): Promise<boolean> {
  const row = await db
    .prepare(
      `SELECT count(*) scopes, COALESCE(sum(length(CAST(entries_json AS BLOB))), 0) bytes
    FROM source_preferences WHERE subject = ?1 AND package_name = ?2 AND source_id <> ?3`,
    )
    .bind(subject, packageName, sourceId)
    .first<{ scopes: number; bytes: number }>();
  return (
    !!row &&
    row.scopes < SOURCE_PREFERENCES_PACKAGE_LIMIT &&
    row.bytes + new TextEncoder().encode(entriesJson).byteLength <=
      SOURCE_PREFERENCES_PACKAGE_BYTES
  );
}

export async function applySourcePreferencesMutation(
  db: D1Database,
  subject: string,
  mutation: SourcePreferencesMutation,
): Promise<{
  status: 200 | 400 | 409 | 413 | 503;
  response: SourcePreferencesMutationResponse;
}> {
  const requestHash = await hashText(
    KIND + '\n' + toJsonString(SourcePreferencesMutationSchema, mutation),
  );
  const findMutation = () =>
    db
      .prepare(
        'SELECT kind, request_hash, response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutation.mutationId)
      .first<{ kind: string; request_hash: string; response_json: string }>();
  const replay = (responseJson: string) => ({
    status: 200 as const,
    response: sourcePreferencesMutationResponseSchema.parse(
      JSON.parse(responseJson),
    ),
  });
  const existing = await findMutation();
  if (existing?.kind === KIND && existing.request_hash === requestHash)
    return replay(existing.response_json);
  let state = await currentPreferences(
    db,
    subject,
    mutation.packageName,
    mutation.sourceId,
  );
  const failure = (error: StateError) => ({
    status: error.status,
    response: create(SourcePreferencesMutationResponseSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: mutation.mutationId,
      accountRevision: state.accountRevision,
      preferences: state.preferences,
      error: {
        code: error.code,
        message: error.message,
        retryable: error.status === 503,
      },
    }),
  });
  if (existing)
    return failure(
      new StateError(
        ErrorCode.IDEMPOTENCY_CONFLICT,
        'Mutation ID was used for different content',
        409,
      ),
    );
  if (state.preferences.revision !== mutation.expectedRevision)
    return failure(
      new StateError(
        ErrorCode.REVISION_CONFLICT,
        'Source preferences revision changed',
        409,
      ),
    );
  if (
    state.preferences.revision === MAX_REVISION ||
    state.accountRevision === MAX_REVISION
  )
    return failure(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Source preferences revision is exhausted',
        409,
      ),
    );
  const entriesJson = sourcePreferenceEntriesJson(mutation.entries);
  if (
    !(await packageHasCapacity(
      db,
      subject,
      mutation.packageName,
      mutation.sourceId,
      entriesJson,
    ))
  )
    return failure(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Source package preferences exceed their budget',
        413,
      ),
    );
  const nonce = crypto.randomUUID();
  const winner =
    'EXISTS (SELECT 1 FROM state_mutations WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3)';
  await db.batch([
    db
      .prepare(
        'INSERT OR IGNORE INTO account_state(subject, revision) VALUES (?, 0)',
      )
      .bind(subject),
    db
      .prepare(
        `INSERT OR IGNORE INTO state_mutations(subject, mutation_id, request_hash, attempt_nonce, response_json, kind)
      SELECT ?1, ?2, ?3, ?4, ?5, '${KIND}'
      WHERE COALESCE((SELECT revision FROM source_preferences WHERE subject = ?1 AND package_name = ?6 AND source_id = ?7), 0) = ?8
        AND ?8 < ?9 AND (SELECT revision FROM account_state WHERE subject = ?1) < ?9
        AND (SELECT count(*) FROM source_preferences WHERE subject = ?1 AND package_name = ?6 AND source_id <> ?7) < ?11
        AND COALESCE((SELECT sum(length(CAST(entries_json AS BLOB))) FROM source_preferences
          WHERE subject = ?1 AND package_name = ?6 AND source_id <> ?7), 0) + length(CAST(?10 AS BLOB)) <= ?12`,
      )
      .bind(
        subject,
        mutation.mutationId,
        requestHash,
        nonce,
        toJsonString(
          SourcePreferencesMutationResponseSchema,
          create(SourcePreferencesMutationResponseSchema, {
            schemaVersion: businessSchemaVersion,
            mutationId: mutation.mutationId,
          }),
        ),
        mutation.packageName,
        mutation.sourceId,
        mutation.expectedRevision,
        MAX_REVISION,
        entriesJson,
        SOURCE_PREFERENCES_PACKAGE_LIMIT,
        SOURCE_PREFERENCES_PACKAGE_BYTES,
      ),
    db
      .prepare(
        `UPDATE account_state SET revision = revision + 1 WHERE subject = ?1 AND ${winner}`,
      )
      .bind(subject, mutation.mutationId, nonce),
    db
      .prepare(
        `INSERT INTO source_preferences(subject, package_name, source_id, revision, entries_json)
      SELECT ?1, ?4, ?5, ?6, ?7 WHERE ${winner}
      ON CONFLICT(subject, package_name, source_id) DO UPDATE SET revision = excluded.revision, entries_json = excluded.entries_json`,
      )
      .bind(
        subject,
        mutation.mutationId,
        nonce,
        mutation.packageName,
        mutation.sourceId,
        mutation.expectedRevision + 1,
        entriesJson,
      ),
    db
      .prepare(
        `UPDATE state_mutations SET response_json = json_object('schemaVersion', ${businessSchemaVersion},
      'mutationId', ?2, 'accountRevision', (SELECT revision FROM account_state WHERE subject = ?1),
      'preferences', json_object('packageName', ?4, 'sourceId', ?5, 'revision', ?6, 'entries', json(?7)))
      WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3`,
      )
      .bind(
        subject,
        mutation.mutationId,
        nonce,
        mutation.packageName,
        mutation.sourceId,
        mutation.expectedRevision + 1,
        entriesJson,
      ),
  ]);
  const committed = await findMutation();
  if (committed?.kind === KIND && committed.request_hash === requestHash)
    return replay(committed.response_json);
  state = await currentPreferences(
    db,
    subject,
    mutation.packageName,
    mutation.sourceId,
  );
  if (committed)
    return failure(
      new StateError(
        ErrorCode.IDEMPOTENCY_CONFLICT,
        'Mutation ID was used for different content',
        409,
      ),
    );
  if (
    !(await packageHasCapacity(
      db,
      subject,
      mutation.packageName,
      mutation.sourceId,
      entriesJson,
    ))
  )
    return failure(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Source package preferences exceed their budget',
        413,
      ),
    );
  return failure(
    new StateError(
      ErrorCode.REVISION_CONFLICT,
      'Source preferences revision changed',
      409,
    ),
  );
}
