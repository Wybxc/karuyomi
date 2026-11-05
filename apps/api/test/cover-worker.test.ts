import { create, toJson } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  COVER_BYTE_LIMIT,
  libraryPageResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode as ErrorCode,
  StateMutationSchema,
  type StateMutation,
} from '@karuyomi/protocol';
import { env, exports } from 'cloudflare:workers';
import { applyD1Migrations } from 'cloudflare:test';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { createHash } from 'node:crypto';
import { beforeAll, expect, test } from 'vitest';
import {
  cleanupCoverOrphans,
  COVER_ORPHAN_GRACE_MS,
} from '../../../tools/cloudflare/cover-orphans.ts';

const origin = 'https://read.example.com';
const png = Uint8Array.from(
  Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=',
    'base64',
  ),
);
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'cover-fixture';
  env.PROBE_ACCESS_JWKS = JSON.stringify({ keys: [jwk] });
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}, 30000);

async function client(subject: string = crypto.randomUUID()) {
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'cover-fixture' })
    .setSubject(subject)
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('state-fixture')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  return {
    subject,
    async request(path: string, options: RequestInit = {}) {
      const headers = new Headers({
        'Cf-Access-Jwt-Assertion': token,
        'X-App-Subject': subject,
      });
      new Headers(options.headers).forEach((value, key) =>
        headers.set(key, value),
      );
      return exports.default.fetch(`${origin}${path}`, {
        ...options,
        headers: [...headers.entries()],
      });
    },
    async upload(mutation: StateMutation, bytes = png, type = 'image/png') {
      const form = new FormData();
      form.set(
        'mutation',
        JSON.stringify(toJson(StateMutationSchema, mutation)),
      );
      form.set('image', new File([bytes], 'cover.png', { type }));
      const response = await this.request(`/api/covers/${mutation.mangaKey}`, {
        method: 'POST',
        headers: { Origin: origin, 'X-App-Request': '1' },
        body: form,
      });
      return {
        status: response.status,
        body: stateMutationResponseSchema.parse(await response.json()),
      };
    },
    async mutate(mutation: StateMutation) {
      const response = await this.request('/api/state/mutations', {
        method: 'POST',
        headers: {
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(toJson(StateMutationSchema, mutation)),
      });
      return {
        status: response.status,
        body: stateMutationResponseSchema.parse(await response.json()),
      };
    },
    async state(key: string) {
      const response = await this.request(`/api/state/manga/${key}`);
      expect(response.status).toBe(200);
      return mangaStateResponseSchema.parse(await response.json());
    },
  };
}
function command(key: string, revision = 0, bytes = png) {
  return create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: key,
    expectedRevision: revision,
    operation: {
      case: 'setCustomCover',
      value: {
        cover: {
          assetId: crypto.randomUUID(),
          contentType: 'image/png',
          byteLength: bytes.byteLength,
          sha256: createHash('sha256').update(bytes).digest('hex'),
        },
      },
    },
  });
}
function assetId(mutation: StateMutation) {
  if (
    mutation.operation.case !== 'setCustomCover' ||
    !mutation.operation.value.cover
  )
    throw new Error('Cover missing');
  return mutation.operation.value.cover.assetId;
}
function clear(key: string, revision: number) {
  return create(StateMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    mangaKey: key,
    expectedRevision: revision,
    operation: { case: 'setCustomCover', value: {} },
  });
}
async function objectKeys(subject: string) {
  const prefix = `covers/${createHash('sha256').update(subject).digest('hex')}/`;
  return (await env.COVERS.list({ prefix })).objects.map(
    (object) => object.key,
  );
}

test('private covers round trip through verified subjects and current D1/library references while Source updates preserve them', async () => {
  const owner = await client();
  const metadata = {
    packageName: 'eu.kanade.tachiyomi.extension.en.fixture',
    sourceId: '123',
    sourceName: 'Fixture',
    sourceLang: 'en',
    manga: { url: '/manga', title: 'Original' },
  };
  const key = createHash('sha256')
    .update(
      JSON.stringify([
        metadata.packageName,
        metadata.sourceId,
        metadata.manga.url,
      ]),
    )
    .digest('hex');
  const upload = command(key);
  const saved = await owner.upload(upload);
  expect(saved.status).toBe(200);
  expect(saved.body.manga?.customCover?.assetId).toBe(assetId(upload));
  const favorite = create(StateMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    mangaKey: key,
    expectedRevision: 1,
    operation: { case: 'setFavorite', value: { favorite: true, metadata } },
  });
  expect((await owner.mutate(favorite)).status).toBe(200);
  const second = await client(owner.subject);
  expect((await second.state(key)).manga?.customCover).toEqual(
    saved.body.manga?.customCover,
  );
  const response = await second.request(`/api/covers/${assetId(upload)}`);
  expect(response.status).toBe(200);
  expect(response.headers.get('Content-Type')).toBe('image/png');
  expect(response.headers.get('Cache-Control')).toBe('private, no-store');
  expect(response.headers.get('Content-Length')).toBe(String(png.byteLength));
  expect(new Uint8Array(await response.arrayBuffer())).toEqual(png);
  const library = await second.request('/api/library');
  expect(
    libraryPageResponseSchema.parse(await library.json()).entries[0]
      ?.customCover,
  ).toEqual(saved.body.manga?.customCover);
  const other = await client();
  expect((await other.request(`/api/covers/${assetId(upload)}`)).status).toBe(
    404,
  );
  expect(
    (
      await other.request(`/api/covers/${assetId(upload)}`, {
        headers: { 'X-App-Subject': owner.subject },
      })
    ).status,
  ).toBe(403);
  expect(
    (await exports.default.fetch(`${origin}/api/covers/${assetId(upload)}`))
      .status,
  ).toBe(401);
  const refreshed = create(StateMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    mangaKey: key,
    expectedRevision: 2,
    operation: {
      case: 'updateMetadata',
      value: { ...metadata, manga: { ...metadata.manga, title: 'Updated' } },
    },
  });
  expect((await owner.mutate(refreshed)).body.manga?.customCover).toEqual(
    saved.body.manga?.customCover,
  );
  favorite.expectedRevision = 3;
  favorite.mutationId = crypto.randomUUID();
  if (favorite.operation.case === 'setFavorite')
    favorite.operation.value.favorite = false;
  expect((await owner.mutate(favorite)).body.manga?.customCover).toEqual(
    saved.body.manga?.customCover,
  );
  expect((await owner.mutate(clear(key, 4))).status).toBe(200);
  expect((await second.state(key)).manga?.customCover).toBeUndefined();
  expect((await second.request(`/api/covers/${assetId(upload)}`)).status).toBe(
    404,
  );
  const row = await env.DB.prepare(
    'SELECT state_json FROM manga_state WHERE subject = ? AND manga_key = ?',
  )
    .bind(owner.subject, key)
    .first<{ state_json: string }>();
  expect(JSON.parse(row!.state_json).customCover).toBeUndefined();
});

test('cover CAS has one winner and durable set/clear retries never upload or resurrect obsolete references', async () => {
  const owner = await client();
  const second = await client(owner.subject);
  const key = 'b'.repeat(64);
  const first = command(key);
  const competing = command(key);
  const outcomes = await Promise.all([
    owner.upload(first),
    second.upload(competing),
  ]);
  expect(outcomes.map((item) => item.status).sort()).toEqual([200, 409]);
  const winner = outcomes[0]?.status === 200 ? first : competing;
  const ack = outcomes.find((item) => item.status === 200)?.body;
  const beforeRetry = await objectKeys(owner.subject);
  expect((await second.upload(winner)).body).toEqual(ack);
  expect(await objectKeys(owner.subject)).toEqual(beforeRetry);
  const replacement = command(key, 1);
  expect((await owner.upload(replacement)).status).toBe(200);
  expect((await owner.upload(winner)).body).toEqual(ack);
  expect((await second.state(key)).manga?.customCover?.assetId).toBe(
    assetId(replacement),
  );
  expect((await second.request(`/api/covers/${assetId(winner)}`)).status).toBe(
    404,
  );
  const remove = clear(key, 2);
  const removed = await owner.mutate(remove);
  expect(removed.status).toBe(200);
  const final = command(key, 3);
  expect((await owner.upload(final)).status).toBe(200);
  expect((await second.mutate(remove)).body).toEqual(removed.body);
  expect((await second.state(key)).manga?.customCover?.assetId).toBe(
    assetId(final),
  );
  const changed = create(StateMutationSchema, {
    ...winner,
    expectedRevision: 4,
  });
  expect((await owner.upload(changed)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  const reused = command('c'.repeat(64));
  if (
    reused.operation.case === 'setCustomCover' &&
    final.operation.case === 'setCustomCover'
  )
    reused.operation.value.cover = final.operation.value.cover;
  expect((await owner.upload(reused)).status).toBe(400);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM cover_assets WHERE subject = ?',
    )
      .bind(owner.subject)
      .first('count'),
  ).toBe(1);
});

test('failed D1 cover transactions retain retryable candidates and maintenance deletes only old unreferenced objects', async () => {
  const owner = await client();
  const key = 'd'.repeat(64);
  const mutation = command(key);
  await env.DB.exec(
    `CREATE TRIGGER fail_cover BEFORE INSERT ON cover_assets WHEN NEW.subject = '${owner.subject}' BEGIN SELECT RAISE(ABORT, 'controlled cover failure'); END`,
  );
  try {
    expect((await owner.upload(mutation)).status).toBe(503);
    expect((await owner.state(key)).accountRevision).toBe(0);
    expect((await owner.state(key)).manga?.customCover).toBeUndefined();
    expect(
      await env.DB.prepare(
        'SELECT count(*) count FROM state_mutations WHERE subject = ?',
      )
        .bind(owner.subject)
        .first('count'),
    ).toBe(0);
  } finally {
    await env.DB.exec('DROP TRIGGER fail_cover');
  }
  const orphan = (await objectKeys(owner.subject))[0]!;
  expect(orphan).toBeDefined();
  expect((await owner.upload(mutation)).status).toBe(200);
  const current = await env.DB.prepare(
    'SELECT object_key FROM cover_assets WHERE subject = ?',
  )
    .bind(owner.subject)
    .first<string>('object_key');
  expect(current).not.toBe(orphan);
  await expect(
    cleanupCoverOrphans(env.DB, env.COVERS, {
      graceMs: COVER_ORPHAN_GRACE_MS - 1,
    }),
  ).rejects.toThrow('at least one hour');
  await cleanupCoverOrphans(env.DB, env.COVERS);
  expect(await env.COVERS.head(orphan)).not.toBeNull();
  await cleanupCoverOrphans(env.DB, env.COVERS, {
    now: new Date(Date.now() + 2 * COVER_ORPHAN_GRACE_MS),
  });
  expect(await env.COVERS.head(orphan)).toBeNull();
  expect(await env.COVERS.head(current!)).not.toBeNull();
  expect((await owner.request(`/api/covers/${assetId(mutation)}`)).status).toBe(
    200,
  );
  await env.COVERS.delete(current!);
  expect((await owner.request(`/api/covers/${assetId(mutation)}`)).status).toBe(
    503,
  );
});

test('invalid binary uploads and the JSON shortcut cannot mutate D1 or write R2', async () => {
  const owner = await client();
  const key = 'e'.repeat(64);
  const valid = command(key);
  expect((await owner.mutate(valid)).status).toBe(400);
  const badHash = command(key);
  if (
    badHash.operation.case === 'setCustomCover' &&
    badHash.operation.value.cover
  )
    badHash.operation.value.cover.sha256 = '0'.repeat(64);
  expect((await owner.upload(badHash)).status).toBe(400);
  expect((await owner.upload(valid, png, 'image/jpeg')).status).toBe(400);
  const unknown = new Uint8Array([1, 2, 3]);
  expect((await owner.upload(command(key, 0, unknown), unknown)).status).toBe(
    400,
  );
  const hugeDimensions = png.slice();
  hugeDimensions.set([0, 0, 16, 1], 16);
  expect(
    (await owner.upload(command(key, 0, hugeDimensions), hugeDimensions))
      .status,
  ).toBe(400);
  expect(
    (await owner.upload(valid, new Uint8Array(COVER_BYTE_LIMIT + 1))).status,
  ).toBe(413);
  expect(
    (await owner.upload(valid, new Uint8Array(COVER_BYTE_LIMIT + 200000)))
      .status,
  ).toBe(413);
  const form = new FormData();
  form.set('mutation', JSON.stringify(toJson(StateMutationSchema, valid)));
  form.set('image', new File([png], 'cover.png', { type: 'image/png' }));
  form.append('image', new File([png], 'duplicate.png'));
  expect(
    (
      await owner.request(`/api/covers/${key}`, {
        method: 'POST',
        headers: { Origin: origin, 'X-App-Request': '1' },
        body: form,
      })
    ).status,
  ).toBe(400);
  const forged = new FormData();
  forged.set('mutation', JSON.stringify(toJson(StateMutationSchema, valid)));
  forged.set('image', new File([png], 'cover.png', { type: 'image/png' }));
  expect(
    (
      await owner.request(`/api/covers/${'f'.repeat(64)}`, {
        method: 'POST',
        headers: { Origin: origin, 'X-App-Request': '1' },
        body: forged,
      })
    ).status,
  ).toBe(400);
  expect((await owner.state(key)).accountRevision).toBe(0);
  expect(await objectKeys(owner.subject)).toEqual([]);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM cover_assets WHERE subject = ?',
    )
      .bind(owner.subject)
      .first('count'),
  ).toBe(0);
});
