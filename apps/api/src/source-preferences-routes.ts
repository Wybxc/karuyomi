import { create, toJson } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  SourcePreferencesResponseSchema,
  CatalogReferenceSchema,
  SourcePreferencesMutationResponseSchema,
  type CatalogReference,
  type PreferenceSyncRule,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  sourcePreferencesMutationSchema,
  validatePreferencePackageName,
  validateCatalogReference,
  preferenceRulesAssetPath,
  preferenceRulesAssetSchema,
} from '@karuyomi/contracts';
import { Hono } from 'hono';
import type { AppEnv } from './env.js';
import { requestJson, stateFailure } from './business-request.js';
import {
  applySourcePreferencesMutation,
  readSourcePreferences,
} from './source-preferences-store.js';
import { StateError } from './state-store.js';

async function currentSyncRules(
  assets: Fetcher,
  appOrigin: string,
  catalog: CatalogReference,
  packageName: string,
): Promise<PreferenceSyncRule[]> {
  if (catalog.catalogUrl !== appOrigin + '/extensions/index.json') return [];
  const response = await assets.fetch(appOrigin + preferenceRulesAssetPath);
  if (!response.ok)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Source preference metadata is unavailable',
      503,
    );
  const metadata = preferenceRulesAssetSchema.parse(await response.json());
  if (
    metadata.repoId !== catalog.repoId ||
    !Object.hasOwn(metadata.packages, packageName)
  )
    return [];
  return metadata.packages[packageName] ?? [];
}

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
      const rules = await currentSyncRules(
        c.env.ASSETS,
        c.env.APP_ORIGIN,
        catalog,
        packageName,
      );
      return c.json(
        toJson(
          SourcePreferencesResponseSchema,
          await readSourcePreferences(
            c.env.DB,
            c.get('identity').subject,
            packageName,
            catalog,
            rules,
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
    let syncRules: PreferenceSyncRule[] = [];
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
      syncRules = await currentSyncRules(
        c.env.ASSETS,
        c.env.APP_ORIGIN,
        catalog,
        mutation.packageName,
      );
      const result = await applySourcePreferencesMutation(
        c.env.DB,
        c.get('identity').subject,
        mutation,
        syncRules,
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
