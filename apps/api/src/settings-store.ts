import { create, fromJsonString, toJsonString } from '@bufbuild/protobuf';
import {
  AppTheme,
  BusinessStateErrorCode as ErrorCode,
  GlobalSettingsValuesSchema,
  ReaderBackground,
  ReaderFit,
  ReaderInputPreset,
  ReaderMode,
  ReaderPageLayout,
  ReaderSettingsOverrideSchema,
  SettingsMutationResponseSchema,
  SettingsMutationSchema,
  SettingsResponseSchema,
  type SettingsMutation,
  type SettingsMutationResponse,
  type SettingsResponse,
} from '@karuyomi/protocol';
import { businessSchemaVersion } from '@karuyomi/contracts';
import { hashText, StateError } from './state-store.js';

const MAX_REVISION = 0xffff_ffff;
const defaultValues = toJsonString(
  GlobalSettingsValuesSchema,
  create(GlobalSettingsValuesSchema, {
    theme: AppTheme.SYSTEM,
    reader: {
      mode: ReaderMode.LEFT_TO_RIGHT,
      pageLayout: ReaderPageLayout.AUTO,
      background: ReaderBackground.BLACK,
      fit: ReaderFit.CONTAIN,
      cropBorders: false,
      dimPercent: 0,
      tapZones: ReaderInputPreset.STANDARD,
      keyboard: ReaderInputPreset.STANDARD,
    },
  }),
);
const globalValuesSql = `COALESCE((SELECT values_json FROM reader_settings WHERE subject = ?1 AND scope_key = ''), '${defaultValues}')`;

// Used by reads and by the final statement of the mutation transaction. A
// concurrent write to a different scope cannot mix old defaults with a new
// account revision in the persisted acknowledgement.
function snapshotFieldsSql(mangaKeySql?: string): string {
  const overrides = mangaKeySql
    ? `COALESCE((SELECT values_json FROM reader_settings WHERE subject = ?1 AND scope_key = ${mangaKeySql}), '{}')`
    : "'{}'";
  return `'accountRevision', COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0),
    'global', json_object('revision', COALESCE((SELECT revision FROM reader_settings WHERE subject = ?1 AND scope_key = ''), 0),
      'values', json(${globalValuesSql})),
    'effectiveReader', json_object(
      'mode', COALESCE(json_extract(${overrides}, '$.mode'), json_extract(${globalValuesSql}, '$.reader.mode')),
      'pageLayout', COALESCE(json_extract(${overrides}, '$.pageLayout'), json_extract(${globalValuesSql}, '$.reader.pageLayout')),
      'background', COALESCE(json_extract(${overrides}, '$.background'), json_extract(${globalValuesSql}, '$.reader.background')),
      'dimPercent', COALESCE(json_extract(${overrides}, '$.dimPercent'), json_extract(${globalValuesSql}, '$.reader.dimPercent'), 0),
      'tapZones', COALESCE(json_extract(${overrides}, '$.tapZones'), json_extract(${globalValuesSql}, '$.reader.tapZones')),
      'keyboard', COALESCE(json_extract(${overrides}, '$.keyboard'), json_extract(${globalValuesSql}, '$.reader.keyboard')),
      'fit', COALESCE(json_extract(${overrides}, '$.fit'), json_extract(${globalValuesSql}, '$.reader.fit')),
      'cropBorders', json(CASE WHEN COALESCE(json_extract(${overrides}, '$.cropBorders'), json_extract(${globalValuesSql}, '$.reader.cropBorders'), 0) THEN 'true' ELSE 'false' END))
    ${
      mangaKeySql
        ? `, 'manga', json_object('mangaKey', ${mangaKeySql},
      'revision', COALESCE((SELECT revision FROM reader_settings WHERE subject = ?1 AND scope_key = ${mangaKeySql}), 0),
      'overrides', json(${overrides}))`
        : ''
    }`;
}

export async function readSettings(
  db: D1Database,
  subject: string,
  mangaKey?: string,
): Promise<SettingsResponse> {
  const row = await db
    .prepare(
      `SELECT json_object('schemaVersion', ${businessSchemaVersion}, ${snapshotFieldsSql(mangaKey ? '?2' : undefined)}) response_json`,
    )
    .bind(subject, ...(mangaKey ? [mangaKey] : []))
    .first<{ response_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Settings are unavailable',
      503,
    );
  return fromJsonString(SettingsResponseSchema, row.response_json);
}

function mutationResponse(
  mutation: SettingsMutation,
  state: SettingsResponse,
  error: StateError,
): SettingsMutationResponse {
  return create(SettingsMutationResponseSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: mutation.mutationId,
    accountRevision: state.accountRevision,
    global: state.global,
    manga: state.manga,
    effectiveReader: state.effectiveReader,
    error: {
      code: error.code,
      message: error.message,
      retryable: error.status === 503,
    },
  });
}

export async function applySettingsMutation(
  db: D1Database,
  subject: string,
  mutation: SettingsMutation,
): Promise<{
  status: 200 | 400 | 409 | 413 | 503;
  response: SettingsMutationResponse;
}> {
  const operation = mutation.operation;
  if (operation.case !== 'setGlobal' && operation.case !== 'setManga')
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'A settings operation is required',
    );
  const mangaKey =
    operation.case === 'setManga' ? operation.value.mangaKey : undefined;
  const scopeKey = mangaKey ?? '';
  const requestHash = await hashText(
    'settings\n' + toJsonString(SettingsMutationSchema, mutation),
  );
  const findMutation = () =>
    db
      .prepare(
        'SELECT kind, request_hash, response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutation.mutationId)
      .first<{ kind: string; request_hash: string; response_json: string }>();
  const existing = await findMutation();
  if (existing?.kind === 'settings' && existing.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        SettingsMutationResponseSchema,
        existing.response_json,
      ),
    };
  const state = await readSettings(db, subject, mangaKey);
  const failure = (error: StateError, canonical = state) => ({
    status: error.status,
    response: mutationResponse(mutation, canonical, error),
  });
  if (existing)
    return failure(
      new StateError(
        ErrorCode.IDEMPOTENCY_CONFLICT,
        'Mutation ID was used for different content',
        409,
      ),
    );
  const revision = mangaKey ? state.manga?.revision : state.global?.revision;
  if (revision === undefined)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Settings are unavailable',
      503,
    );
  if (revision !== mutation.expectedRevision)
    return failure(
      new StateError(
        ErrorCode.REVISION_CONFLICT,
        'Settings revision changed',
        409,
      ),
    );
  if (revision === MAX_REVISION || state.accountRevision === MAX_REVISION)
    return failure(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Settings revision is exhausted',
        409,
      ),
    );
  let valuesJson: string;
  if (operation.case === 'setGlobal') {
    valuesJson = toJsonString(GlobalSettingsValuesSchema, operation.value);
  } else {
    if (!operation.value.overrides)
      throw new StateError(
        ErrorCode.INVALID_INPUT,
        'Reader overrides are required',
      );
    valuesJson = toJsonString(
      ReaderSettingsOverrideSchema,
      operation.value.overrides,
    );
  }
  const nonce = crypto.randomUUID();
  const winner =
    'EXISTS (SELECT 1 FROM state_mutations WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3)';
  const initialResponse = create(SettingsMutationResponseSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: mutation.mutationId,
  });
  await db.batch([
    db
      .prepare(
        'INSERT OR IGNORE INTO account_state(subject, revision) VALUES (?, 0)',
      )
      .bind(subject),
    db
      .prepare(
        `INSERT OR IGNORE INTO state_mutations(subject, mutation_id, request_hash, attempt_nonce, response_json, kind)
      SELECT ?1, ?2, ?3, ?4, ?5, 'settings'
      WHERE COALESCE((SELECT revision FROM reader_settings WHERE subject = ?1 AND scope_key = ?6), 0) = ?7
      AND ?7 < ?8 AND (SELECT revision FROM account_state WHERE subject = ?1) < ?8`,
      )
      .bind(
        subject,
        mutation.mutationId,
        requestHash,
        nonce,
        toJsonString(SettingsMutationResponseSchema, initialResponse),
        scopeKey,
        mutation.expectedRevision,
        MAX_REVISION,
      ),
    db
      .prepare(
        `UPDATE account_state SET revision = revision + 1 WHERE subject = ?1 AND ${winner}`,
      )
      .bind(subject, mutation.mutationId, nonce),
    db
      .prepare(
        `INSERT INTO reader_settings(subject, scope_key, revision, values_json)
      SELECT ?1, ?4, ?5, ?6 WHERE ${winner}
      ON CONFLICT(subject, scope_key) DO UPDATE SET revision = excluded.revision, values_json = excluded.values_json`,
      )
      .bind(
        subject,
        mutation.mutationId,
        nonce,
        scopeKey,
        revision + 1,
        valuesJson,
      ),
    db
      .prepare(
        `UPDATE state_mutations SET response_json = json_object('schemaVersion', ${businessSchemaVersion}, 'mutationId', ?2,
      ${snapshotFieldsSql(mangaKey ? '?4' : undefined)})
      WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3`,
      )
      .bind(
        subject,
        mutation.mutationId,
        nonce,
        ...(mangaKey ? [mangaKey] : []),
      ),
  ]);
  const committed = await findMutation();
  if (committed?.kind === 'settings' && committed.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        SettingsMutationResponseSchema,
        committed.response_json,
      ),
    };
  return failure(
    new StateError(
      committed ? ErrorCode.IDEMPOTENCY_CONFLICT : ErrorCode.REVISION_CONFLICT,
      committed
        ? 'Mutation ID was used for different content'
        : 'Settings revision changed',
      409,
    ),
    await readSettings(db, subject, mangaKey),
  );
}
