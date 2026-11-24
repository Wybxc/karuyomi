import { create, toJson, type MessageInitShape } from '@bufbuild/protobuf';
import {
  BrowsingHistoryResponseSchema,
  BusinessStateErrorCode as ErrorCode,
  LibraryMetadataSchema,
} from '@karuyomi/protocol';
import {
  BROWSING_HISTORY_LIMIT,
  LIBRARY_METADATA_LIMIT,
  businessSchemaVersion,
  parseMessage,
  recordBrowsingVisitSchema,
  validateLibraryMetadata,
} from '@karuyomi/contracts';
import { Hono, type Context } from 'hono';
import type { AppEnv } from './env.js';
import { requestJson, stateFailure } from './business-request.js';
import { mangaMetadataKey, StateError } from './state-store.js';

function reply(
  c: Context<AppEnv>,
  result: MessageInitShape<typeof BrowsingHistoryResponseSchema> = {},
  status: 200 | 400 | 403 | 409 | 413 | 503 = 200,
) {
  return c.json(
    toJson(
      BrowsingHistoryResponseSchema,
      create(BrowsingHistoryResponseSchema, {
        ...result,
        schemaVersion: businessSchemaVersion,
      }),
    ),
    status,
  );
}

function mangaKey(value: string): string {
  if (!/^[a-f0-9]{64}$/.test(value))
    throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid manga key');
  return value;
}

export function createHistoryRoutes() {
  const app = new Hono<AppEnv>();
  app.use('*', async (c, next) => {
    if (c.req.header('X-App-Subject') !== c.get('identity').subject) {
      return reply(
        c,
        {
          error: {
            code: ErrorCode.UNAVAILABLE,
            message: 'Client identity changed; sign in again',
            retryable: false,
          },
        },
        403,
      );
    }
    await next();
  });
  app.onError((error, c) => {
    const failure = stateFailure(
      error instanceof StateError
        ? error
        : new StateError(
            ErrorCode.UNAVAILABLE,
            'Browsing history is temporarily unavailable',
            503,
          ),
    );
    return reply(c, { error: failure.error }, failure.status);
  });
  app.get('/', async (c) => {
    const rows = await c.env.DB.prepare(
      `SELECT manga_key AS mangaKey, title, source_name AS sourceName,
          visited_at_ms AS visitedAtMs FROM browsing_history WHERE subject = ?
          ORDER BY visited_at_ms DESC, manga_key ASC LIMIT ?`,
    )
      .bind(c.get('identity').subject, BROWSING_HISTORY_LIMIT)
      .all<{
        mangaKey: string;
        title: string;
        sourceName: string;
        visitedAtMs: number;
      }>();
    return reply(c, {
      entries: rows.results.map((row) => ({
        ...row,
        visitedAtMs: BigInt(row.visitedAtMs),
      })),
    });
  });
  app.get('/:mangaKey', async (c) => {
    const key = mangaKey(c.req.param('mangaKey'));
    const encoded = await c.env.DB.prepare(
      'SELECT metadata_json FROM browsing_history WHERE subject = ? AND manga_key = ?',
    )
      .bind(c.get('identity').subject, key)
      .first<string>('metadata_json');
    if (encoded === null) return reply(c);
    const metadata = parseMessage(
      LibraryMetadataSchema,
      JSON.parse(encoded),
      LIBRARY_METADATA_LIMIT,
    );
    validateLibraryMetadata(metadata);
    if ((await mangaMetadataKey(metadata)) !== key)
      throw new Error('Stored history identity mismatch');
    return reply(c, { metadata });
  });
  app.post('/', async (c) => {
    const visitedAtMs = Date.now();
    let metadata;
    try {
      metadata = recordBrowsingVisitSchema.parse(await requestJson(c.req.raw));
    } catch (error) {
      if (error instanceof StateError) throw error;
      throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid browsing visit');
    }
    const manga = metadata.manga;
    if (!manga) throw new StateError(ErrorCode.INVALID_INPUT, 'Missing manga');
    const subject = c.get('identity').subject;
    const key = await mangaMetadataKey(metadata);
    const db = c.env.DB;
    await db.batch([
      db
        .prepare(
          `INSERT INTO browsing_history
          (subject, manga_key, title, source_name, metadata_json, visited_at_ms)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(subject, manga_key) DO UPDATE SET title = excluded.title,
            source_name = excluded.source_name, metadata_json = excluded.metadata_json,
            visited_at_ms = excluded.visited_at_ms
          WHERE excluded.visited_at_ms >= browsing_history.visited_at_ms`,
        )
        .bind(
          subject,
          key,
          [...manga.title].slice(0, 256).join(''),
          metadata.sourceName,
          JSON.stringify(toJson(LibraryMetadataSchema, metadata)),
          visitedAtMs,
        ),
      db
        .prepare(
          `DELETE FROM browsing_history WHERE subject = ? AND manga_key IN (
          SELECT manga_key FROM browsing_history WHERE subject = ?
          ORDER BY visited_at_ms DESC, manga_key ASC LIMIT -1 OFFSET ?)`,
        )
        .bind(subject, subject, BROWSING_HISTORY_LIMIT),
    ]);
    return reply(c);
  });
  app.delete('/:mangaKey', async (c) => {
    await c.env.DB.prepare(
      'DELETE FROM browsing_history WHERE subject = ? AND manga_key = ?',
    )
      .bind(c.get('identity').subject, mangaKey(c.req.param('mangaKey')))
      .run();
    return reply(c);
  });
  app.delete('/', async (c) => {
    await c.env.DB.prepare('DELETE FROM browsing_history WHERE subject = ?')
      .bind(c.get('identity').subject)
      .run();
    return reply(c);
  });
  return app;
}
