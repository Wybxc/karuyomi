import { equals, toJsonString } from '@bufbuild/protobuf';
import {
  BUSINESS_REQUEST_LIMIT,
  settingsMutationResponseSchema,
  settingsMutationSchema,
} from '@karuyomi/contracts';
import {
  SettingsMutationResponseSchema,
  SettingsMutationSchema,
} from '@karuyomi/protocol';

const maxAttempts = 16;
const path = '/api/settings/mutations';

async function sha256(value: ArrayBuffer | string): Promise<string> {
  const bytes =
    typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

interface SettingsAckAttempt {
  sequence: number;
  mutation_id: string;
  expected_revision: number;
  account_revision: number;
  global_revision: number;
  body_sha256: string;
  ack_sha256: string;
  receipt_sha256: string;
  drop_ack: number;
}

export function shouldObserveSettingsAck(
  request: Request,
  origin: string,
): boolean {
  const url = new URL(request.url);
  return (
    url.origin === origin &&
    url.hostname === '127.0.0.1' &&
    url.pathname === path &&
    url.search === '' &&
    request.method === 'POST'
  );
}

export async function prepareSettingsAckLoss(db: D1Database): Promise<void> {
  // This independent audit table exists only in the opt-in acceptance D1.
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_settings_ack_attempts (
      sequence INTEGER PRIMARY KEY,
      mutation_id TEXT NOT NULL,
      expected_revision INTEGER NOT NULL,
      account_revision INTEGER NOT NULL,
      global_revision INTEGER NOT NULL,
      body_sha256 TEXT NOT NULL,
      ack_sha256 TEXT NOT NULL,
      receipt_sha256 TEXT NOT NULL,
      drop_ack INTEGER NOT NULL CHECK (drop_ack IN (0, 1))
    )`),
    db.prepare(`CREATE UNIQUE INDEX acceptance_settings_ack_one_drop
      ON acceptance_settings_ack_attempts(drop_ack) WHERE drop_ack = 1`),
  ]);
}

export async function settingsAckAttempts(
  db: D1Database,
): Promise<SettingsAckAttempt[]> {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_settings_ack_attempts ORDER BY sequence')
    .all<SettingsAckAttempt>();
  return results;
}

export async function observeSettingsAck(
  request: Request,
  response: Response,
  db: D1Database,
  subject: string,
): Promise<Response> {
  if (
    response.status !== 200 ||
    request.headers.get('X-App-Subject') !== subject
  ) {
    void request.body?.cancel().catch(() => {});
    return response;
  }
  // The real route has already validated this same body and applied its limit.
  const raw = await request.arrayBuffer();
  if (raw.byteLength > BUSINESS_REQUEST_LIMIT) {
    throw new Error('Oversized accepted settings mutation');
  }
  const mutation = settingsMutationSchema.parse(
    JSON.parse(
      new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(raw),
    ),
  );
  if (mutation.operation.case !== 'setGlobal') return response;
  const ackText = await response.clone().text();
  const ack = settingsMutationResponseSchema.parse(JSON.parse(ackText));
  if (ack.error) return response;
  if (
    ack.mutationId !== mutation.mutationId ||
    !ack.global ||
    ack.manga ||
    ack.global.revision !== mutation.expectedRevision + 1
  ) {
    throw new Error('Unexpected successful global settings ACK');
  }
  const receipt = await db
    .prepare(
      `SELECT kind, request_hash, attempt_nonce, response_json
      FROM state_mutations WHERE subject = ? AND mutation_id = ?`,
    )
    .bind(subject, mutation.mutationId)
    .first<{
      kind: string;
      request_hash: string;
      attempt_nonce: string;
      response_json: string;
    }>();
  const requestHash = await sha256(
    'settings\n' + toJsonString(SettingsMutationSchema, mutation),
  );
  if (
    receipt?.kind !== 'settings' ||
    receipt.request_hash !== requestHash ||
    !equals(
      SettingsMutationResponseSchema,
      ack,
      settingsMutationResponseSchema.parse(JSON.parse(receipt.response_json)),
    )
  ) {
    throw new Error('Successful settings ACK has no matching D1 receipt');
  }
  const bodySha256 = await sha256(raw);
  // No credentials, request body, setting values, or original nonce are logged.
  const ackSha256 = await sha256(ackText);
  const receiptSha256 = await sha256(
    JSON.stringify([
      receipt.kind,
      receipt.request_hash,
      receipt.attempt_nonce,
      receipt.response_json,
    ]),
  );
  // A single D1 statement atomically gives at most one successful attempt the
  // fault slot, independently of worker lifetimes or the production receipt.
  const attempt = await db
    .prepare(
      `INSERT INTO acceptance_settings_ack_attempts (
        mutation_id, expected_revision, account_revision, global_revision,
        body_sha256, ack_sha256, receipt_sha256, drop_ack
      )
      SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7,
        CASE WHEN EXISTS (SELECT 1 FROM acceptance_settings_ack_attempts WHERE drop_ack = 1)
        THEN 0 ELSE 1 END
      WHERE (SELECT COUNT(*) FROM acceptance_settings_ack_attempts) < ?8
      RETURNING *`,
    )
    .bind(
      mutation.mutationId,
      mutation.expectedRevision,
      ack.accountRevision,
      ack.global.revision,
      bodySha256,
      ackSha256,
      receiptSha256,
      maxAttempts,
    )
    .first<SettingsAckAttempt>();
  if (attempt) {
    console.log('ACCEPTANCE_SETTINGS_ACK_ATTEMPT=' + JSON.stringify(attempt));
  }
  if (attempt?.drop_ack !== 1) return response;

  await response.body?.cancel().catch(() => {});
  const headers = new Headers(response.headers);
  headers.delete('Content-Length');
  const prefix = new TextEncoder().encode(ackText.slice(0, 16));
  let sent = false;
  return new Response(
    new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (!sent) {
          sent = true;
          controller.enqueue(prefix);
          return;
        }
        // Give the HTTP runtime time to flush the 200 headers before failing
        // the stream. The complete ACK is never sent.
        await new Promise<void>((resolve) => setTimeout(resolve, 250));
        controller.error(new Error('Acceptance interrupted the settings ACK'));
      },
    }),
    { status: response.status, statusText: response.statusText, headers },
  );
}
