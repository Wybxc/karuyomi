import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  httpRequestMetaSchema,
  httpResponseMetaSchema,
} from '@karuyomi/contracts';

export function bridgeErrorTarget(value: string | undefined): string {
  const url = value === undefined ? null : URL.parse(value);
  if (
    !url ||
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.hash
  ) {
    throw new Error(
      'ACCEPTANCE_BRIDGE_ERROR_URL must be an HTTPS URL without credentials or a fragment',
    );
  }
  return url.href;
}

export function shouldObserveBridgeError(
  request: Request,
  origin: string,
): boolean {
  const url = new URL(request.url);
  return (
    url.origin === origin &&
    url.hostname === '127.0.0.1' &&
    url.pathname === '/api/bridge/http' &&
    url.search === '' &&
    request.method === 'POST' &&
    request.headers.get('Origin') === origin &&
    request.headers.get('X-App-Request') === '1' &&
    request.headers.get('Content-Type') === HTTP_BRIDGE_MEDIA_TYPE &&
    request.headers.get('Accept') === HTTP_BRIDGE_MEDIA_TYPE
  );
}

export async function prepareBridgeError(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_bridge_error_attempts (
      sequence INTEGER PRIMARY KEY,
      request_id TEXT NOT NULL,
      runtime_generation TEXT NOT NULL,
      bridge_status INTEGER NOT NULL,
      upstream_status INTEGER,
      injected INTEGER NOT NULL CHECK (injected IN (0, 1))
    )`),
    db.prepare(`CREATE UNIQUE INDEX acceptance_bridge_error_once
      ON acceptance_bridge_error_attempts(injected) WHERE injected = 1`),
  ]);
}

export async function bridgeErrorAttempts(db: D1Database) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_bridge_error_attempts ORDER BY sequence')
    .all<{
      sequence: number;
      request_id: string;
      runtime_generation: string;
      bridge_status: number;
      upstream_status: number | null;
      injected: number;
    }>();
  return results;
}

export async function bridgeErrorRequest(target: string, clone: Request) {
  if (!clone.body) return;
  const input = new HttpFrameReader(clone.body, 0);
  try {
    const parsed = httpRequestMetaSchema.safeParse(await input.meta());
    if (
      parsed.success &&
      parsed.data.method === 'GET' &&
      !parsed.data.hasBody &&
      parsed.data.url === target &&
      (await input.read(HTTP_FRAME_LIMIT)) === null
    ) {
      const { requestId, runtimeGeneration } = parsed.data;
      return { requestId, runtimeGeneration };
    }
  } catch {
    // Let the actual bridge's response report any malformed request.
  } finally {
    void input.cancel().catch(() => {});
  }
}

export async function observeBridgeError(
  requestMeta: { requestId: string; runtimeGeneration: string },
  response: Response,
  db: D1Database,
): Promise<Response> {
  let upstreamStatus: number | null = null;
  if (
    response.ok &&
    response.headers.get('Content-Type') === HTTP_BRIDGE_MEDIA_TYPE
  ) {
    const body = response.clone().body;
    if (body) {
      const output = new HttpFrameReader(body, HTTP_RESPONSE_BODY_LIMIT);
      try {
        const parsed = httpResponseMetaSchema.safeParse(await output.meta());
        if (
          parsed.success &&
          parsed.data.requestId === requestMeta.requestId &&
          parsed.data.runtimeGeneration === requestMeta.runtimeGeneration
        ) {
          upstreamStatus = parsed.data.upstreamStatus;
        }
      } catch {
        // Do not replace an actual bridge error.
      } finally {
        // The original response's tee branch still belongs to the caller.
        void output.cancel().catch(() => {});
      }
    }
  }
  const eligible =
    upstreamStatus !== null && upstreamStatus >= 200 && upstreamStatus < 300;
  // One D1 statement claims the fixture even if two successful responses race.
  const attempt = await db
    .prepare(
      `INSERT INTO acceptance_bridge_error_attempts
      (request_id, runtime_generation, bridge_status, upstream_status, injected)
      VALUES (?1, ?2, ?3, ?4, CASE WHEN ?5 AND NOT EXISTS (
        SELECT 1 FROM acceptance_bridge_error_attempts WHERE injected = 1
      ) THEN 1 ELSE 0 END) RETURNING injected`,
    )
    .bind(
      requestMeta.requestId,
      requestMeta.runtimeGeneration,
      response.status,
      upstreamStatus,
      eligible ? 1 : 0,
    )
    .first<{ injected: number }>();
  if (attempt?.injected !== 1) return response;
  void response.body?.cancel().catch(() => {});
  // A pre-header network error permits automatic GET retry. This upstream
  // failure is an ordinary Source error and keeps the detail session usable.
  return Response.json(
    { error: 'upstream_body_error' },
    { status: 502, headers: { 'Cache-Control': 'private, no-store' } },
  );
}
