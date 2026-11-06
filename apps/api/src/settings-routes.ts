import { create, toJson } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  SettingsMutationResponseSchema,
  SettingsResponseSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  settingsMutationSchema,
} from '@karuyomi/contracts';
import { Hono } from 'hono';
import type { AppEnv } from './env.js';
import { requestJson, stateFailure } from './business-request.js';
import { applySettingsMutation, readSettings } from './settings-store.js';
import { StateError } from './state-store.js';

export function createSettingsRoutes() {
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
              SettingsMutationResponseSchema,
              create(SettingsMutationResponseSchema, {
                schemaVersion: businessSchemaVersion,
                error,
              }),
            ),
            403,
          )
        : c.json(
            toJson(
              SettingsResponseSchema,
              create(SettingsResponseSchema, {
                schemaVersion: businessSchemaVersion,
                error,
              }),
            ),
            403,
          );
    }
    await next();
  });
  app.get('/', async (c) => {
    try {
      return c.json(
        toJson(
          SettingsResponseSchema,
          await readSettings(c.env.DB, c.get('identity').subject),
        ),
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          SettingsResponseSchema,
          create(SettingsResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: failure.error,
          }),
        ),
        failure.status,
      );
    }
  });
  app.get('/manga/:mangaKey', async (c) => {
    try {
      const key = c.req.param('mangaKey');
      if (!/^[a-f0-9]{64}$/.test(key))
        throw new StateError(ErrorCode.INVALID_INPUT, 'Invalid manga key');
      return c.json(
        toJson(
          SettingsResponseSchema,
          await readSettings(c.env.DB, c.get('identity').subject, key),
        ),
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          SettingsResponseSchema,
          create(SettingsResponseSchema, {
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
    try {
      let mutation;
      try {
        mutation = settingsMutationSchema.parse(await requestJson(c.req.raw));
      } catch (error) {
        if (error instanceof StateError) throw error;
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Invalid settings mutation',
        );
      }
      if (
        mutation.operation.case === 'setGlobal' &&
        mutation.operation.value.repositories.some(
          (repository) =>
            repository.catalogUrl ===
            `${c.env.APP_ORIGIN}/extensions/index.json`,
        )
      ) {
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'The default repository is implicit and cannot be registered twice',
        );
      }
      mutationId = mutation.mutationId;
      const result = await applySettingsMutation(
        c.env.DB,
        c.get('identity').subject,
        mutation,
      );
      return c.json(
        toJson(SettingsMutationResponseSchema, result.response),
        result.status,
      );
    } catch (error) {
      const failure = stateFailure(error);
      return c.json(
        toJson(
          SettingsMutationResponseSchema,
          create(SettingsMutationResponseSchema, {
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
