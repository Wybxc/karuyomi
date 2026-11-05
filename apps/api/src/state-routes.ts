import { create, toJson } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  LibraryPageResponseSchema,
  MangaStateResponseSchema,
  StateMutationResponseSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  BUSINESS_REQUEST_LIMIT,
  stateMutationSchema,
} from '@karuyomi/contracts';
import { Hono, type MiddlewareHandler } from 'hono';
import type { AppEnv } from './env.js';
import {
  applyMutation,
  readLibrary,
  readMangaState,
  StateError,
} from './state-store.js';

async function requestJson(request: Request): Promise<unknown> {
  if (!request.headers.get('Content-Type')?.startsWith('application/json')) {
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'JSON content type is required',
    );
  }
  const length = request.headers.get('Content-Length');
  if (length && Number(length) > BUSINESS_REQUEST_LIMIT)
    throw new StateError(
      ErrorCode.LIMIT_EXCEEDED,
      'Mutation body is too large',
      413,
    );
  const reader = request.body?.getReader();
  if (!reader)
    throw new StateError(ErrorCode.INVALID_INPUT, 'Mutation body is required');
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  let bytes = 0;
  let text = '';
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > BUSINESS_REQUEST_LIMIT) {
        await reader.cancel();
        throw new StateError(
          ErrorCode.LIMIT_EXCEEDED,
          'Mutation body is too large',
          413,
        );
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } finally {
    reader.releaseLock();
  }
}

function mangaKey(value: string): string {
  if (!/^[a-f0-9]{64}$/.test(value))
    throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid manga key');
  return value;
}

export function createStateRoutes() {
  const app = new Hono<AppEnv>();
  const bindSession: MiddlewareHandler<AppEnv> = async (c, next) => {
    if (c.req.header('X-App-Subject') !== c.get('identity').subject) {
      // This header only binds a client session. It never selects an account.
      const error = {
        code: ErrorCode.UNAVAILABLE,
        message: 'Client identity changed; sign in again',
        retryable: false,
      };
      if (c.req.path === '/api/library')
        return c.json(
          toJson(
            LibraryPageResponseSchema,
            create(LibraryPageResponseSchema, {
              schemaVersion: businessSchemaVersion,
              error,
            }),
          ),
          403,
        );
      if (c.req.path === '/api/state/mutations')
        return c.json(
          toJson(
            StateMutationResponseSchema,
            create(StateMutationResponseSchema, {
              schemaVersion: businessSchemaVersion,
              error,
            }),
          ),
          403,
        );
      return c.json(
        toJson(
          MangaStateResponseSchema,
          create(MangaStateResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error,
          }),
        ),
        403,
      );
    }
    await next();
  };
  app.use('/library', bindSession);
  app.use('/state/manga/:mangaKey', bindSession);
  app.use('/state/mutations', bindSession);
  app.get('/library', async (c) => {
    try {
      const after = c.req.query('afterKey') ?? '';
      if (after) mangaKey(after);
      const revisionText = c.req.query('revision');
      if (
        (after && revisionText === undefined) ||
        (revisionText !== undefined &&
          (!/^(0|[1-9][0-9]{0,9})$/.test(revisionText) ||
            Number(revisionText) > 0xffff_ffff))
      )
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Valid pagination revision is required',
        );
      const result = await readLibrary(
        c.env.DB,
        c.get('identity').subject,
        after,
        revisionText === undefined ? undefined : Number(revisionText),
      );
      return c.json(
        toJson(LibraryPageResponseSchema, result),
        result.error ? 409 : 200,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          LibraryPageResponseSchema,
          create(LibraryPageResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.get('/state/manga/:mangaKey', async (c) => {
    try {
      const key = mangaKey(c.req.param('mangaKey'));
      const chapter = c.req.query('chapterKey') ?? '';
      if (chapter.length > 4096)
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Chapter key is too long',
        );
      const result = await readMangaState(
        c.env.DB,
        c.get('identity').subject,
        key,
        chapter,
      );
      return c.json(toJson(MangaStateResponseSchema, result));
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          MangaStateResponseSchema,
          create(MangaStateResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.post('/state/mutations', async (c) => {
    let mutationId = '';
    try {
      let mutation;
      try {
        mutation = stateMutationSchema.parse(await requestJson(c.req.raw));
      } catch (error) {
        if (error instanceof StateError) throw error;
        throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid mutation');
      }
      mutationId = mutation.mutationId;
      const result = await applyMutation(
        c.env.DB,
        c.get('identity').subject,
        mutation,
      );
      return c.json(
        toJson(StateMutationResponseSchema, result.response),
        result.status,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          StateMutationResponseSchema,
          create(StateMutationResponseSchema, {
            schemaVersion: businessSchemaVersion,
            mutationId,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  return app;
}

function stateFailure(error: unknown) {
  const failure =
    error instanceof StateError
      ? error
      : new StateError(
          ErrorCode.UNAVAILABLE,
          'State is unavailable; retry with the same mutation ID',
          503,
        );
  return {
    status: failure.status,
    error: {
      code: failure.code,
      message: failure.message,
      retryable: failure.status === 503,
    },
  };
}
