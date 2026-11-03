import { Hono } from 'hono';
import { buildManifestSchema } from '@karuyomi/contracts';
import type { AppEnv } from './app.js';

export interface ArtifactRecord {
  sha256: string;
  objectKey: string;
  size: number;
  contentType: string;
}

export interface ExtensionStore {
  list(after: string): Promise<{ buildId: string; manifestJson: string }[]>;
  manifest(buildId: string): Promise<string | null>;
  artifact(sha256: string): Promise<ArtifactRecord | null>;
}

export function d1ExtensionStore(db: D1Database): ExtensionStore {
  return {
    async list(after) {
      const result = await db
        .prepare(
          'SELECT build_id AS buildId, manifest_json AS manifestJson FROM extension_builds WHERE status = ? AND build_id > ? ORDER BY build_id LIMIT 26',
        )
        .bind('verified', after)
        .all<{ buildId: string; manifestJson: string }>();
      return result.results;
    },
    async manifest(buildId) {
      const row = await db
        .prepare(
          'SELECT manifest_json FROM extension_builds WHERE build_id = ? AND status = ?',
        )
        .bind(buildId, 'verified')
        .first<{ manifest_json: string }>();
      return row?.manifest_json ?? null;
    },
    async artifact(sha256) {
      return db
        .prepare(
          `SELECT a.sha256, a.object_key AS objectKey, a.size, a.content_type AS contentType
        FROM extension_artifacts a WHERE a.sha256 = ? AND EXISTS (
          SELECT 1 FROM build_artifacts ba JOIN extension_builds b ON b.build_id = ba.build_id
          WHERE ba.sha256 = a.sha256 AND b.status = 'verified')`,
        )
        .bind(sha256)
        .first<ArtifactRecord>();
    },
  };
}

/** A single byte range; multipart ranges are intentionally not implemented. */
export function byteRange(
  value: string,
  size: number,
): { offset: number; length: number } | null {
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match || size === 0 || (!match[1] && !match[2])) return null;
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) return null;
    const length = Math.min(size, suffix);
    return { offset: size - length, length };
  }
  const start = Number(match[1]);
  const end = match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    start >= size ||
    start > end
  )
    return null;
  return { offset: start, length: end - start + 1 };
}

const types = new Set([
  'application/javascript',
  'text/javascript',
  'application/wasm',
  'application/octet-stream',
  'application/json',
]);

export function createExtensionRoutes(
  storeFactory: (env: AppEnv['Bindings']) => ExtensionStore = (env) =>
    d1ExtensionStore(env.DB),
) {
  const app = new Hono<AppEnv>();
  app.get('/builds', async (c) => {
    const cursor = c.req.query('cursor') ?? '';
    if (cursor.length > 200 || (cursor && !/^[a-zA-Z0-9._-]+$/.test(cursor)))
      return c.json({ error: 'invalid_cursor' }, 400);
    const records = await storeFactory(c.env).list(cursor);
    const builds = [];
    try {
      for (const record of records.slice(0, 25)) {
        const manifest = buildManifestSchema.parse(
          JSON.parse(record.manifestJson),
        );
        if (manifest.buildId !== record.buildId)
          throw new Error('Invalid build');
        builds.push({
          buildId: manifest.buildId,
          packageName: manifest.packageName,
          repoId: manifest.repoId,
          version: manifest.version,
          sourceIds: manifest.sourceIds,
          manifestPath: `/api/extensions/builds/${manifest.buildId}/manifest`,
        });
      }
    } catch {
      return c.json({ error: 'invalid_build_manifest' }, 503);
    }
    return c.json({
      builds,
      nextCursor: records.length > 25 ? records[24]!.buildId : null,
    });
  });
  app.get('/builds/:buildId/manifest', async (c) => {
    const buildId = c.req.param('buildId');
    if (!/^[a-zA-Z0-9._-]{1,200}$/.test(buildId))
      return c.json({ error: 'invalid_build_id' }, 400);
    const value = await storeFactory(c.env).manifest(buildId);
    if (value === null) return c.json({ error: 'build_not_found' }, 404);
    let parsed: unknown;
    try {
      parsed = JSON.parse(value);
    } catch {
      return c.json({ error: 'invalid_build_manifest' }, 503);
    }
    const manifest = buildManifestSchema.safeParse(parsed);
    if (!manifest.success || manifest.data.buildId !== buildId)
      return c.json({ error: 'invalid_build_manifest' }, 503);
    return c.json(manifest.data);
  });
  app.on(['GET', 'HEAD'], '/artifacts/:sha256', async (c) => {
    const hash = c.req.param('sha256');
    if (!/^[a-f0-9]{64}$/.test(hash))
      return c.json({ error: 'invalid_artifact_hash' }, 400);
    const record = await storeFactory(c.env).artifact(hash);
    if (!record) return c.json({ error: 'artifact_not_found' }, 404);
    if (
      record.sha256 !== hash ||
      record.objectKey !== `artifacts/${hash}` ||
      !Number.isSafeInteger(record.size) ||
      record.size <= 0 ||
      !types.has(record.contentType)
    ) {
      return c.json({ error: 'invalid_artifact_metadata' }, 503);
    }
    const metadata = await c.env.ARTIFACTS.head(record.objectKey);
    if (
      !metadata ||
      metadata.size !== record.size ||
      metadata.httpMetadata?.contentEncoding
    ) {
      return c.json({ error: 'artifact_unavailable' }, 503);
    }
    // Authentication has already run before metadata, conditional or range work.
    const etag = `"${hash}"`;
    const headers = new Headers({
      'Content-Type': record.contentType,
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'private, no-cache',
      ETag: etag,
      'Accept-Ranges': 'bytes',
    });
    const condition = c.req.header('If-None-Match');
    if (
      condition
        ?.split(',')
        .map((v) => v.trim().replace(/^W\//, ''))
        .some((v) => v === etag || v === '*')
    ) {
      return new Response(null, { status: 304, headers });
    }
    const requestedRange = c.req.header('Range');
    const ifRange = c.req.header('If-Range');
    const range =
      requestedRange && (!ifRange || ifRange === etag)
        ? byteRange(requestedRange, record.size)
        : undefined;
    if (range === null) {
      headers.set('Content-Range', `bytes */${record.size}`);
      return new Response(null, { status: 416, headers });
    }
    headers.set('Content-Length', String(range?.length ?? record.size));
    if (range)
      headers.set(
        'Content-Range',
        `bytes ${range.offset}-${range.offset + range.length - 1}/${record.size}`,
      );
    if (c.req.method === 'HEAD')
      return new Response(null, { status: range ? 206 : 200, headers });
    const object = await c.env.ARTIFACTS.get(
      record.objectKey,
      range ? { range } : undefined,
    );
    if (!object || object.size !== record.size)
      return c.json({ error: 'artifact_unavailable' }, 503);
    return new Response(object.body, { status: range ? 206 : 200, headers });
  });
  return app;
}
