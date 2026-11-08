import { create, toJson } from '@bufbuild/protobuf';
import {
  sourcePreferencesMutationResponseSchema,
  sourcePreferencesResponseSchema,
  SOURCE_PREFERENCES_PACKAGE_LIMIT,
} from '@karuyomi/contracts';
import * as pb from '@karuyomi/protocol';
import { env, exports } from 'cloudflare:workers';
import { applyD1Migrations } from 'cloudflare:test';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { beforeAll, expect, test } from 'vitest';

const origin = 'https://read.example.com';
const komiic = 'eu.kanade.tachiyomi.extension.zh.komiic';
const fire = 'eu.kanade.tachiyomi.extension.all.mangafire';
const katana = 'eu.kanade.tachiyomi.extension.en.mangakatana';
const sourceId = '792932060924485302';
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'preferences-fixture';
  env.PROBE_ACCESS_JWKS = JSON.stringify({ keys: [jwk] });
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}, 30_000);
const text = (key: string, value: string) =>
  create(pb.PreferenceEntrySchema, {
    key,
    value: { value: { case: 'text', value } },
  });
const boolean = (key: string, value: boolean) =>
  create(pb.PreferenceEntrySchema, {
    key,
    value: { value: { case: 'boolean', value } },
  });
const strings = (values: string[]) =>
  create(pb.PreferenceEntrySchema, {
    key: 'pref_content_rating',
    value: { value: { case: 'strings', value: { values } } },
  });
function command(
  entries: pb.PreferenceEntry[],
  expectedRevision = 0,
  packageName = komiic,
  id = sourceId,
) {
  return create(pb.SourcePreferencesMutationSchema, {
    schemaVersion: 1,
    catalog: {
      catalogUrl: origin + '/extensions/index.json',
      repoId: 'keiyoushi',
    },
    mutationId: crypto.randomUUID(),
    packageName,
    sourceId: id,
    expectedRevision,
    entries,
  });
}
async function client(subject = crypto.randomUUID()) {
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'preferences-fixture' })
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
      return exports.default.fetch(origin + path, {
        ...options,
        headers: [...headers.entries()],
      });
    },
    async read(
      packageName = komiic,
      catalog = {
        catalogUrl: origin + '/extensions/index.json',
        repoId: 'keiyoushi',
      },
    ) {
      const response = await this.request(
        '/api/source-preferences/packages/' +
          packageName +
          '?catalogUrl=' +
          encodeURIComponent(catalog.catalogUrl) +
          '&repoId=' +
          encodeURIComponent(catalog.repoId),
      );
      expect(response.status).toBe(200);
      return sourcePreferencesResponseSchema.parse(await response.json());
    },
    async mutate(mutation: pb.SourcePreferencesMutation) {
      const response = await this.raw(
        toJson(pb.SourcePreferencesMutationSchema, mutation),
      );
      return {
        status: response.status,
        body: sourcePreferencesMutationResponseSchema.parse(
          await response.json(),
        ),
      };
    },
    async raw(value: unknown, headers: Record<string, string> = {}) {
      return this.request('/api/source-preferences/mutations', {
        method: 'POST',
        headers: {
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: JSON.stringify(value),
      });
    },
  };
}

test('package reads are pure and identity-scoped; full replacement preserves actual alias, false and empty values', async () => {
  const first = await client(),
    second = await client(first.subject),
    outsider = await client();
  expect((await first.read()).sources).toEqual([]);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM account_state WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(0);
  const original = command([
    text('preferred_mirror', '1'),
    text('CHAPTER_FILTER', 'book'),
  ]);
  const saved = await first.mutate(original);
  expect(saved.status).toBe(200);
  expect(saved.body.preferences).toMatchObject({ revision: 1, sourceId });
  expect((await second.read()).sources).toEqual([saved.body.preferences]);
  expect((await outsider.read()).sources).toEqual([]);
  expect((await first.read(fire)).sources).toEqual([]);
  const alias = await first.mutate(
    command(
      [text('server_preference', ''), text('SERVER_PREFERENCE', 'mk')],
      0,
      katana,
    ),
  );
  expect(alias.status).toBe(200);
  expect((await second.read(katana)).sources[0]?.entries).toEqual(
    alias.body.preferences?.entries,
  );
  const emptied = await first.mutate(
    command([boolean('merge_chapters', false), strings([])], 0, fire),
  );
  expect(emptied.body.preferences?.entries).toEqual([
    boolean('merge_chapters', false),
    strings([]),
  ]);
  const cleared = await second.mutate(command([], 1));
  expect(cleared.body.preferences).toMatchObject({ revision: 2, entries: [] });
  expect((await first.read()).sources).toEqual([cleared.body.preferences]);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM reader_settings WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(0);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM manga_state WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(0);
});

test('lost ACK replays its exact committed snapshot without applying twice or rolling back newer preferences; source CAS stays independent', async () => {
  const first = await client(),
    second = await client(first.subject);
  const original = command([text('preferred_mirror', '1')]);
  const ack = await first.mutate(original);
  const later = await second.mutate(
    command([text('preferred_mirror', '0')], 1),
  );
  expect(later.body.accountRevision).toBe(2);
  expect((await first.mutate(original)).body).toEqual(ack.body);
  expect((await first.read()).sources[0]).toEqual(later.body.preferences);
  expect(
    (
      await first.mutate({
        ...original,
        entries: [text('preferred_mirror', '0')],
      })
    ).body.error?.code,
  ).toBe(pb.BusinessStateErrorCode.IDEMPOTENCY_CONFLICT);
  expect(
    (await first.mutate({ ...original, packageName: katana, entries: [] })).body
      .error?.code,
  ).toBe(pb.BusinessStateErrorCode.IDEMPOTENCY_CONFLICT);
  const conflict = await first.mutate(command([], 1));
  expect(conflict.status).toBe(409);
  expect(conflict.body.preferences).toEqual(later.body.preferences);
  const [left, right] = await Promise.all([
    first.mutate(command([boolean('merge_chapters', true)], 0, fire, '1')),
    second.mutate(command([boolean('merge_chapters', false)], 0, fire, '1')),
  ]);
  expect([left.status, right.status].sort()).toEqual([200, 409]);
  expect((await first.mutate(command([], 0, fire, '2'))).status).toBe(200);
  expect((await first.read(fire)).accountRevision).toBe(4);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM state_mutations WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(4);
});

test('ordinary API rejects sensitive, unknown, malformed and oversized values before writes and enforces session identity', async () => {
  const reader = await client();
  const base = toJson(pb.SourcePreferencesMutationSchema, command([]));
  for (const entries of [
    [{ key: 'token', value: { text: 'secret' } }],
    [{ key: 'CHAPTER_FILTER', value: { boolean: true } }],
    [{ key: 'CHAPTER_FILTER', value: { text: 'a'.repeat(4097) } }],
    [
      { key: 'CHAPTER_FILTER', value: { text: 'book' } },
      { key: 'CHAPTER_FILTER', value: { text: 'all' } },
    ],
    [{ key: 'CHAPTER_FILTER', value: { text: 'book' }, syncScope: 'ACCOUNT' }],
  ])
    expect((await reader.raw({ ...base, entries })).status).toBe(400);
  expect(
    (
      await reader.raw({
        ...base,
        entries: [{ key: 'x', value: { text: 'x'.repeat(128 * 1024) } }],
      })
    ).status,
  ).toBe(413);
  for (const packageName of ['', 'a'.repeat(201)])
    expect((await reader.raw({ ...base, packageName })).status).toBe(400);
  expect(
    (
      await reader.request(
        '/api/source-preferences/packages/' + 'a'.repeat(201),
      )
    ).status,
  ).toBe(400);
  expect(
    (await reader.raw(base, { 'X-App-Subject': 'old-subject' })).status,
  ).toBe(403);
  expect(
    (await reader.raw(base, { Origin: 'https://wrong.example.com' })).status,
  ).toBe(403);
  expect(
    (
      await reader.request('/api/source-preferences/packages/' + komiic, {
        headers: { 'X-App-Subject': 'old-subject' },
      })
    ).status,
  ).toBe(403);
  expect((await reader.read()).accountRevision).toBe(0);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM source_preferences WHERE subject = ?',
    )
      .bind(reader.subject)
      .first('count'),
  ).toBe(0);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM state_mutations WHERE subject = ?',
    )
      .bind(reader.subject)
      .first('count'),
  ).toBe(0);
});

test('a valid community package can read preferences without gaining sync rules', async () => {
  const reader = await client();
  const packageName = 'org.example.extension';
  const catalog = {
    catalogUrl: 'https://community.example/extensions/index.json',
    repoId: 'community',
  };
  const initial = await reader.read(packageName, catalog);
  expect(initial).toMatchObject({
    packageName,
    accountRevision: 0,
    syncRules: [],
    sources: [],
  });
  const write = await reader.mutate({
    ...command([text('preferred_mirror', '1')], 0, packageName),
    catalog: create(pb.CatalogReferenceSchema, catalog),
  });
  expect(write.status).toBe(400);
  expect((await reader.read(packageName, catalog)).accountRevision).toBe(0);
});

test('package scope count is bounded transactionally, including simultaneous last-slot writes, and clearing retains CAS', async () => {
  const reader = await client();
  for (let index = 1; index < SOURCE_PREFERENCES_PACKAGE_LIMIT; index++)
    expect(
      (await reader.mutate(command([], 0, fire, String(index)))).status,
    ).toBe(200);
  const [first, second] = await Promise.all([
    reader.mutate(command([], 0, fire, '64')),
    reader.mutate(command([], 0, fire, '65')),
  ]);
  expect([first.status, second.status].sort()).toEqual([200, 413]);
  const canonical = await reader.read(fire);
  expect(canonical.sources).toHaveLength(64);
  expect(canonical.accountRevision).toBe(64);
  expect(
    (await reader.mutate(command([], 1, fire, '1'))).body.preferences?.revision,
  ).toBe(2);
  expect(
    (await reader.mutate(command([], 0, fire, '66'))).body.error?.code,
  ).toBe(pb.BusinessStateErrorCode.LIMIT_EXCEEDED);
  expect((await reader.read(fire)).accountRevision).toBe(65);
});

test('UTF-8 package entries budget is enforced across concurrent source writes while replacement frees capacity', async () => {
  const reader = await client();
  const large = [
    strings(
      Array.from(
        { length: 7 },
        (_, index) => String(index) + '字'.repeat(1199),
      ),
    ),
  ];
  const results = await Promise.all(
    ['1', '2', '3'].map((id) => reader.mutate(command(large, 0, fire, id))),
  );
  expect(results.map((result) => result.status).sort()).toEqual([
    200, 200, 413,
  ]);
  const before = await reader.read(fire);
  expect(before.sources).toHaveLength(2);
  expect(before.accountRevision).toBe(2);
  const clearedId = before.sources[0]!.sourceId;
  expect((await reader.mutate(command([], 1, fire, clearedId))).status).toBe(
    200,
  );
  const missing = ['1', '2', '3'].find(
    (id) => !before.sources.some((source) => source.sourceId === id),
  )!;
  expect((await reader.mutate(command(large, 0, fire, missing))).status).toBe(
    200,
  );
  expect((await reader.read(fire)).accountRevision).toBe(4);
});

test('catalog namespace isolates the same package and an external keiyoushi name cannot inherit account sync permission', async () => {
  const reader = await client();
  const main = {
    catalogUrl: origin + '/extensions/index.json',
    repoId: 'keiyoushi',
  };
  const external = {
    catalogUrl: 'https://other.example.org/extensions/index.json',
    repoId: 'keiyoushi',
  };
  const saved = await reader.mutate(command([text('preferred_mirror', '1')]));
  expect(saved.status).toBe(200);
  expect(saved.body.catalog).toMatchObject(main);
  expect(saved.body.syncRules.length).toBeGreaterThan(0);
  const externalRead = await reader.read(komiic, external);
  expect(externalRead.catalog).toMatchObject(external);
  expect(externalRead.sources).toEqual([]);
  expect(externalRead.syncRules).toEqual([]);
  const rejected = await reader.mutate({
    ...command([text('preferred_mirror', '0')]),
    catalog: create(pb.CatalogReferenceSchema, external),
  });
  expect(rejected.status).toBe(400);
  expect(rejected.body.catalog).toMatchObject(external);
  expect(rejected.body.syncRules).toEqual([]);
  const empty = {
    ...command([]),
    catalog: create(pb.CatalogReferenceSchema, external),
  };
  const externalSaved = await reader.mutate(empty);
  expect(externalSaved.status).toBe(200);
  expect(externalSaved.body.preferences?.revision).toBe(1);
  expect((await reader.read()).sources[0]?.entries).toEqual(
    saved.body.preferences?.entries,
  );
  expect((await reader.read(komiic, external)).sources[0]?.entries).toEqual([]);
  expect((await reader.mutate(empty)).body).toEqual(externalSaved.body);
  const changedScope = await reader.mutate({
    ...empty,
    catalog: create(pb.CatalogReferenceSchema, main),
  });
  expect(changedScope.body.error?.code).toBe(
    pb.BusinessStateErrorCode.IDEMPOTENCY_CONFLICT,
  );
  expect(changedScope.body.catalog).toMatchObject(main);
});
