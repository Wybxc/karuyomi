import { create, toJson } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  LibraryPageResponseSchema,
  BookmarkPageResponseSchema,
  ChapterProgressPageResponseSchema,
  MangaStateResponseSchema,
  StateMutationResponseSchema,
  CategoryCatalogResponseSchema,
  CategoryMutationResponseSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  stateMutationSchema,
  categoryMutationSchema,
} from '@karuyomi/contracts';
import { Hono, type MiddlewareHandler } from 'hono';
import type { AppEnv } from './env.js';
import { requestJson, stateFailure } from './business-request.js';
import {
  applyMutation,
  readLibrary,
  readBookmarkPage,
  readChapterProgressPage,
  readMangaState,
  StateError,
  readCategoryCatalog,
  applyCategoryMutation,
} from './state-store.js';

function mangaKey(value: string): string {
  if (!/^[a-f0-9]{64}$/.test(value))
    throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid manga key');
  return value;
}

function chapterKey(value: string): string {
  if (!value || value.length > 200)
    throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid chapter key');
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
      if (
        c.req.path === '/api/categories' ||
        c.req.path === '/api/categories/mutations'
      ) {
        if (c.req.path === '/api/categories')
          return c.json(
            toJson(
              CategoryCatalogResponseSchema,
              create(CategoryCatalogResponseSchema, {
                schemaVersion: businessSchemaVersion,
                error,
              }),
            ),
            403,
          );
        return c.json(
          toJson(
            CategoryMutationResponseSchema,
            create(CategoryMutationResponseSchema, {
              schemaVersion: businessSchemaVersion,
              error,
            }),
          ),
          403,
        );
      }
      if (c.req.path.endsWith('/bookmarks'))
        return c.json(
          toJson(
            BookmarkPageResponseSchema,
            create(BookmarkPageResponseSchema, {
              schemaVersion: businessSchemaVersion,
              error,
            }),
          ),
          403,
        );
      if (c.req.path.endsWith('/progress'))
        return c.json(
          toJson(
            ChapterProgressPageResponseSchema,
            create(ChapterProgressPageResponseSchema, {
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
  app.use('/state/manga/:mangaKey/bookmarks', bindSession);
  app.use('/state/manga/:mangaKey/progress', bindSession);
  app.use('/state/mutations', bindSession);
  app.use('/categories', bindSession);
  app.use('/categories/mutations', bindSession);
  app.get('/categories', async (c) => {
    try {
      return c.json(
        toJson(
          CategoryCatalogResponseSchema,
          await readCategoryCatalog(c.env.DB, c.get('identity').subject),
        ),
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          CategoryCatalogResponseSchema,
          create(CategoryCatalogResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.post('/categories/mutations', async (c) => {
    let mutationId = '';
    try {
      let mutation;
      try {
        mutation = categoryMutationSchema.parse(await requestJson(c.req.raw));
      } catch (error) {
        if (error instanceof StateError) throw error;
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Invalid category mutation',
        );
      }
      mutationId = mutation.mutationId;
      const result = await applyCategoryMutation(
        c.env.DB,
        c.get('identity').subject,
        mutation,
      );
      return c.json(
        toJson(CategoryMutationResponseSchema, result.response),
        result.status,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          CategoryMutationResponseSchema,
          create(CategoryMutationResponseSchema, {
            schemaVersion: businessSchemaVersion,
            mutationId,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
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
  app.get('/state/manga/:mangaKey/bookmarks', async (c) => {
    try {
      const key = mangaKey(c.req.param('mangaKey'));
      const after = c.req.query('afterKey') ?? '';
      if (after) chapterKey(after);
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
      const result = await readBookmarkPage(
        c.env.DB,
        c.get('identity').subject,
        key,
        after,
        revisionText === undefined ? undefined : Number(revisionText),
      );
      return c.json(
        toJson(BookmarkPageResponseSchema, result),
        result.error ? 409 : 200,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          BookmarkPageResponseSchema,
          create(BookmarkPageResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.get('/state/manga/:mangaKey/progress', async (c) => {
    try {
      const key = mangaKey(c.req.param('mangaKey'));
      const after = c.req.query('afterKey') ?? '';
      if (after) chapterKey(after);
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
      const result = await readChapterProgressPage(
        c.env.DB,
        c.get('identity').subject,
        key,
        after,
        revisionText === undefined ? undefined : Number(revisionText),
      );
      return c.json(
        toJson(ChapterProgressPageResponseSchema, result),
        result.error ? 409 : 200,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          ChapterProgressPageResponseSchema,
          create(ChapterProgressPageResponseSchema, {
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
      if (chapter) chapterKey(chapter);
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
      if (
        mutation.operation.case === 'setCustomCover' &&
        mutation.operation.value.cover
      )
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Cover images require multipart upload',
        );
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
