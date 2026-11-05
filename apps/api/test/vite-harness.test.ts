import { categoryCatalogResponseSchema } from '@karuyomi/contracts';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import {
  mkdir,
  mkdtemp,
  readFile,
  realpath,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import { expect, test } from 'vitest';
import { createTestHarness, type TestHarness } from 'wrangler';
import { z } from 'zod';
import type { Bindings } from '../src/env.js';
import { buildProbeApi } from './probe-build.ts';

const origin = 'https://read.example.com';
const deploymentRedirect = fileURLToPath(
  new URL('../.wrangler/deploy/config.json', import.meta.url),
);
const outputConfigSchema = z.object({
  main: z.string(),
  no_bundle: z.literal(true),
  assets: z.object({
    directory: z.string(),
    binding: z.literal('ASSETS'),
    run_worker_first: z.array(z.string()),
    not_found_handling: z.literal('none'),
  }),
  d1_databases: z.array(
    z.object({ binding: z.string(), migrations_dir: z.string() }),
  ),
});

async function readDeploymentRedirect(): Promise<Buffer | null> {
  try {
    return await readFile(deploymentRedirect);
  } catch (error) {
    if (
      !(error instanceof Error) ||
      !('code' in error) ||
      error.code !== 'ENOENT'
    )
      throw error;
    return null;
  }
}

test('Cloudflare Vite output serves static assets and verified D1 routes without changing the product deployment', async () => {
  const originalRedirect = await readDeploymentRedirect();
  const directory = await realpath(
    await mkdtemp(path.join(tmpdir(), 'karuyomi-vite-harness-')),
  );
  let server: TestHarness | undefined;
  try {
    const publicDirectory = path.join(directory, 'public');
    await mkdir(path.join(publicDirectory, 'runtime'), { recursive: true });
    await writeFile(
      path.join(publicDirectory, 'index.html'),
      '<!doctype html><title>Vite fixture shell</title>',
    );
    await writeFile(
      path.join(publicDirectory, 'hello.txt'),
      'Vite static bytes\n',
    );
    await writeFile(
      path.join(publicDirectory, 'runtime/host.html'),
      '<!doctype html><title>Vite runtime fixture</title>',
    );
    await writeFile(
      path.join(publicDirectory, '_headers'),
      '/hello.txt\n  X-Vite-Asset: copied\n',
    );

    const { configPath } = await buildProbeApi(directory, publicDirectory);
    const generated = outputConfigSchema.parse(
      JSON.parse(await readFile(configPath, 'utf8')),
    );
    const outputDirectory = path.dirname(configPath);
    const assetsDirectory = path.resolve(
      outputDirectory,
      generated.assets.directory,
    );
    expect(
      (await stat(path.resolve(outputDirectory, generated.main))).isFile(),
    ).toBe(true);
    expect(assetsDirectory).not.toBe(publicDirectory);
    expect(
      await readFile(path.join(assetsDirectory, 'hello.txt'), 'utf8'),
    ).toBe('Vite static bytes\n');
    expect(
      await readFile(path.join(assetsDirectory, '_headers'), 'utf8'),
    ).toContain('X-Vite-Asset: copied');
    expect(generated.assets.run_worker_first).toEqual([
      '/api',
      '/api/*',
      '/runtime/host.html',
    ]);
    const database = generated.d1_databases.find(
      (value) => value.binding === 'DB',
    );
    expect(database).toBeDefined();
    if (!database)
      throw new Error('Generated API configuration has no D1 binding');
    expect(
      (
        await stat(path.resolve(outputDirectory, database.migrations_dir))
      ).isDirectory(),
    ).toBe(true);
    expect(await readDeploymentRedirect()).toEqual(originalRedirect);

    const keys = await generateKeyPair('RS256');
    const publicKey = await exportJWK(keys.publicKey);
    publicKey.kid = 'vite-harness';
    server = createTestHarness({
      root: directory,
      workers: [
        {
          configPath,
          vars: {
            PROBE_ACCESS_JWKS: JSON.stringify({ keys: [publicKey] }),
            ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
            ACCESS_AUD: 'vite-harness',
            ACCESS_SUBJECT: 'vite-owner',
            OWNER_EMAIL: 'owner@example.com',
            APP_ORIGIN: origin,
          },
        },
      ],
    });
    await server.listen();
    const worker = server.getWorker<Bindings>();
    expect((await worker.getEnv()).APP_ORIGIN).toBe(origin);
    await worker.applyD1Migrations('DB');

    const shell = await server.fetch(`${origin}/`);
    expect(shell.status).toBe(200);
    expect(await shell.text()).toContain('Vite fixture shell');
    expect(shell.headers.has('X-Karuyomi-Probe-Worker')).toBe(false);
    const asset = await server.fetch(`${origin}/hello.txt`);
    expect(asset.status).toBe(200);
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
    const anonymous = await worker.fetch(`${origin}/api/categories`);
    expect(anonymous.status, await anonymous.clone().text()).toBe(401);
    expect(await anonymous.json()).toEqual({ error: 'access_required' });

    const token = await new SignJWT({ email: 'owner@example.com' })
      .setProtectedHeader({ alg: 'RS256', kid: 'vite-harness' })
      .setSubject('vite-owner')
      .setIssuer('https://example.cloudflareaccess.com')
      .setAudience('vite-harness')
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(keys.privateKey);
    const categories = await worker.fetch(`${origin}/api/categories`, {
      headers: {
        'Cf-Access-Jwt-Assertion': token,
        'X-App-Subject': 'vite-owner',
      },
    });
    expect(categories.status).toBe(200);
    expect(categories.headers.get('X-Karuyomi-Probe-Worker')).toBe('1');
    const catalog = categoryCatalogResponseSchema.parse(
      await categories.json(),
    );
    expect(catalog.accountRevision).toBe(0);
    expect(catalog.categoryCatalog).toMatchObject({
      revision: 0,
      categories: [],
    });
    expect(catalog.error).toBeUndefined();
  } finally {
    try {
      await server?.close();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  }
  expect(await readDeploymentRedirect()).toEqual(originalRedirect);
}, 60_000);
