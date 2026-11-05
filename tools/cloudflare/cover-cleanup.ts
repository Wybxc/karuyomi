import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { getPlatformProxy, unstable_readConfig } from 'wrangler';
import { z } from 'zod';
import {
  cleanupCoverOrphans,
  COVER_ORPHAN_GRACE_MS,
  type CoverCleanupBindings,
} from './cover-orphans.ts';

const { values } = parseArgs({
  options: {
    remote: { type: 'boolean', default: false },
    cursor: { type: 'string' },
    'grace-hours': { type: 'string', default: '1' },
  },
});
const graceMs = Number(values['grace-hours']) * COVER_ORPHAN_GRACE_MS;
if (!Number.isFinite(graceMs) || graceMs < COVER_ORPHAN_GRACE_MS)
  throw new Error('--grace-hours must be at least 1');
const apiDirectory = fileURLToPath(new URL('../../apps/api/', import.meta.url));
const config = z
  .object({
    name: z.string(),
    compatibility_date: z.string(),
    account_id: z.string().optional(),
    d1_databases: z.array(
      z.object({
        binding: z.string(),
        database_name: z.string(),
        database_id: z.string(),
      }),
    ),
    r2_buckets: z.array(
      z.object({ binding: z.string(), bucket_name: z.string() }),
    ),
  })
  .parse(
    unstable_readConfig(
      { config: resolve(apiDirectory, 'wrangler.jsonc') },
      { hideWarnings: true },
    ),
  );
const db = config.d1_databases.find((binding) => binding.binding === 'DB');
const covers = config.r2_buckets.find(
  (binding) => binding.binding === 'COVERS',
);
if (!db || !covers) throw new Error('DB and COVERS bindings are required');
const directory = await mkdtemp(join(tmpdir(), 'karuyomi-cover-cleanup-'));
try {
  const configPath = join(directory, 'wrangler.json');
  await writeFile(
    configPath,
    JSON.stringify({
      name: `${config.name}-cover-cleanup`,
      compatibility_date: config.compatibility_date,
      ...(config.account_id ? { account_id: config.account_id } : {}),
      d1_databases: [{ ...db, remote: values.remote }],
      r2_buckets: [{ ...covers, remote: values.remote }],
    }),
  );
  const proxy = await getPlatformProxy<CoverCleanupBindings>({
    configPath,
    remoteBindings: values.remote,
    persist: { path: resolve(apiDirectory, '.wrangler/state/v3') },
    envFiles: [],
  });
  try {
    const result = await cleanupCoverOrphans(proxy.env.DB, proxy.env.COVERS, {
      graceMs,
      ...(values.cursor ? { cursor: values.cursor } : {}),
    });
    process.stdout.write(
      `${JSON.stringify({ mode: values.remote ? 'remote' : 'local', ...result })}\n`,
    );
  } finally {
    await proxy.dispose();
  }
} finally {
  await rm(directory, { recursive: true, force: true });
}
