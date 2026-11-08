#!/usr/bin/env node
// Validate authoritative static metadata, then register explicit Source policy only.
import { isDeepStrictEqual, parseArgs } from 'node:util';
import { mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { URL } from 'node:url';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  buildIdSchema,
  runtimeMaterialCatalogSchema,
  catalogReferenceSchema,
  validateExtensionCatalogUrl,
  type CatalogReference,
} from '@karuyomi/contracts';
import type {
  BuildManifest,
  ExtensionIndex,
} from '../../packages/contracts/src/index.ts';
import isRecord from 'is-plain-obj';
import { execa } from 'execa';
import {
  parseManifest,
  parseManifestValue,
  parseExtensionIndex,
  readRegularFile,
  repositoryRoot,
  verifyBundleFile,
  verifyMaterialReferences,
  type MaterialCatalogRefs,
} from './verify-manifest.ts';

export type { MaterialCatalogRefs } from './verify-manifest.ts';
export type MetadataLoader = (
  pathname: string,
  limit: number,
) => Promise<Uint8Array>;
export type PolicyDestination =
  | { mode: 'remote'; catalogUrl?: string }
  | {
      mode: 'local';
      staticRoot: string;
      persistTo?: string;
      catalogUrl?: string;
    };
export type D1Executor = (
  arguments_: readonly string[],
  destination: PolicyDestination,
) => Promise<unknown>;
export const INDEX_METADATA_LIMIT = 2 * 1024 * 1024;
export const MANIFEST_METADATA_LIMIT = 64 * 1024;

/** Catalog-only validation does not read any extension or WASM bytes. */
export async function verifyMetadata(
  input: unknown,
  materialCatalog?: MaterialCatalogRefs,
): Promise<BuildManifest> {
  const manifest = await parseManifestValue(input);
  if (manifest.hostScripts.length || manifest.resources.length) {
    const catalog =
      materialCatalog ??
      runtimeMaterialCatalogSchema.parse(
        JSON.parse(
          await readFile(
            new URL(
              '../../packages/runtime-host/dist/materials.json',
              import.meta.url,
            ),
            'utf8',
          ),
        ),
      );
    verifyMaterialReferences(manifest, catalog);
  }
  return manifest;
}

/** false is only for already verified in-process bytes, never a disk resume. */
export async function verifyBuild(
  input: unknown,
  artifactDirectory: string,
  {
    verifyHashes = true,
    materialCatalog,
  }: { verifyHashes?: boolean; materialCatalog?: MaterialCatalogRefs } = {},
): Promise<BuildManifest> {
  const manifest = await verifyMetadata(input, materialCatalog);
  await verifyBundleFile(manifest.bundle, artifactDirectory, { verifyHashes });
  return manifest;
}

export function networkHosts(input: readonly string[]): string[] {
  const hosts = [...new Set(input)].sort();
  if (
    !hosts.every(
      (host) =>
        /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(host) &&
        host.includes('.') &&
        !/^[\d.]+$/.test(host) &&
        !/(?:^|\.)(?:localhost|local|internal|home|invalid|test)$/.test(host),
    )
  )
    throw new Error('Network policy requires explicit public hostnames');
  return hosts;
}
export const quote = (value: string): string =>
  "'" + value.replaceAll("'", "''") + "'";

export function retireNoncurrentBuildsSql(
  catalog: CatalogReference,
  currentBuildIds: Iterable<string>,
): string[] {
  catalogReferenceSchema.parse(catalog);
  const scope = `catalog_url=${quote(catalog.catalogUrl)} AND repo_id=${quote(catalog.repoId)}`;
  const prefix = `DELETE FROM extension_builds WHERE ${scope}`;
  const ids = [...new Set(currentBuildIds)]
    .map((id) => buildIdSchema.parse(id))
    .sort();
  if (ids.length === 0) return [prefix + ';'];

  // D1 caps each statement at 100,000 bytes. At most 400 ASCII IDs of
  // 200 bytes, plus their quotes, scope and range bounds, fit in a statement.
  // Use disjoint lexical ranges so an ID in one group cannot be retired by
  // another group's NOT IN. The build_id column uses SQLite's BINARY order.
  const groupSize = 400;
  const statements: string[] = [];
  let lower = '';
  for (let start = 0; start < ids.length; start += groupSize) {
    const group = ids.slice(start, start + groupSize);
    const next = ids[start + groupSize];
    const upper = next ? ` AND build_id<${quote(next)}` : '';
    statements.push(
      `${prefix}${lower}${upper} AND build_id NOT IN (${group.map(quote).join(',')});`,
    );
    if (next) lower = ` AND build_id>=${quote(next)}`;
  }
  return statements;
}

export function registrationSql(
  manifest: BuildManifest,
  hosts: readonly string[],
  catalog: CatalogReference,
  currentBuildIds?: ReadonlySet<string>,
): string {
  catalogReferenceSchema.parse(catalog);
  if (catalog.repoId !== manifest.repoId)
    throw new Error('Manifest repository differs from registration scope');
  const build = quote(manifest.buildId);
  const packageName = quote(manifest.packageName);
  const policy = quote(JSON.stringify(networkHosts(hosts)));
  const digest = quote(manifest.bundle.sha256);
  const scope = `catalog_url=${quote(catalog.catalogUrl)} AND repo_id=${quote(catalog.repoId)}`;
  const retire = currentBuildIds
    ? retireNoncurrentBuildsSql(catalog, currentBuildIds).join('\n') + '\n'
    : '';
  // The single Wrangler SQL file is transactional. A NOT NULL guard rejects
  // identity/policy conflicts and rolls back preceding retirement statements.
  return (
    retire +
    `DELETE FROM extension_builds WHERE ${scope} AND package_name=${packageName} AND build_id<>${build};\n` +
    `INSERT INTO extension_builds (build_id,package_name,catalog_url,repo_id,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (${build},${packageName},${quote(catalog.catalogUrl)},${quote(catalog.repoId)},${digest},'verified',unixepoch(),${policy}) ON CONFLICT(build_id) DO UPDATE SET bundle_sha256=CASE WHEN extension_builds.catalog_url=excluded.catalog_url AND extension_builds.repo_id=excluded.repo_id AND extension_builds.package_name=excluded.package_name AND extension_builds.bundle_sha256=excluded.bundle_sha256 AND json(extension_builds.allowed_hosts_json)=json(excluded.allowed_hosts_json) THEN extension_builds.bundle_sha256 ELSE NULL END,status='verified';\n`
  );
}

export const loadStaticIndex = async (
  load: MetadataLoader,
): Promise<ExtensionIndex> =>
  parseExtensionIndex(
    await load('/extensions/index.json', INDEX_METADATA_LIMIT),
  );
export function assertIndexIdentity(
  manifest: BuildManifest,
  descriptor: ExtensionIndex['builds'][number] | undefined,
) {
  if (
    !descriptor ||
    !(
      [
        'buildId',
        'packageName',
        'repoId',
        'version',
        'sourceIds',
        'sources',
      ] as const
    ).every((key) => isDeepStrictEqual(descriptor[key], manifest[key]))
  )
    throw new Error('Build is not current in the static index');
}
export async function verifyStaticAuthority(
  manifest: BuildManifest,
  load: MetadataLoader,
): Promise<Set<string>> {
  const index = await loadStaticIndex(load);
  const current = index.builds.find(
    (item) => item.packageName === manifest.packageName,
  );
  assertIndexIdentity(manifest, current);
  if (!current) throw new Error('Missing current static build');
  const deployed = await parseManifest(
    await load(current.manifestPath, MANIFEST_METADATA_LIMIT),
  );
  if (!isDeepStrictEqual(deployed, manifest))
    throw new Error('Static manifest differs from supplied build');
  return new Set(index.builds.map((item) => item.buildId));
}

export function snapshotLoader(directory: string): MetadataLoader {
  const base = realpath(directory);
  return async (pathname, limit) => {
    const root = await base;
    const file = path.join(root, pathname);
    const relative = path.relative(root, await realpath(file));
    if (
      relative === '..' ||
      relative.startsWith('..' + path.sep) ||
      path.isAbsolute(relative)
    )
      throw new Error('Invalid static snapshot path');
    return readRegularFile(file, limit);
  };
}
export function deployedLoader(origin: string): MetadataLoader {
  const parsed = new URL(origin);
  if (
    parsed.protocol !== 'https:' ||
    parsed.origin !== origin ||
    parsed.username ||
    parsed.password
  )
    throw new Error('Static authority requires a configured HTTPS origin');
  return async (pathname, limit) => {
    const url = new URL(pathname, origin);
    if (url.origin !== origin)
      throw new Error('Invalid static metadata origin');
    const response = await fetch(url, {
      headers: { Accept: 'application/json', 'Cache-Control': 'no-cache' },
      redirect: 'error',
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok || !response.body)
      throw new Error(`Static metadata HTTP ${response.status}`);
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      for (;;) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.byteLength;
        if (size > limit) throw new Error('Static metadata exceeds limit');
        chunks.push(next.value);
      }
      return Buffer.concat(chunks, size);
    } finally {
      await reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  };
}
export async function destinationCatalogUrl(
  destination: PolicyDestination,
): Promise<string> {
  if (destination.catalogUrl) return destination.catalogUrl;
  const configuration = await readFile(
    path.join(repositoryRoot, 'apps/api/wrangler.jsonc'),
    'utf8',
  );
  const origin = /"APP_ORIGIN":\s*"([^"\n]+)"/.exec(configuration)?.[1];
  if (!origin) throw new Error('APP_ORIGIN is missing');
  const url = origin + '/extensions/index.json';
  validateExtensionCatalogUrl(url);
  return url;
}
export async function destinationLoader(
  destination: PolicyDestination,
): Promise<MetadataLoader> {
  if (destination.mode === 'local')
    return snapshotLoader(destination.staticRoot);
  return deployedLoader(
    new URL(await destinationCatalogUrl(destination)).origin,
  );
}

export const destinationOptions = {
  'catalog-url': { type: 'string' },
  local: { type: 'boolean' },
  remote: { type: 'boolean' },
  'static-root': { type: 'string' },
  'persist-to': { type: 'string' },
} as const;
export function policyDestination(
  values: {
    local?: boolean;
    remote?: boolean;
    'static-root'?: string;
    'persist-to'?: string;
    'catalog-url'?: string;
  },
  required = false,
): PolicyDestination | undefined {
  if (values['catalog-url']) validateExtensionCatalogUrl(values['catalog-url']);
  if (values.local && values.remote)
    throw new Error('--local and --remote are mutually exclusive');
  if ((values['static-root'] || values['persist-to']) && !values.local)
    throw new Error('Local static snapshots/state require --local');
  if (values.local) {
    if (!values['static-root'])
      throw new Error('--local requires an explicit --static-root snapshot');
    return {
      mode: 'local',
      ...(values['catalog-url'] ? { catalogUrl: values['catalog-url'] } : {}),
      staticRoot: path.resolve(values['static-root']),
      ...(values['persist-to']
        ? { persistTo: path.resolve(values['persist-to']) }
        : {}),
    };
  }
  if (values.remote)
    return {
      mode: 'remote',
      ...(values['catalog-url'] ? { catalogUrl: values['catalog-url'] } : {}),
    };
  if (required) throw new Error('Specify --local or --remote');
  return undefined;
}

export const executeD1: D1Executor = async (arguments_, destination) => {
  const require = createRequire(
    new URL('../../apps/api/package.json', import.meta.url),
  );
  const flags =
    destination.mode === 'remote'
      ? ['--remote']
      : [
          '--local',
          ...(destination.persistTo
            ? ['--persist-to', destination.persistTo]
            : []),
        ];
  const { stdout } = await execa(
    process.execPath,
    [
      require.resolve('wrangler'),
      'd1',
      'execute',
      'DB',
      ...flags,
      ...arguments_,
      '--json',
    ],
    {
      shell: false,
      stdin: 'ignore',
      preferLocal: false,
      stripFinalNewline: false,
      verbose: 'none',
      cwd: path.join(repositoryRoot, 'apps/api'),
      maxBuffer: 8 * 1024 * 1024,
      extendEnv: false,
      env: {
        ...process.env,
        CLOUDFLARE_SEND_METRICS: 'false',
        // --json suppresses D1 logs but not its separate upload spinner logger.
        // Set both loggers before Wrangler's command middleware initializes.
        WRANGLER_LOG: 'error',
        WRANGLER_LOG_PATH:
          process.env.WRANGLER_LOG_PATH ??
          path.join(repositoryRoot, '.local/extensions/network-policy.log'),
      },
    },
  );
  const value: unknown = JSON.parse(stdout);
  if (
    !Array.isArray(value) ||
    !value.length ||
    !value.every((item: unknown) => isRecord(item) && item.success === true)
  )
    throw new Error('Wrangler D1 operation failed');
  return value;
};
export async function writePolicyTransaction(
  sql: string,
  destination: PolicyDestination,
  execute: D1Executor = executeD1,
) {
  const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-policy-'));
  try {
    const file = path.join(temporary, 'policy.sql');
    await writeFile(file, sql);
    await execute(['--file', file, '--yes'], destination);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

export async function registrationMain(
  args = process.argv.slice(2),
  execute: D1Executor = executeD1,
) {
  const { values, positionals } = parseArgs({
    args,
    allowPositionals: true,
    options: {
      ...destinationOptions,
      'allow-host': { type: 'string', multiple: true },
      help: { type: 'boolean' },
    },
  });
  if (values.help) {
    console.log(
      'node tools/extensions/registration.ts MANIFEST [--allow-host HOST] [--remote | --local --static-root SNAPSHOT] [--persist-to STATE] [--catalog-url URL]',
    );
    return;
  }
  if (positionals.length !== 1 || !positionals[0])
    throw new Error('Expected one build manifest path');
  const destination = policyDestination(values);
  const file = path.resolve(positionals[0]);
  const manifest = await verifyMetadata(
    await parseManifest(await readRegularFile(file, MANIFEST_METADATA_LIMIT)),
  );
  const hosts = networkHosts(values['allow-host'] ?? []);
  const current = destination
    ? await verifyStaticAuthority(
        manifest,
        await destinationLoader(destination),
      )
    : undefined;
  console.log(
    JSON.stringify(
      {
        buildId: manifest.buildId,
        artifacts: 1,
        totalBytes: manifest.bundle.size,
        allowedHosts: hosts,
        destination: destination?.mode ?? 'plan-only',
      },
      null,
      2,
    ),
  );
  if (destination)
    await writePolicyTransaction(
      registrationSql(
        manifest,
        hosts,
        {
          catalogUrl: await destinationCatalogUrl(destination),
          repoId: manifest.repoId,
        },
        current,
      ),
      destination,
      execute,
    );
}
if (import.meta.main) await registrationMain();
