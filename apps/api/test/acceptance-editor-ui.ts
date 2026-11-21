import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  categoryMutationSchema,
  settingsMutationSchema,
  sourcePreferencesMutationSchema,
  stateMutationSchema,
  staticManifestPathSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  CategoryMutationResponseSchema,
  SettingsMutationResponseSchema,
  SourcePreferencesMutationResponseSchema,
  StateMutationResponseSchema,
} from '@karuyomi/protocol';

const modes = [
  'pass',
  'hold-read',
  'delay-read',
  'fail-read',
  'fail-image',
  'hold-confirm',
  'delay-confirm',
  'confirm-read-failure',
  'confirm-next-loss',
  'lose-confirm',
  'reject-save',
  'login-required',
  'access-denied',
] as const;
type EditorUiMode = (typeof modes)[number];
export const editorUiScopes = [
  'manga',
  'global',
  'cover',
  'migration',
  'connection',
  'categories',
  'classification',
  'chapter-read',
  'preferences',
  'extension-manifest',
] as const;
type EditorUiScope = (typeof editorUiScopes)[number];
interface Control {
  mode: EditorUiMode;
  scope: EditorUiScope;
  generation: number;
}

export async function prepareEditorUi(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_editor_ui_control (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      mode TEXT NOT NULL, scope TEXT NOT NULL, generation INTEGER NOT NULL
    )`),
    db.prepare(
      "INSERT INTO acceptance_editor_ui_control VALUES (1, 'pass', 'manga', 0)",
    ),
    db.prepare(`CREATE TABLE acceptance_editor_ui_attempts (
      sequence INTEGER PRIMARY KEY, path TEXT NOT NULL, method TEXT NOT NULL,
      mode TEXT NOT NULL, body TEXT, worker_status INTEGER, client_status INTEGER
    )`),
  ]);
}

// Only the harness stdin can configure faults; no HTTP control endpoint exists.
export async function setEditorUiMode(
  db: D1Database,
  mode: string,
  scope: string,
) {
  if (
    !modes.some((value) => value === mode) ||
    !editorUiScopes.some((value) => value === scope)
  ) {
    throw new Error(
      'Expected an editor UI mode and ' + editorUiScopes.join('/') + ' scope',
    );
  }
  await db
    .prepare(
      'UPDATE acceptance_editor_ui_control SET mode = ?, scope = ?, generation = generation + 1 WHERE singleton = 1',
    )
    .bind(mode, scope)
    .run();
  return readControl(db);
}

async function readControl(db: D1Database): Promise<Control> {
  const control = await db
    .prepare(
      'SELECT mode, scope, generation FROM acceptance_editor_ui_control WHERE singleton = 1',
    )
    .first<Control>();
  if (!control) throw new Error('Editor UI fixture was not initialized');
  return control;
}

export async function editorUiAttempts(db: D1Database) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_editor_ui_attempts ORDER BY sequence')
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
  automaticDelayMs?: number,
): Promise<void> {
  // One-second polling keeps both manual gates and automatic delays bounded.
  // A manual timeout fails instead of claiming a successful release.
  const deadline = Date.now() + (automaticDelayMs ?? 30_000);
  signal.throwIfAborted();
  while ((await readControl(db)).generation === generation) {
    signal.throwIfAborted();
    if (Date.now() >= deadline) {
      if (automaticDelayMs !== undefined) return;
      throw new Error('Editor UI gate expired');
    }
    await new Promise<void>((resolve) => setTimeout(resolve, 1000));
  }
  signal.throwIfAborted();
}

export async function withEditorUi(
  request: Request,
  db: D1Database,
  origin: string,
  readJson: (request: Request) => Promise<unknown>,
  dispatch: () => Promise<Response>,
): Promise<Response> {
  const url = new URL(request.url);
  const defaultCatalog = origin + '/extensions/index.json';
  const preferencesReading =
    request.method === 'GET' &&
    /^\/api\/source-preferences\/packages\/[a-zA-Z0-9._-]{1,200}$/.test(
      url.pathname,
    ) &&
    url.searchParams.size === 2 &&
    url.searchParams.get('catalogUrl') === defaultCatalog &&
    !!url.searchParams.get('repoId');
  if (
    url.origin !== origin ||
    url.hostname !== '127.0.0.1' ||
    (url.search !== '' && !preferencesReading)
  )
    return dispatch();
  const bootstrapReading =
    request.method === 'GET' && url.pathname === '/api/bootstrap';
  const extensionManifestReading =
    request.method === 'GET' &&
    staticManifestPathSchema.safeParse(url.pathname).success;
  const settingsReading =
    request.method === 'GET' &&
    (url.pathname === '/api/settings' ||
      url.pathname.startsWith('/api/settings/manga/'));
  const mangaReading =
    request.method === 'GET' &&
    /^\/api\/state\/manga\/[a-f0-9]{64}$/.test(url.pathname);
  const coverImage =
    request.method === 'GET' && url.pathname.startsWith('/api/covers/');
  const settingsSaving =
    request.method === 'POST' && url.pathname === '/api/settings/mutations';
  const preferencesSaving =
    request.method === 'POST' &&
    url.pathname === '/api/source-preferences/mutations';
  const categoriesReading =
    request.method === 'GET' && url.pathname === '/api/categories';
  const libraryReading =
    request.method === 'GET' && url.pathname === '/api/library';
  const categoriesSaving =
    request.method === 'POST' && url.pathname === '/api/categories/mutations';
  const stateSaving =
    request.method === 'POST' && url.pathname === '/api/state/mutations';
  if (
    !bootstrapReading &&
    !extensionManifestReading &&
    !settingsReading &&
    !mangaReading &&
    !coverImage &&
    !settingsSaving &&
    !preferencesReading &&
    !preferencesSaving &&
    !categoriesReading &&
    !libraryReading &&
    !categoriesSaving &&
    !stateSaving
  )
    return dispatch();
  const settingsCommand = settingsSaving
    ? settingsMutationSchema.parse(await readJson(request.clone()))
    : undefined;
  const stateCommand = stateSaving
    ? stateMutationSchema.parse(await readJson(request.clone()))
    : undefined;
  const categoryCommand = categoriesSaving
    ? categoryMutationSchema.parse(await readJson(request.clone()))
    : undefined;
  const preferencesCommand = preferencesSaving
    ? sourcePreferencesMutationSchema.parse(await readJson(request.clone()))
    : undefined;
  if (
    preferencesCommand &&
    preferencesCommand.catalog?.catalogUrl !== defaultCatalog
  )
    return dispatch();
  const classificationSaving = stateCommand?.operation.case === 'setCategories';
  const chapterReadSaving = stateCommand?.operation.case === 'setChapterRead';
  // Regular reading progress and multipart uploads keep their normal behavior.
  const forwardOnlyState =
    stateCommand !== undefined &&
    !classificationSaving &&
    !chapterReadSaving &&
    stateCommand.operation.case !== 'migrateFrom' &&
    (stateCommand.operation.case !== 'setCustomCover' ||
      stateCommand.operation.value.cover !== undefined);
  const command =
    settingsCommand ?? stateCommand ?? categoryCommand ?? preferencesCommand;
  const control = await readControl(db);
  if (
    (libraryReading &&
      control.scope !== 'categories' &&
      control.scope !== 'classification') ||
    (extensionManifestReading && control.scope !== 'extension-manifest')
  )
    return dispatch();
  let scope: EditorUiScope = 'manga';
  if (
    categoriesReading ||
    categoryCommand ||
    (libraryReading && control.scope === 'categories')
  )
    scope = 'categories';
  else if (
    classificationSaving ||
    ((mangaReading || libraryReading) && control.scope === 'classification')
  )
    scope = 'classification';
  else if (chapterReadSaving) scope = 'chapter-read';
  else if (bootstrapReading) scope = 'connection';
  else if (extensionManifestReading) scope = 'extension-manifest';
  else if (preferencesReading || preferencesCommand) scope = 'preferences';
  else if (
    stateCommand?.operation.case === 'migrateFrom' ||
    (mangaReading && control.scope === 'migration')
  )
    scope = 'migration';
  else if (stateCommand || mangaReading || coverImage) scope = 'cover';
  else if (
    settingsCommand?.operation.case === 'setGlobal' ||
    (!settingsCommand && url.pathname === '/api/settings')
  )
    scope = 'global';
  const mode =
    !forwardOnlyState && control.scope === scope ? control.mode : 'pass';
  const reading =
    bootstrapReading ||
    extensionManifestReading ||
    settingsReading ||
    preferencesReading ||
    mangaReading ||
    categoriesReading ||
    libraryReading;
  // requestJson has already enforced the body bound before retaining exact bytes.
  const body = command ? await request.clone().text() : null;
  const inserted = await db
    .prepare(
      'INSERT INTO acceptance_editor_ui_attempts (path, method, mode, body) SELECT ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM acceptance_editor_ui_attempts) < 256 RETURNING sequence',
    )
    .bind(url.pathname, request.method, mode, body)
    .first<{ sequence: number }>();
  if (!inserted) throw new Error('Editor UI audit limit reached');
  const sequence = inserted.sequence;
  let workerStatus: number | null = null;
  let response: Response;
  if (mode === 'login-required') {
    response = new Response(
      '<!doctype html><title>Test Access login required</title>',
      { status: 401, headers: { 'Content-Type': 'text/html' } },
    );
  } else if (mode === 'access-denied') {
    response = new Response(
      '<!doctype html><title>Test Access denied</title>',
      { status: 403, headers: { 'Content-Type': 'text/html' } },
    );
  } else if (reading && mode === 'fail-read') {
    response = new Response('Injected editor read failure', { status: 503 });
  } else if (coverImage && mode === 'fail-image') {
    response = new Response('Injected cover image failure', { status: 503 });
  } else if (command && mode === 'reject-save') {
    const rejection = {
      schemaVersion: businessSchemaVersion,
      mutationId: command.mutationId,
      error: {
        code: BusinessStateErrorCode.INVALID_INPUT,
        message: 'Injected pre-dispatch rejection',
        retryable: false,
      },
    };
    response = new Response(
      categoryCommand
        ? toJsonString(
            CategoryMutationResponseSchema,
            create(CategoryMutationResponseSchema, rejection),
          )
        : stateCommand
          ? toJsonString(
              StateMutationResponseSchema,
              create(StateMutationResponseSchema, rejection),
            )
          : preferencesCommand
            ? toJsonString(
                SourcePreferencesMutationResponseSchema,
                create(SourcePreferencesMutationResponseSchema, {
                  ...rejection,
                  catalog: preferencesCommand.catalog,
                }),
              )
            : toJsonString(
                SettingsMutationResponseSchema,
                create(SettingsMutationResponseSchema, rejection),
              ),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  } else {
    if (reading && (mode === 'hold-read' || mode === 'delay-read'))
      await waitForRelease(
        db,
        control.generation,
        request.signal,
        mode === 'delay-read' ? 5_000 : undefined,
      );
    response = await dispatch();
    workerStatus = response.status;
    if (
      command &&
      (mode === 'hold-confirm' ||
        mode === 'delay-confirm' ||
        mode === 'confirm-read-failure' ||
        mode === 'confirm-next-loss')
    ) {
      await waitForRelease(
        db,
        control.generation,
        request.signal,
        mode === 'hold-confirm' ? undefined : 2_000,
      );
      if (
        (mode === 'confirm-read-failure' || mode === 'confirm-next-loss') &&
        response.ok
      ) {
        // Arm only this generation. An explicit control change wins over a
        // delayed response and must never be replaced by its scheduled fault.
        await db
          .prepare(
            'UPDATE acceptance_editor_ui_control SET mode = ?, generation = generation + 1 WHERE singleton = 1 AND generation = ? AND scope = ?',
          )
          .bind(
            mode === 'confirm-read-failure' ? 'fail-read' : 'lose-confirm',
            control.generation,
            control.scope,
          )
          .run();
      }
    }
    if (command && mode === 'lose-confirm' && response.ok) {
      // The real transaction has committed. Only delivery of its ACK is lost.
      response = new Response('Injected committed editor ACK loss', {
        status: 502,
      });
    }
  }
  await db
    .prepare(
      'UPDATE acceptance_editor_ui_attempts SET worker_status = ?, client_status = ? WHERE sequence = ?',
    )
    .bind(workerStatus, response.status, sequence)
    .run();
  return response;
}
