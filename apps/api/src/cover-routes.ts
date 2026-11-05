import { create, toJson } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  BUSINESS_REQUEST_LIMIT,
  COVER_BYTE_LIMIT,
  stateMutationSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode as ErrorCode,
  StateMutationResponseSchema,
} from '@karuyomi/protocol';
import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import type { AppEnv } from './env.js';
import { stateFailure } from './business-request.js';
import { uploadCover, verifyCoverImage } from './cover-store.js';
import { applyMutation, StateError } from './state-store.js';

export function createCoverRoutes() {
  const app = new Hono<AppEnv>();
  app.use('*', async (c, next) => {
    if (c.req.header('X-App-Subject') !== c.get('identity').subject) {
      return c.json(
        toJson(
          StateMutationResponseSchema,
          create(StateMutationResponseSchema, {
            schemaVersion: businessSchemaVersion,
            error: {
              code: ErrorCode.UNAVAILABLE,
              message: 'Client identity changed; sign in again',
              retryable: false,
            },
          }),
        ),
        403,
      );
    }
    await next();
  });
  app.post(
    '/:mangaKey',
    bodyLimit({
      maxSize: COVER_BYTE_LIMIT + BUSINESS_REQUEST_LIMIT + 16 * 1024,
      onError: (c) =>
        c.json(
          toJson(
            StateMutationResponseSchema,
            create(StateMutationResponseSchema, {
              schemaVersion: businessSchemaVersion,
              error: {
                code: ErrorCode.LIMIT_EXCEEDED,
                message: 'Cover upload exceeds the body limit',
                retryable: false,
              },
            }),
          ),
          413,
        ),
    }),
    async (c) => {
      let mutationId = '';
      try {
        if (!c.req.header('Content-Type')?.startsWith('multipart/form-data;'))
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Multipart cover upload is required',
          );
        let form;
        try {
          form = await c.req.formData();
        } catch {
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Invalid multipart upload',
          );
        }
        const entries = [...form.entries()];
        const control = form.get('mutation');
        const image = form.get('image');
        if (
          entries.length !== 2 ||
          typeof control !== 'string' ||
          !(image instanceof File) ||
          entries.some(([key]) => key !== 'mutation' && key !== 'image')
        )
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Upload requires exactly mutation and image fields',
          );
        if (
          new TextEncoder().encode(control).byteLength > BUSINESS_REQUEST_LIMIT
        )
          throw new StateError(
            ErrorCode.LIMIT_EXCEEDED,
            'Cover control exceeds the byte limit',
            413,
          );
        let mutation;
        try {
          mutation = stateMutationSchema.parse(JSON.parse(control));
        } catch {
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Invalid cover mutation',
          );
        }
        mutationId = mutation.mutationId;
        if (
          mutation.mangaKey !== c.req.param('mangaKey') ||
          mutation.operation.case !== 'setCustomCover' ||
          !mutation.operation.value.cover
        )
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Cover upload must match its manga and descriptor',
          );
        const cover = mutation.operation.value.cover;
        const bytes = await verifyCoverImage(image, cover);
        const result = await applyMutation(
          c.env.DB,
          c.get('identity').subject,
          mutation,
          () =>
            uploadCover(c.env.COVERS, c.get('identity').subject, cover, bytes),
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
    },
  );
  app.get('/:assetId', async (c) => {
    const row = await c.env.DB.prepare(
      'SELECT object_key, descriptor_json FROM cover_assets WHERE subject = ? AND asset_id = ?',
    )
      .bind(c.get('identity').subject, c.req.param('assetId'))
      .first<{ object_key: string; descriptor_json: string }>();
    if (!row) return c.notFound();
    const object = await c.env.COVERS.get(row.object_key);
    if (!object) return c.json({ error: 'cover_unavailable' }, 503);
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('Content-Length', String(object.size));
    headers.set('ETag', object.httpEtag);
    headers.set('Cache-Control', 'private, no-store');
    headers.set('X-Content-Type-Options', 'nosniff');
    return new Response(object.body, { headers });
  });
  return app;
}
