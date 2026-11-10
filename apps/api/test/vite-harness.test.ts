import {
  create,
  toJsonString,
  type MessageInitShape,
} from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  categoryCatalogResponseSchema,
  libraryPageResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import { StateMutationSchema } from '@karuyomi/protocol';
import { exportJWK, generateKeyPair, SignJWT, type JWK } from 'jose';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath, URL } from 'node:url';
import { afterAll, beforeAll, expect, test } from 'vitest';
import { createTestHarness, type TestHarnessOptions } from 'wrangler';
import type { Bindings } from '../src/env.js';

const origin = 'https://read.example.com';
const accessTeamDomain = 'example.cloudflareaccess.com';
const accessAudience = 'vite-harness';

async function createAccessKey(kid: string) {
  const { privateKey, publicKey } = await generateKeyPair('RS256');
  return { privateKey, jwk: { ...(await exportJWK(publicKey)), kid } };
}

async function accessHeaders(
  key: Awaited<ReturnType<typeof createAccessKey>>,
  subject: string,
) {
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: key.jwk.kid })
    .setSubject(subject)
    .setIssuer(`https://${accessTeamDomain}`)
    .setAudience(accessAudience)
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(key.privateKey);
  return {
    'Cf-Access-Jwt-Assertion': token,
    'X-App-Subject': subject,
  };
}

const harnessOptions = (jwk: JWK): TestHarnessOptions => ({
  workers: [
    {
      configPath: fileURLToPath(
        new URL('./fixture/dist/karuyomi/wrangler.json', import.meta.url),
      ),
      vars: {
        PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
        ACCESS_TEAM_DOMAIN: accessTeamDomain,
        ACCESS_AUD: accessAudience,
        APP_ORIGIN: origin,
      },
    },
  ],
});
const keys = await createAccessKey('vite-harness');
const server = createTestHarness(harnessOptions(keys.jwk));
const worker = server.getWorker<Bindings>();
beforeAll(async () => {
  await server.listen();
  await worker.applyD1Migrations('DB');
});
afterAll(() => server.close());

test('declared Vite assets bypass the Worker and retain their headers', async () => {
  const shell = await server.fetch(`${origin}/`);
  expect(shell.status).toBe(200);
  expect(await shell.text()).toContain('Karuyomi static fixture');
  expect(shell.headers.has('X-Karuyomi-Probe-Worker')).toBe(false);
  const asset = await server.fetch(`${origin}/hello.txt`);
  expect(await asset.text()).toBe('Vite static bytes\n');
  expect(asset.headers.get('X-Vite-Asset')).toBe('copied');
  expect(asset.headers.has('X-Karuyomi-Probe-Worker')).toBe(false);
  const host = await server.fetch(`${origin}/runtime/host.html`, {
    redirect: 'manual',
  });
  expect(host.status).toBe(307);
  expect(new URL(host.headers.get('location') ?? '', origin).pathname).toBe(
    '/runtime/host',
  );
  expect(host.headers.get('X-Karuyomi-Probe-Worker')).toBe('1');
});

test('the public Access callback serves only a no-store return notice', async () => {
  const callback = await server.fetch(
    `${origin}/auth/complete?attempt=${crypto.randomUUID()}`,
    { redirect: 'manual' },
  );
  expect(callback.status).toBe(200);
  expect(callback.headers.get('X-Karuyomi-Probe-Worker')).toBe('1');
  expect(callback.headers.get('Cache-Control')).toBe('no-store');
  expect(callback.headers.get('Content-Type')).toMatch(/^text\/plain\b/);
  expect(await callback.text()).toBe('请返回 Karuyomi。');
});

test('generated Worker config applies D1 migrations, binds private R2 and verifies the test JWT', async () => {
  expect((await worker.fetch(`${origin}/api/categories`)).status).toBe(401);
  const response = await worker.fetch(`${origin}/api/categories`, {
    headers: await accessHeaders(keys, 'vite-owner'),
  });
  expect(response.status).toBe(200);
  const catalog = categoryCatalogResponseSchema.parse(await response.json());
  expect(catalog.categoryCatalog).toMatchObject({
    revision: 0,
    categories: [],
  });
  expect(catalog.error).toBeUndefined();
  const bindings = await worker.getEnv();
  expect(
    await bindings.DB.prepare('SELECT count(*) count FROM cover_assets').first(
      'count',
    ),
  ).toBe(0);
  await bindings.COVERS.put('harness-private-cover', 'private R2 binding');
  expect(
    await (await bindings.COVERS.get('harness-private-cover'))?.text(),
  ).toBe('private R2 binding');
  await bindings.COVERS.delete('harness-private-cover');
});

test('Worker reload preserves D1 state and an exact retry cannot overwrite later progress', async () => {
  const recoveryServer = createTestHarness(harnessOptions(keys.jwk));
  const subject = 'vite-recovery-owner';
  const before = await accessHeaders(keys, subject);
  const nextKey = await createAccessKey('vite-reloaded');
  const after = await accessHeaders(nextKey, subject);
  const recoveryWorker = recoveryServer.getWorker<Bindings>();
  const metadata = {
    packageName: 'test.recovery.source',
    sourceId: '123',
    sourceName: 'Test source',
    sourceLang: 'en',
    manga: { url: '/recovery', title: 'Recovery fixture' },
  };
  const mangaKey = createHash('sha256')
    .update(
      JSON.stringify([
        metadata.packageName,
        metadata.sourceId,
        metadata.manga.url,
      ]),
    )
    .digest('hex');
  const chapterKey = 'recovery-chapter';
  const manifestVersion = 'recovery-pages';
  const pageKeys = ['first', 'middle', 'last'];
  const mangaUrl = `${origin}/api/state/manga/${mangaKey}?chapterKey=${chapterKey}`;
  const mutationBody = (value: MessageInitShape<typeof StateMutationSchema>) =>
    toJsonString(StateMutationSchema, create(StateMutationSchema, value));
  const progressBody = (revision: number, index: number, pageKey: string) => {
    const anchor = {
      chapterKey,
      manifestVersion,
      pageKey,
      pageIndexHint: index,
    };
    return mutationBody({
      schemaVersion: businessSchemaVersion,
      mutationId: randomUUID(),
      mangaKey,
      expectedRevision: revision,
      operation: {
        case: 'saveProgress',
        value: {
          snapshot: { chapterKey, manifestVersion, pageKeys },
          progress: { chapterKey, current: anchor, furthest: anchor },
        },
      },
    });
  };
  const mutate = async (
    headers: Awaited<ReturnType<typeof accessHeaders>>,
    body: string,
  ) => {
    const response = await recoveryWorker.fetch(
      `${origin}/api/state/mutations`,
      {
        method: 'POST',
        headers: {
          ...headers,
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
        },
        body,
      },
    );
    expect(response.status).toBe(200);
    return stateMutationResponseSchema.parse(await response.json());
  };
  const state = async (headers: Awaited<ReturnType<typeof accessHeaders>>) => {
    const response = await recoveryWorker.fetch(mangaUrl, { headers });
    expect(response.status).toBe(200);
    return mangaStateResponseSchema.parse(await response.json());
  };

  try {
    const initialListener = await recoveryServer.listen();
    await recoveryWorker.applyD1Migrations('DB');
    const favorite = await mutate(
      before,
      mutationBody({
        schemaVersion: businessSchemaVersion,
        mutationId: randomUUID(),
        mangaKey,
        expectedRevision: 0,
        operation: { case: 'setFavorite', value: { metadata, favorite: true } },
      }),
    );
    expect(favorite.manga?.revision).toBe(1);
    const savedBody = progressBody(1, 1, 'middle');
    const saved = await mutate(before, savedBody);
    expect(saved).toMatchObject({
      accountRevision: 2,
      manga: { revision: 2 },
      progress: { current: { pageKey: 'middle' } },
    });
    const original = await state(before);

    await recoveryServer.update(harnessOptions(nextKey.jwk));
    expect((await recoveryServer.listen()).url.href).toBe(
      initialListener.url.href,
    );
    expect(
      (await recoveryWorker.fetch(mangaUrl, { headers: before })).status,
    ).toBe(401);
    expect(await state(after)).toEqual(original);
    const library = await recoveryWorker.fetch(`${origin}/api/library`, {
      headers: after,
    });
    expect(library.status).toBe(200);
    expect(libraryPageResponseSchema.parse(await library.json())).toMatchObject(
      {
        accountRevision: 2,
        entries: [{ mangaKey, revision: 2, metadata, resume: { chapterKey } }],
      },
    );

    const newer = {
      accountRevision: 3,
      manga: { revision: 3 },
      progress: {
        current: { pageKey: 'last' },
        furthest: { pageKey: 'last' },
      },
    };
    expect(await mutate(after, progressBody(2, 2, 'last'))).toMatchObject(
      newer,
    );
    // A client that lost the earlier ACK must receive that original result,
    // even though the authoritative position has advanced since then.
    expect(await mutate(after, savedBody)).toEqual(saved);
    expect(await state(after)).toMatchObject(newer);
    const { DB } = await recoveryWorker.getEnv();
    expect(
      await DB.prepare(
        'SELECT count(*) count FROM state_mutations WHERE subject = ?',
      )
        .bind(subject)
        .first('count'),
    ).toBe(3);
  } finally {
    await recoveryServer.close();
  }
}, 30_000);
