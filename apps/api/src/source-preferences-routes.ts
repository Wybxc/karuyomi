import { create, toJson } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  SourcePreferencesResponseSchema,
  CatalogReferenceSchema,
  SourcePreferencesMutationResponseSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  sourcePreferencesMutationSchema,
  validatePreferencePackageName,
  validateCatalogReference,
  preferenceSyncRulesForCatalog,
} from '@karuyomi/contracts';
import { Hono } from 'hono';
import type { AppEnv } from './env.js';
import { requestJson, stateFailure } from './business-request.js';
import {
  applySourcePreferencesMutation,
  readSourcePreferences,
} from './source-preferences-store.js';
import { StateError } from './state-store.js';

export function createSourcePreferencesRoutes() {
  const app = new Hono<AppEnv>();
  app.use('*', async (c, next) => {
    if (c.req.header('X-App-Subject') !== c.get('identity').subject) {
      const error = {
        code: ErrorCode.UNAVAILABLE,
        message: 'Client identity changed; sign in again',
        retryable: false,
      };
      return c.req.method === 'POST'
        ? c.json(
            toJson(
              SourcePreferencesMutationResponseSchema,
              create(SourcePreferencesMutationResponseSchema, {
                schemaVersion: businessSchemaVersion,
                error,
              }),
            ),
            403,
          )
        : c.json(
            toJson(
              SourcePreferencesResponseSchema,
              create(SourcePreferencesResponseSchema, {
                schemaVersion: businessSchemaVersion,
                error,
              }),
            ),
            403,
          );
    }
    await next();
  });
  app.get('/packages/:packageName', async (c) => {
    try {
      const packageName = c.req.param('packageName');
      const catalog = create(CatalogReferenceSchema, {
        catalogUrl: c.req.query('catalogUrl') ?? '',
        repoId: c.req.query('repoId') ?? '',
      });
      try {
        validatePreferencePackageName(packageName);
        validateCatalogReference(catalog);
      } catch {
        throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid package name');
      }
      return c.json(
        toJson(
          SourcePreferencesResponseSchema,
          await readSourcePreferences(
            c.env.DB,
            c.get('identity').subject,
            packageName,
            catalog,
            c.env.APP_ORIGIN,
          ),
        ),
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          SourcePreferencesResponseSchema,
          create(SourcePreferencesResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.post('/mutations', async (c) => {
    let mutationId = '';
    let catalog: ReturnType<
      typeof sourcePreferencesMutationSchema.parse
    >['catalog'];
    let syncRules: ReturnType<typeof preferenceSyncRulesForCatalog> = [];
    try {
      let mutation;
      try {
        mutation = sourcePreferencesMutationSchema.parse(
          await requestJson(c.req.raw),
        );
      } catch (error) {
        if (error instanceof StateError) throw error;
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Invalid Source preferences mutation',
        );
      }
      mutationId = mutation.mutationId;
      catalog = mutation.catalog;
      if (!catalog)
        throw new StateError(ErrorCode.INVALID_INPUT, 'Missing catalog');
      syncRules = preferenceSyncRulesForCatalog(
        mutation.packageName,
        catalog,
        c.env.APP_ORIGIN,
      );
      const result = await applySourcePreferencesMutation(
        c.env.DB,
        c.get('identity').subject,
        mutation,
        c.env.APP_ORIGIN,
      );
      return c.json(
        toJson(SourcePreferencesMutationResponseSchema, result.response),
        result.status,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          SourcePreferencesMutationResponseSchema,
          create(SourcePreferencesMutationResponseSchema, {
            schemaVersion: businessSchemaVersion,
            mutationId,
            ...(catalog ? { catalog, syncRules: [...syncRules] } : {}),
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  return app;
}
