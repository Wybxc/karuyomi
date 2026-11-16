import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  settingsMutationSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  SettingsMutationResponseSchema,
} from '@karuyomi/protocol';

const modes = [
  'pass',
  'hold-read',
  'fail-read',
  'hold-confirm',
  'lose-confirm',
  'reject-save',
  'login-required',
] as const;
type SettingsUiMode = (typeof modes)[number];
type SettingsUiScope = 'manga' | 'global';
interface Control {
  mode: SettingsUiMode;
  scope: SettingsUiScope;
  generation: number;
}

export async function prepareSettingsUi(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_settings_ui_control (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      mode TEXT NOT NULL, scope TEXT NOT NULL, generation INTEGER NOT NULL
    )`),
    db.prepare(
      "INSERT INTO acceptance_settings_ui_control VALUES (1, 'pass', 'manga', 0)",
    ),
    db.prepare(`CREATE TABLE acceptance_settings_ui_attempts (
      sequence INTEGER PRIMARY KEY, path TEXT NOT NULL, method TEXT NOT NULL,
      mode TEXT NOT NULL, body TEXT, worker_status INTEGER, client_status INTEGER
    )`),
  ]);
}

// Only the harness stdin can configure faults; no HTTP control endpoint exists.
export async function setSettingsUiMode(
  db: D1Database,
  mode: string,
  scope: string,
) {
  if (
    !modes.some((value) => value === mode) ||
    (scope !== 'manga' && scope !== 'global')
  ) {
    throw new Error('Expected a settings UI mode and manga/global scope');
  }
  await db
    .prepare(
      'UPDATE acceptance_settings_ui_control SET mode = ?, scope = ?, generation = generation + 1 WHERE singleton = 1',
    )
    .bind(mode, scope)
    .run();
  return readControl(db);
}

async function readControl(db: D1Database): Promise<Control> {
  const control = await db
    .prepare(
      'SELECT mode, scope, generation FROM acceptance_settings_ui_control WHERE singleton = 1',
    )
    .first<Control>();
  if (!control) throw new Error('Settings UI fixture was not initialized');
  return control;
}

export async function settingsUiAttempts(db: D1Database) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_settings_ui_attempts ORDER BY sequence')
    .all<{
      sequence: number;
      path: string;
      method: string;
      mode: string;
      body: string | null;
      worker_status: number | null;
      client_status: number | null;
    }>();
  return results;
}

async function waitForRelease(
  db: D1Database,
  generation: number,
  signal: AbortSignal,
): Promise<void> {
  // Bounded, one-second polling keeps the local fixture inexpensive. A timeout
  // fails the request instead of silently claiming that the gate was released.
  const deadline = Date.now() + 30_000;
  signal.throwIfAborted();
  while ((await readControl(db)).generation === generation) {
    signal.throwIfAborted();
    if (Date.now() >= deadline) throw new Error('Settings UI gate expired');
    await new Promise<void>((resolve) => setTimeout(resolve, 1000));
  }
  signal.throwIfAborted();
}

export async function withSettingsUi(
  request: Request,
  db: D1Database,
  origin: string,
  readJson: (request: Request) => Promise<unknown>,
  dispatch: () => Promise<Response>,
): Promise<Response> {
  const url = new URL(request.url);
  if (
    url.origin !== origin ||
    url.hostname !== '127.0.0.1' ||
    url.search !== ''
  )
    return dispatch();
  const reading =
    request.method === 'GET' &&
    (url.pathname === '/api/settings' ||
      url.pathname.startsWith('/api/settings/manga/'));
  const saving =
    request.method === 'POST' && url.pathname === '/api/settings/mutations';
  if (!reading && !saving) return dispatch();
  const command = saving
    ? settingsMutationSchema.parse(await readJson(request.clone()))
    : undefined;
  const scope = command
    ? command.operation.case === 'setGlobal'
      ? 'global'
      : 'manga'
    : url.pathname === '/api/settings'
      ? 'global'
      : 'manga';
  const control = await readControl(db);
  const mode = control.scope === scope ? control.mode : 'pass';
  // requestJson has already enforced the body bound before retaining exact bytes.
  const body = saving ? await request.clone().text() : null;
  const inserted = await db
    .prepare(
      'INSERT INTO acceptance_settings_ui_attempts (path, method, mode, body) SELECT ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM acceptance_settings_ui_attempts) < 256 RETURNING sequence',
    )
    .bind(url.pathname, request.method, mode, body)
    .first<{ sequence: number }>();
  if (!inserted) throw new Error('Settings UI audit limit reached');
  const sequence = inserted.sequence;
  let workerStatus: number | null = null;
  let response: Response;
  if (mode === 'login-required') {
    response = new Response(
      '<!doctype html><title>Test Access login required</title>',
      { status: 401, headers: { 'Content-Type': 'text/html' } },
    );
  } else if (reading && mode === 'fail-read') {
    response = new Response('Injected settings read failure', { status: 503 });
  } else if (command && mode === 'reject-save') {
    response = new Response(
      toJsonString(
        SettingsMutationResponseSchema,
        create(SettingsMutationResponseSchema, {
          schemaVersion: businessSchemaVersion,
          mutationId: command.mutationId,
          error: {
            code: BusinessStateErrorCode.INVALID_INPUT,
            message: 'Injected pre-dispatch rejection',
            retryable: false,
          },
        }),
      ),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  } else {
    if (reading && mode === 'hold-read')
      await waitForRelease(db, control.generation, request.signal);
    response = await dispatch();
    workerStatus = response.status;
    if (command && mode === 'hold-confirm')
      await waitForRelease(db, control.generation, request.signal);
    if (command && mode === 'lose-confirm' && response.ok) {
      // The real transaction has committed. Only delivery of its ACK is lost.
      response = new Response('Injected committed settings ACK loss', {
        status: 502,
      });
    }
  }
  await db
    .prepare(
      'UPDATE acceptance_settings_ui_attempts SET worker_status = ?, client_status = ? WHERE sequence = ?',
    )
    .bind(workerStatus, response.status, sequence)
    .run();
  return response;
}
