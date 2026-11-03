#!/usr/bin/env node
// Manual, trusted Actions permission check; never imported by product code.
// API contracts: https://developers.cloudflare.com/api/resources/d1/subresources/database/
// https://developers.cloudflare.com/api/resources/workers/subresources/routes/
// Static upload is delegated to the repository's checksum-locked Wrangler.
import {
  deployPermissionProbe,
  PermissionDeploymentFailure,
} from '../tools/cloudflare/deploy-permission-probe.ts';
import { randomUUID } from 'node:crypto';
import {
  appendFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import isRecord from 'is-plain-obj';

type Check = { status: 'passed' | 'failed'; detail: string };
class CheckFailure extends Error {}
const safeError = (error: unknown) =>
  error instanceof CheckFailure || error instanceof PermissionDeploymentFailure
    ? error.message
    : 'Request interrupted or unexpected failure; raw error output withheld';
const identifier = (
  value: unknown,
  pattern = /^[a-f0-9]{32}$/,
): value is string => typeof value === 'string' && pattern.test(value);

async function main() {
  const token = process.env.CLOUDFLARE_API_TOKEN;
  const account = process.env.CLOUDFLARE_ACCOUNT_ID;
  if (!token || !identifier(account))
    throw new CheckFailure(
      'CLOUDFLARE_API_TOKEN and a valid CLOUDFLARE_ACCOUNT_ID are required',
    );
  const deploymentToken = token;
  const redact = (value: string) => value.replaceAll(token, '[redacted]');
  const abort = new AbortController();
  const stop = () => abort.abort();
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  const temporary = await mkdtemp(
    path.join(tmpdir(), 'karuyomi-cloudflare-check-'),
  );
  const name = `karuyomi-check-${randomUUID().replaceAll('-', '').slice(0, 16)}`;
  const workerName = 'karuyomi-ci-permission-check';
  const routePattern = `${name}.wybxc.cc/*`;
  const accountPath = `/accounts/${account}`;
  const workerPath = `${accountPath}/workers/scripts/${workerName}`;
  const checks: Record<string, Check> = {};
  const cleanup: Record<string, Check> = {};
  let workerAttempted = false;
  let workerUploaded = false;
  let databaseAttempted = false;
  let databaseId: string | undefined;
  let zoneId: string | undefined;
  let routeAttempted = false;
  let routeId: string | undefined;

  async function api(
    endpoint: string,
    method = 'GET',
    body?: unknown,
    cleaning = false,
    missingOkay = false,
  ): Promise<unknown> {
    const response = await fetch(
      `https://api.cloudflare.com/client/v4${endpoint}`,
      {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: cleaning
          ? AbortSignal.timeout(30_000)
          : AbortSignal.any([abort.signal, AbortSignal.timeout(45_000)]),
        redirect: 'error',
      },
    );
    if ((missingOkay && response.status === 404) || response.status === 204)
      return null;
    let value: unknown;
    try {
      value = await response.json();
    } catch {
      throw new CheckFailure(
        `Cloudflare returned HTTP ${response.status} without valid API JSON`,
      );
    }
    if (!response.ok || !isRecord(value) || value.success !== true) {
      const codes =
        isRecord(value) && Array.isArray(value.errors)
          ? value.errors.flatMap((error: unknown) =>
              isRecord(error) && typeof error.code === 'number'
                ? [error.code]
                : [],
            )
          : [];
      const messages =
        isRecord(value) && Array.isArray(value.errors)
          ? value.errors.flatMap((error: unknown) =>
              typeof error === 'string'
                ? [error]
                : isRecord(error) && typeof error.message === 'string'
                  ? [error.message]
                  : [],
            )
          : [];
      throw new CheckFailure(
        `Cloudflare HTTP ${response.status}; API codes: ${codes.join(',') || 'unavailable'}; ${redact(messages.join('; ')).slice(0, 1500)}`,
      );
    }
    return value.result;
  }
  async function check(
    target: Record<string, Check>,
    key: string,
    action: () => Promise<string>,
  ) {
    try {
      target[key] = { status: 'passed', detail: await action() };
    } catch (error) {
      target[key] = { status: 'failed', detail: safeError(error) };
    }
    console.log(`${key}: ${target[key]?.status} — ${target[key]?.detail}`);
  }
  async function existingWorker(
    cleaning = false,
  ): Promise<Record<string, unknown>> {
    let metadata: unknown;
    try {
      metadata = await api(
        `${workerPath}/settings`,
        'GET',
        undefined,
        cleaning,
        true,
      );
    } catch (error) {
      if (!(error instanceof CheckFailure) || !/\b10007\b/.test(error.message))
        throw error;
    }
    if (metadata === undefined || metadata === null)
      throw new CheckFailure(
        `Isolated Worker ${workerName} is missing; bootstrap it manually with workers.dev and previews disabled and no routes, then rerun. This check never creates a Worker`,
      );
    if (!isRecord(metadata))
      throw new CheckFailure('Existing isolated Worker metadata was invalid');
    return metadata;
  }
  async function deploy(cleaning = false) {
    // The token only needs to edit an existing isolated Worker. Never turn a
    // missing pre-created Worker into an implicit create attempt.
    await existingWorker(cleaning);
    const require = createRequire(
      new URL('../apps/api/package.json', import.meta.url),
    );
    const resolved = require.resolve('wrangler');
    const cli = path.join(path.dirname(resolved), '../bin/wrangler.js');
    const locked: unknown = JSON.parse(
      await readFile(
        path.join(path.dirname(resolved), '../package.json'),
        'utf8',
      ),
    );
    if (!isRecord(locked) || locked.version !== '4.156.1')
      throw new CheckFailure('Expected repository-pinned Wrangler 4.156.1');
    const configuration = path.join(
      temporary,
      cleaning ? 'baseline.wrangler.json' : 'check.wrangler.json',
    );
    if (!cleaning) {
      await mkdir(path.join(temporary, 'public'), { recursive: true });
      await writeFile(
        path.join(temporary, 'public/check.txt'),
        `Static upload permission check ${randomUUID()}\n`,
      );
    }
    const entry = cleaning ? 'baseline.ts' : 'worker.ts';
    await writeFile(
      path.join(temporary, entry),
      cleaning
        ? 'export default { fetch() { return new Response(null, { status: 404 }); } };\n'
        : "export default { fetch() { return new Response('Temporary permission check'); } };\n",
    );
    await writeFile(
      configuration,
      JSON.stringify({
        name: workerName,
        main: './' + entry,
        account_id: account,
        compatibility_date: '2026-11-03',
        workers_dev: false,
        preview_urls: false,
        routes: [],
        ...(cleaning
          ? {}
          : {
              assets: {
                directory: './public',
                binding: 'ASSETS',
                not_found_handling: 'none',
              },
            }),
        observability: { enabled: false },
      }),
    );
    if (!cleaning) workerAttempted = true;
    await deployPermissionProbe({
      wranglerCli: cli,
      configuration,
      temporaryDirectory: temporary,
      token: deploymentToken,
      restoringBaseline: cleaning,
      signal: abort.signal,
    });
    if (!cleaning) workerUploaded = true;
    const subdomain = await api(
      `${workerPath}/subdomain`,
      'GET',
      undefined,
      cleaning,
    );
    if (
      !isRecord(subdomain) ||
      subdomain.enabled !== false ||
      subdomain.previews_enabled !== false
    )
      throw new CheckFailure(
        'Isolated Worker public workers.dev/preview URLs were not both disabled',
      );
    if (cleaning) {
      const metadata = await existingWorker(true);
      if (
        metadata.assets != null ||
        (Array.isArray(metadata.bindings) &&
          metadata.bindings.some(
            (binding: unknown) =>
              isRecord(binding) && binding.type === 'assets',
          ))
      )
        throw new CheckFailure(
          'Isolated Worker baseline still has Static Assets',
        );
    }
  }

  try {
    await check(checks, 'Worker + Static Assets Write', async () => {
      await deploy();
      return `Wrangler 4.156.1 updated existing ${workerName} and uploaded one unique static file; workers.dev and preview URLs disabled`;
    });
    await check(checks, 'D1 Write', async () => {
      databaseAttempted = true;
      const database = await api(`${accountPath}/d1/database`, 'POST', {
        name,
      });
      if (
        !isRecord(database) ||
        !identifier(database.uuid, /^[a-f0-9-]{36}$/) ||
        database.name !== name
      )
        throw new CheckFailure(
          'D1 create response did not identify the temporary database',
        );
      databaseId = database.uuid;
      const query = await api(
        `${accountPath}/d1/database/${databaseId}/query`,
        'POST',
        {
          batch: [
            { sql: 'CREATE TABLE permission_check (value TEXT NOT NULL)' },
            { sql: 'INSERT INTO permission_check VALUES (?)', params: [name] },
            { sql: 'SELECT value FROM permission_check' },
          ],
        },
      );
      if (
        !Array.isArray(query) ||
        query.length === 0 ||
        !query.every(
          (result: unknown) => isRecord(result) && result.success === true,
        ) ||
        !query.some(
          (result: unknown) =>
            isRecord(result) &&
            Array.isArray(result.results) &&
            result.results.some(
              (row: unknown) => isRecord(row) && row.value === name,
            ),
        )
      )
        throw new CheckFailure('Temporary D1 write/read result did not match');
      return 'Created an isolated database, created a table, wrote and read the unique marker';
    });
    await check(checks, 'Workers Routes Edit', async () => {
      const configured = process.env.CLOUDFLARE_ZONE_ID;
      if (configured !== undefined) {
        if (!identifier(configured))
          throw new CheckFailure('CLOUDFLARE_ZONE_ID is invalid');
        zoneId = configured;
      } else {
        const zones = await api(`/zones?name=wybxc.cc&account.id=${account}`);
        if (
          !Array.isArray(zones) ||
          zones.length !== 1 ||
          !isRecord(zones[0]) ||
          zones[0].name !== 'wybxc.cc' ||
          !identifier(zones[0].id)
        )
          throw new CheckFailure(
            'Zone Read must identify the single wybxc.cc zone for this account',
          );
        zoneId = zones[0].id;
      }
      routeAttempted = true;
      const route = await api(`/zones/${zoneId}/workers/routes`, 'POST', {
        pattern: routePattern,
        ...(workerUploaded ? { script: workerName } : {}),
      });
      if (
        !isRecord(route) ||
        !identifier(route.id) ||
        route.pattern !== routePattern ||
        (workerUploaded && route.script !== workerName)
      )
        throw new CheckFailure('Temporary route create response did not match');
      routeId = route.id;
      return 'Created one unique random-subdomain route in wybxc.cc; no DNS record changed';
    });
  } finally {
    // Recover IDs by their unique name/pattern if a create response was lost.
    await check(cleanup, 'Cleanup route', async () => {
      if (routeAttempted && zoneId) {
        if (!routeId) {
          const routes = await api(
            `/zones/${zoneId}/workers/routes`,
            'GET',
            undefined,
            true,
          );
          if (!Array.isArray(routes))
            throw new CheckFailure('Cannot inspect temporary route cleanup');
          const route = routes.find(
            (value: unknown) =>
              isRecord(value) && value.pattern === routePattern,
          );
          if (isRecord(route) && identifier(route.id)) routeId = route.id;
        }
        if (routeId)
          await api(
            `/zones/${zoneId}/workers/routes/${routeId}`,
            'DELETE',
            undefined,
            true,
            true,
          );
      }
      return 'Temporary route removed or never created';
    });
    await check(cleanup, 'Cleanup Worker', async () => {
      if (workerAttempted) {
        await deploy(true);
        return `Restored ${workerName} to the empty baseline without assets, routes or public URLs; Worker retained`;
      }
      return 'Isolated Worker was not modified; no create or delete attempted';
    });
    await check(cleanup, 'Cleanup D1', async () => {
      if (databaseAttempted) {
        if (!databaseId) {
          const databases = await api(
            `${accountPath}/d1/database?name=${name}`,
            'GET',
            undefined,
            true,
          );
          if (!Array.isArray(databases))
            throw new CheckFailure('Cannot inspect temporary D1 cleanup');
          const database = databases.find(
            (value: unknown) => isRecord(value) && value.name === name,
          );
          if (
            isRecord(database) &&
            identifier(database.uuid, /^[a-f0-9-]{36}$/)
          )
            databaseId = database.uuid;
        }
        if (databaseId)
          await api(
            `${accountPath}/d1/database/${databaseId}`,
            'DELETE',
            undefined,
            true,
            true,
          );
      }
      return 'Temporary database removed or never created';
    });
    await rm(temporary, { recursive: true, force: true });
    process.off('SIGINT', stop);
    process.off('SIGTERM', stop);
    const passed =
      Object.keys(checks).length === 3 &&
      [...Object.values(checks), ...Object.values(cleanup)].every(
        (value) => value.status === 'passed',
      ) &&
      !abort.signal.aborted;
    console.log(
      JSON.stringify(
        {
          passed,
          isolatedWorker: workerName,
          temporaryResourceLabel: name,
          checks,
          cleanup,
        },
        null,
        2,
      ),
    );
    if (process.env.GITHUB_STEP_SUMMARY)
      await appendFile(
        process.env.GITHUB_STEP_SUMMARY,
        `Cloudflare permission check: **${passed ? 'PASSED' : 'FAILED'}**\n\nTemporary resource label: \`${name}\`\n\n| Check | Result | Detail |\n| --- | --- | --- |\n${Object.entries(
          { ...checks, ...cleanup },
        )
          .map(
            ([key, value]) => `| ${key} | ${value.status} | ${value.detail} |`,
          )
          .join('\n')}\n`,
      );
    if (!passed) process.exitCode = 1;
  }
}

await main().catch((error: unknown) => {
  console.error(`Cloudflare permission check failed: ${safeError(error)}`);
  process.exitCode = 1;
});
