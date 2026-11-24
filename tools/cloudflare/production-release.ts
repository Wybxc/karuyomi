import assert from 'node:assert/strict';
import { readdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { execa } from 'execa';
import { unstable_readConfig } from 'wrangler';
import { z } from 'zod';

const ledger = z.tuple([
  z.object({
    success: z.literal(true),
    results: z.array(z.object({ name: z.string() })),
  }),
]);
const databaseBindings = z.array(
  z.object({
    binding: z.string(),
    migrations_dir: z.string().optional(),
    migrations_pattern: z.string().optional(),
    migrations_table: z.string().optional(),
  }),
);

export function assertAppliedMigrations(
  expected: readonly string[],
  response: unknown,
): void {
  assert(expected.length > 0, 'The release has no migration files');
  const [{ results }] = ledger.parse(response);
  const applied = results.map(({ name }) => name);
  assert(
    applied.length <= expected.length &&
      applied.every((name, index) => name === expected[index]),
    'The production D1 migration ledger is not a prefix of this release',
  );
  const pending = expected.slice(applied.length);
  assert(
    pending.length === 0,
    `Production D1 is missing ${pending.join(', ')}. Use the maintenance procedure in docs/PRODUCTION.md.`,
  );
}

export async function checkProductionSchema(configPath: string): Promise<void> {
  const config = unstable_readConfig({ config: configPath });
  const database = databaseBindings
    .parse(config.d1_databases)
    .find(({ binding }) => binding === 'DB');
  assert(database, 'The release configuration must bind D1 as DB');
  assert(
    database.migrations_pattern === undefined,
    'The production migration check expects the default top-level SQL layout',
  );
  const migrationTable = database.migrations_table ?? 'd1_migrations';
  assert(
    /^[A-Za-z0-9_]+$/.test(migrationTable),
    'Invalid migration table name',
  );
  const directory = resolve(
    dirname(configPath),
    database.migrations_dir ?? 'migrations',
  );
  const names = (await readdir(directory, { withFileTypes: true }))
    .filter(
      (entry) =>
        entry.isFile() &&
        !entry.name.startsWith('.') &&
        entry.name.endsWith('.sql'),
    )
    .map((entry) => entry.name)
    .sort();
  assert(
    names.every((name) => /^\d{4}_.+\.sql$/.test(name)),
    'Production migration files must use Drizzle sequential names',
  );
  const { stdout } = await execa(
    'pnpm',
    [
      'exec',
      'wrangler',
      'd1',
      'execute',
      'DB',
      '--remote',
      '--json',
      '--config',
      configPath,
      '--command',
      `SELECT name FROM "${migrationTable}" ORDER BY id`,
    ],
    { timeout: 30_000 },
  );
  assertAppliedMigrations(names, JSON.parse(stdout));
  console.log(`Production D1 matches all ${names.length} release migrations.`);
}

export async function stageMaintenanceConfig(
  configPath: string,
  entrypoint: string,
  directory: string,
): Promise<string> {
  const config = unstable_readConfig({ config: configPath });
  assert(config.name && config.compatibility_date, 'Missing Worker identity');
  const destination = join(directory, 'wrangler.maintenance.json');
  await writeFile(
    destination,
    JSON.stringify(
      {
        name: config.name,
        account_id: config.account_id,
        main: entrypoint,
        compatibility_date: config.compatibility_date,
        compatibility_flags: config.compatibility_flags,
        workers_dev: false,
        preview_urls: false,
        durable_objects: config.durable_objects,
        migrations: config.migrations,
      },
      null,
      2,
    ),
    { flag: 'wx' },
  );
  return destination;
}

export async function assertMaintenanceActive(origin: string): Promise<void> {
  for (const pathname of ['/', '/extensions/index.json']) {
    const response = await fetch(new URL(pathname, origin), {
      cache: 'no-store',
      redirect: 'manual',
      signal: AbortSignal.timeout(10_000),
    });
    const active =
      response.status === 503 &&
      response.headers.get('x-karuyomi-maintenance') === '1';
    await response.body?.cancel();
    assert(active, `Production maintenance is not active at ${pathname}`);
  }
  console.log('Production maintenance is active.');
}
