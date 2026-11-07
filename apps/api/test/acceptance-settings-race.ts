import { equals, toJsonString } from '@bufbuild/protobuf';
import {
  settingsMutationResponseSchema,
  settingsMutationSchema,
} from '@karuyomi/contracts';
import {
  AppTheme,
  BusinessStateErrorCode,
  SettingsMutationResponseSchema,
  SettingsMutationSchema,
} from '@karuyomi/protocol';
import { sha256 } from './acceptance-ack.ts';

const racePath = '/api/settings/mutations';
const waitBudgetMs = 15_000;
const pollIntervalMs = 25;
const releaseLeadMs = 3 * pollIntervalMs;

interface Arrival {
  sequence: number;
  mutation_id: string;
  expected_revision: number;
  theme: AppTheme;
  body_sha256: string;
  arrived_at_ms: number;
}

interface RaceAttempt extends Arrival {
  expired: number;
  release_at_ms: number | null;
  dispatch_at_ms: number | null;
  response_at_ms: number | null;
  http_status: number | null;
  error_code: BusinessStateErrorCode | null;
  account_revision: number | null;
  global_revision: number | null;
  receipt_sha256: string | null;
}

interface AdmittedAttempt {
  arrival: Arrival;
  requestHash: string;
  releaseAtMs: number;
}

export async function prepareSettingsRace(db: D1Database): Promise<void> {
  await db
    .prepare(
      `CREATE TABLE acceptance_settings_race (
    sequence INTEGER PRIMARY KEY,
    mutation_id TEXT NOT NULL UNIQUE,
    expected_revision INTEGER NOT NULL CHECK (expected_revision = 0),
    theme INTEGER NOT NULL UNIQUE,
    body_sha256 TEXT NOT NULL,
    arrived_at_ms INTEGER NOT NULL,
    expired INTEGER NOT NULL DEFAULT 0 CHECK (expired IN (0, 1)),
    release_at_ms INTEGER,
    dispatch_at_ms INTEGER,
    response_at_ms INTEGER,
    http_status INTEGER,
    error_code INTEGER,
    account_revision INTEGER,
    global_revision INTEGER,
    receipt_sha256 TEXT
  )`,
    )
    .run();
}

export async function settingsRaceAttempts(
  db: D1Database,
): Promise<RaceAttempt[]> {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_settings_race ORDER BY sequence')
    .all<RaceAttempt>();
  return results;
}

function gateFailure(reason: string): Response {
  return Response.json(
    { acceptanceFixtureError: reason },
    {
      status: 503,
      headers: { 'Cache-Control': 'no-store' },
    },
  );
}

export async function holdSettingsRace(
  request: Request,
  db: D1Database,
  origin: string,
  subject: string,
  readJson: (request: Request) => Promise<unknown>,
  budgetMs = waitBudgetMs,
): Promise<AdmittedAttempt | Response | undefined> {
  const url = new URL(request.url);
  if (
    request.method !== 'POST' ||
    url.origin !== origin ||
    url.hostname !== '127.0.0.1' ||
    url.pathname !== racePath ||
    url.search !== '' ||
    request.headers.get('Origin') !== origin ||
    request.headers.get('X-App-Subject') !== subject ||
    request.headers.get('X-App-Request') !== '1'
  )
    return;

  // Use the real bounded JSON reader on a clone. Invalid and unrelated
  // requests retain their existing route behavior.
  let mutation;
  try {
    mutation = settingsMutationSchema.parse(await readJson(request.clone()));
  } catch {
    return;
  }
  if (
    mutation.expectedRevision !== 0 ||
    mutation.operation.case !== 'setGlobal'
  )
    return;
  const theme = mutation.operation.value.theme;
  if (theme !== AppTheme.DARK && theme !== AppTheme.LIGHT) return;

  const [bodyHash, requestHash] = await Promise.all([
    request.clone().arrayBuffer().then(sha256),
    sha256('settings\n' + toJsonString(SettingsMutationSchema, mutation)),
  ]);
  const arrival = await db
    .prepare(
      `INSERT INTO acceptance_settings_race (
        mutation_id, expected_revision, theme, body_sha256, arrived_at_ms
      )
      SELECT ?1, ?2, ?3, ?4, ?5
      WHERE (SELECT COUNT(*) FROM acceptance_settings_race) < 2
        AND NOT EXISTS (SELECT 1 FROM acceptance_settings_race
          WHERE expired = 1 OR arrived_at_ms + ?6 <= ?5)
      ON CONFLICT DO NOTHING
      RETURNING sequence, mutation_id, expected_revision, theme, body_sha256, arrived_at_ms`,
    )
    .bind(
      mutation.mutationId,
      mutation.expectedRevision,
      theme,
      bodyHash,
      Date.now(),
      budgetMs,
    )
    .first<Arrival>();
  if (!arrival)
    return gateFailure('Settings race slot is closed or duplicated');

  console.log('ACCEPTANCE_SETTINGS_RACE_ARRIVAL=' + JSON.stringify(arrival));
  while (true) {
    const gate = await db
      .prepare(
        `SELECT COUNT(*) AS arrivals, MAX(expired) AS expired,
        MIN(arrived_at_ms) AS first_arrival, MAX(arrived_at_ms) AS last_arrival
        FROM acceptance_settings_race`,
      )
      .first<{
        arrivals: number;
        expired: number;
        first_arrival: number;
        last_arrival: number;
      }>();
    if (gate?.arrivals === 2) {
      // Give both requests time to observe admission and sign their assertion.
      return {
        arrival,
        requestHash,
        releaseAtMs: gate.last_arrival + releaseLeadMs,
      };
    }
    if (!gate || gate.expired === 1)
      return gateFailure('Settings race timed out before release');
    const remaining = gate.first_arrival + budgetMs - Date.now();
    if (remaining <= 0) {
      // This expiry and the second admission are atomic D1 statements. If the
      // other request was admitted first, the two can still be released.
      await db
        .prepare(
          `UPDATE acceptance_settings_race SET expired = 1
        WHERE sequence = 1 AND (SELECT COUNT(*) FROM acceptance_settings_race) = 1`,
        )
        .run();
    } else {
      await scheduler.wait(Math.min(pollIntervalMs, remaining));
    }
  }
}

export async function waitForSettingsRaceRelease(
  attempt: AdmittedAttempt,
): Promise<void> {
  let remaining = attempt.releaseAtMs - Date.now();
  while (remaining > 0) {
    await scheduler.wait(remaining);
    remaining = attempt.releaseAtMs - Date.now();
  }
}

export async function observeSettingsRace(
  db: D1Database,
  subject: string,
  attempt: AdmittedAttempt,
  response: Response,
  dispatchAtMs: number,
  responseAtMs: number,
): Promise<void> {
  const ack = settingsMutationResponseSchema.parse(
    await response.clone().json(),
  );
  const { mutation_id: mutationId, theme } = attempt.arrival;
  if (
    ack.mutationId !== mutationId ||
    ack.global?.revision !== 1 ||
    ack.accountRevision !== 1 ||
    ack.manga
  ) {
    throw new Error('Unexpected settings race ACK identity or revision');
  }
  const receipt = await db
    .prepare(
      `SELECT kind, request_hash, attempt_nonce, response_json FROM state_mutations
      WHERE subject = ? AND mutation_id = ?`,
    )
    .bind(subject, mutationId)
    .first<{
      kind: string;
      request_hash: string;
      attempt_nonce: string;
      response_json: string;
    }>();

  let receiptHash: string | null = null;
  if (
    response.status === 200 &&
    !ack.error &&
    ack.global.values?.theme === theme
  ) {
    if (
      receipt?.kind !== 'settings' ||
      receipt.request_hash !== attempt.requestHash ||
      !equals(
        SettingsMutationResponseSchema,
        ack,
        settingsMutationResponseSchema.parse(JSON.parse(receipt.response_json)),
      )
    )
      throw new Error('Winning settings race ACK has no matching D1 receipt');
    receiptHash = await sha256(
      JSON.stringify([
        receipt.kind,
        receipt.request_hash,
        receipt.attempt_nonce,
        receipt.response_json,
      ]),
    );
  } else if (
    response.status !== 409 ||
    ack.error?.code !== BusinessStateErrorCode.REVISION_CONFLICT ||
    ack.global.values?.theme === theme ||
    receipt !== null
  )
    throw new Error('Expected a losing settings CAS without a D1 receipt');

  const outcome = await db
    .prepare(
      `UPDATE acceptance_settings_race
      SET release_at_ms = ?2, dispatch_at_ms = ?3, response_at_ms = ?4,
        http_status = ?5, error_code = ?6, account_revision = ?7,
        global_revision = ?8, receipt_sha256 = ?9 WHERE sequence = ?1 RETURNING *`,
    )
    .bind(
      attempt.arrival.sequence,
      attempt.releaseAtMs,
      dispatchAtMs,
      responseAtMs,
      response.status,
      ack.error?.code ?? null,
      ack.accountRevision,
      ack.global.revision,
      receiptHash,
    )
    .first<RaceAttempt>();
  console.log('ACCEPTANCE_SETTINGS_RACE_OUTCOME=' + JSON.stringify(outcome));
}
