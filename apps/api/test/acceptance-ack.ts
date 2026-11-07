import { equals, toJsonString } from '@bufbuild/protobuf';
import {
  BUSINESS_REQUEST_LIMIT,
  settingsMutationResponseSchema,
  settingsMutationSchema,
  stateMutationResponseSchema,
  stateMutationSchema,
} from '@karuyomi/contracts';
import {
  SettingsMutationResponseSchema,
  SettingsMutationSchema,
  StateMutationResponseSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';

const maxAttempts = 16;
const fixtures = {
  'settings-ack-loss': {
    path: '/api/settings/mutations',
    label: 'ACCEPTANCE_SETTINGS_ACK',
  },
  'progress-ack-loss': {
    path: '/api/state/mutations',
    label: 'ACCEPTANCE_PROGRESS_ACK',
  },
} as const;

export type AckLossFixture = keyof typeof fixtures;

// English xkcd, SINGLE, /3319/. Require the explicit completion save at the
// last page so automatic observations during preparation never use the fault.
const progressMangaKey =
  '62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f';
const progressChapterKey =
  '3ebd1a075e8cc6fad4cae9daa7595caac80545bdf9499496417bb3d3b6b1142c';

export function isAckLossFixture(value: string): value is AckLossFixture {
  return Object.hasOwn(fixtures, value);
}

export function ackLossLabel(fixture: AckLossFixture): string {
  return fixtures[fixture].label;
}

export async function sha256(value: ArrayBuffer | string): Promise<string> {
  const bytes =
    typeof value === 'string' ? new TextEncoder().encode(value) : value;
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

interface AttemptRow {
  sequence: number;
  mutation_id: string;
  expected_revision: number;
  account_revision: number;
  scope_revision: number;
  body_sha256: string;
  ack_sha256: string;
  receipt_sha256: string;
  drop_ack: number;
}

function auditAttempt(fixture: AckLossFixture, row: AttemptRow) {
  const { scope_revision, ...attempt } = row;
  return fixture === 'settings-ack-loss'
    ? { ...attempt, global_revision: scope_revision }
    : {
        ...attempt,
        manga_revision: scope_revision,
        manga_key: progressMangaKey,
        chapter_key: progressChapterKey,
      };
}

export function shouldObserveAck(
  fixture: AckLossFixture,
  request: Request,
  origin: string,
): boolean {
  const url = new URL(request.url);
  return (
    url.origin === origin &&
    url.hostname === '127.0.0.1' &&
    url.pathname === fixtures[fixture].path &&
    url.search === '' &&
    request.method === 'POST'
  );
}

export async function prepareAckLoss(db: D1Database): Promise<void> {
  // Each harness selects at most one opt-in fixture for its isolated D1.
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_ack_attempts (
      sequence INTEGER PRIMARY KEY,
      mutation_id TEXT NOT NULL,
      expected_revision INTEGER NOT NULL,
      account_revision INTEGER NOT NULL,
      scope_revision INTEGER NOT NULL,
      body_sha256 TEXT NOT NULL,
      ack_sha256 TEXT NOT NULL,
      receipt_sha256 TEXT NOT NULL,
      drop_ack INTEGER NOT NULL CHECK (drop_ack IN (0, 1))
    )`),
    db.prepare(`CREATE UNIQUE INDEX acceptance_ack_one_drop
      ON acceptance_ack_attempts(drop_ack) WHERE drop_ack = 1`),
  ]);
}

export async function ackAttempts(db: D1Database, fixture: AckLossFixture) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_ack_attempts ORDER BY sequence')
    .all<AttemptRow>();
  return results.map((row) => auditAttempt(fixture, row));
}

interface ObservedAck {
  kind: 'settings' | 'manga';
  mutationId: string;
  expectedRevision: number;
  accountRevision: number;
  scopeRevision: number;
  canonicalRequest: string;
  ackText: string;
  matchesReceipt: (receipt: string) => boolean;
}

async function acceptedAck(
  fixture: AckLossFixture,
  input: unknown,
  response: Response,
): Promise<ObservedAck | undefined> {
  if (fixture === 'settings-ack-loss') {
    const mutation = settingsMutationSchema.parse(input);
    if (mutation.operation.case !== 'setGlobal') return;
    const ackText = await response.clone().text();
    const ack = settingsMutationResponseSchema.parse(JSON.parse(ackText));
    if (ack.error) return;
    if (
      ack.mutationId !== mutation.mutationId ||
      !ack.global ||
      ack.manga ||
      ack.global.revision !== mutation.expectedRevision + 1
    ) {
      throw new Error('Unexpected successful global settings ACK');
    }
    return {
      kind: 'settings',
      mutationId: mutation.mutationId,
      expectedRevision: mutation.expectedRevision,
      accountRevision: ack.accountRevision,
      scopeRevision: ack.global.revision,
      canonicalRequest: toJsonString(SettingsMutationSchema, mutation),
      ackText,
      matchesReceipt: (receipt) =>
        equals(
          SettingsMutationResponseSchema,
          ack,
          settingsMutationResponseSchema.parse(JSON.parse(receipt)),
        ),
    };
  }

  const mutation = stateMutationSchema.parse(input);
  if (
    mutation.operation.case !== 'saveProgress' ||
    mutation.mangaKey !== progressMangaKey
  )
    return;
  const { snapshot, progress } = mutation.operation.value;
  if (
    snapshot?.chapterKey !== progressChapterKey ||
    !progress?.completed ||
    !progress.current ||
    progress.current.pageKey !== snapshot.pageKeys.at(-1)
  )
    return;
  const ackText = await response.clone().text();
  const ack = stateMutationResponseSchema.parse(JSON.parse(ackText));
  if (ack.error) return;
  if (
    ack.mutationId !== mutation.mutationId ||
    ack.manga?.mangaKey !== mutation.mangaKey ||
    ack.manga.revision !== mutation.expectedRevision + 1 ||
    ack.progress?.chapterKey !== progressChapterKey ||
    !ack.progress.completed ||
    ack.progress.epoch !== progress.epoch ||
    ack.progress.current?.pageKey !== progress.current.pageKey ||
    ack.progress.current.manifestVersion !== snapshot.manifestVersion
  ) {
    throw new Error('Unexpected successful chapter completion ACK');
  }
  return {
    kind: 'manga',
    mutationId: mutation.mutationId,
    expectedRevision: mutation.expectedRevision,
    accountRevision: ack.accountRevision,
    scopeRevision: ack.manga.revision,
    canonicalRequest: toJsonString(StateMutationSchema, mutation),
    ackText,
    matchesReceipt: (receipt) =>
      equals(
        StateMutationResponseSchema,
        ack,
        stateMutationResponseSchema.parse(JSON.parse(receipt)),
      ),
  };
}

export async function observeAck(
  fixture: AckLossFixture,
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
    throw new Error('Oversized accepted mutation');
  }
  const input: unknown = JSON.parse(
    new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(raw),
  );
  const ack = await acceptedAck(fixture, input, response);
  if (!ack) return response;
  const receipt = await db
    .prepare(
      `SELECT kind, request_hash, attempt_nonce, response_json
      FROM state_mutations WHERE subject = ? AND mutation_id = ?`,
    )
    .bind(subject, ack.mutationId)
    .first<{
      kind: string;
      request_hash: string;
      attempt_nonce: string;
      response_json: string;
    }>();
  const requestHash = await sha256(ack.kind + '\n' + ack.canonicalRequest);
  if (
    receipt?.kind !== ack.kind ||
    receipt.request_hash !== requestHash ||
    !ack.matchesReceipt(receipt.response_json)
  ) {
    throw new Error('Successful mutation ACK has no matching D1 receipt');
  }
  const bodySha256 = await sha256(raw);
  // Do not log credentials, original bodies, values or the receipt nonce.
  const ackSha256 = await sha256(ack.ackText);
  const receiptSha256 = await sha256(
    JSON.stringify([
      receipt.kind,
      receipt.request_hash,
      receipt.attempt_nonce,
      receipt.response_json,
    ]),
  );
  // One D1 statement gives at most one successful attempt the fault slot.
  const attempt = await db
    .prepare(
      `INSERT INTO acceptance_ack_attempts (
        mutation_id, expected_revision, account_revision, scope_revision,
        body_sha256, ack_sha256, receipt_sha256, drop_ack
      )
      SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7,
        CASE WHEN EXISTS (SELECT 1 FROM acceptance_ack_attempts WHERE drop_ack = 1)
        THEN 0 ELSE 1 END
      WHERE (SELECT COUNT(*) FROM acceptance_ack_attempts) < ?8
      RETURNING *`,
    )
    .bind(
      ack.mutationId,
      ack.expectedRevision,
      ack.accountRevision,
      ack.scopeRevision,
      bodySha256,
      ackSha256,
      receiptSha256,
      maxAttempts,
    )
    .first<AttemptRow>();
  if (attempt) {
    console.log(
      ackLossLabel(fixture) +
        '_ATTEMPT=' +
        JSON.stringify(auditAttempt(fixture, attempt)),
    );
  }
  if (attempt?.drop_ack !== 1) return response;

  await response.body?.cancel().catch(() => {});
  const headers = new Headers(response.headers);
  headers.delete('Content-Length');
  const prefix = new TextEncoder().encode(ack.ackText.slice(0, 16));
  let sent = false;
  return new Response(
    new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (!sent) {
          sent = true;
          controller.enqueue(prefix);
          return;
        }
        // Let workerd flush the 200 headers before failing the response body.
        await new Promise<void>((resolve) => setTimeout(resolve, 250));
        controller.error(new Error('Acceptance interrupted the mutation ACK'));
      },
    }),
    { status: response.status, statusText: response.statusText, headers },
  );
}
