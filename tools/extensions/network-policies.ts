#!/usr/bin/env node
// Trusted post-deployment operation; AOT jobs never receive D1 credentials.
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { z } from 'zod';
import {
  runtimeMaterialCatalogSchema,
  validateCatalogReference,
  type CatalogReference,
  type ExtensionIndex,
} from '@karuyomi/contracts';
import { parseManifest } from './verify-manifest.ts';
import type { BuildManifest } from '../../packages/contracts/src/index.ts';
import {
  assertIndexIdentity,
  destinationLoader,
  destinationCatalogUrl,
  destinationOptions,
  executeD1,
  loadStaticIndex,
  MANIFEST_METADATA_LIMIT,
  networkHosts,
  policyDestination,
  quote,
  verifyMetadata,
  writePolicyTransaction,
  type D1Executor,
  type MaterialCatalogRefs,
  type MetadataLoader,
} from './registration.ts';

export interface ApprovedPolicy {
  catalogUrl: string;
  repoId: string;
  packageName: string;
  buildId: string;
  bundleSha256: string;
  allowedHostsJson: string;
}
const rowSchema = z.object({
  catalog_url: z.string(),
  repo_id: z.string(),
  package_name: z.string().min(1).max(200),
  build_id: z.string().min(1).max(200),
  bundle_sha256: z.string().regex(/^[a-f0-9]{64}$/),
  allowed_hosts_json: z.string(),
});
const responseSchema = z
  .array(z.object({ success: z.literal(true), results: z.array(rowSchema) }))
  .length(1);
export function policyRows(value: unknown): ApprovedPolicy[] {
  const rows = responseSchema.parse(value)[0]?.results;
  if (!rows) throw new Error('Invalid Wrangler D1 JSON response');
  const packages = new Set<string>();
  return rows.map((row) => {
    const identity = JSON.stringify([
      row.catalog_url,
      row.repo_id,
      row.package_name,
    ]);
    validateCatalogReference({
      catalogUrl: row.catalog_url,
      repoId: row.repo_id,
    });
    if (packages.has(identity))
      throw new Error('Duplicate approved network policy package');
    packages.add(identity);
    const hosts: unknown = JSON.parse(row.allowed_hosts_json);
    networkHosts(z.array(z.string()).parse(hosts));
    return {
      catalogUrl: row.catalog_url,
      repoId: row.repo_id,
      packageName: row.package_name,
      buildId: row.build_id,
      bundleSha256: row.bundle_sha256,
      allowedHostsJson: row.allowed_hosts_json,
    };
  });
}

/** Only metadata is fetched. Extension gzip bytes are not transferred again. */
export async function currentBuilds(
  load: MetadataLoader,
  knownIndex?: ExtensionIndex,
): Promise<Map<string, BuildManifest>> {
  const index = knownIndex ?? (await loadStaticIndex(load));
  let catalog: MaterialCatalogRefs | undefined;
  const current = new Map<string, BuildManifest>();
  for (const descriptor of index.builds) {
    const manifest = await parseManifest(
      await load(descriptor.manifestPath, MANIFEST_METADATA_LIMIT),
    );
    assertIndexIdentity(manifest, descriptor);
    if (manifest.hostScripts.length || manifest.resources.length)
      catalog ??= runtimeMaterialCatalogSchema.parse(
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
    await verifyMetadata(manifest, catalog);
    current.set(manifest.packageName, manifest);
  }
  return current;
}

export function synchronizationSql(
  current: ReadonlyMap<string, BuildManifest>,
  approved: readonly ApprovedPolicy[],
  catalog: CatalogReference,
): string {
  validateCatalogReference(catalog);
  if (
    [...current.values()].some((manifest) => manifest.repoId !== catalog.repoId)
  )
    throw new Error('Current build belongs to a different catalog');
  const scope = `catalog_url=${quote(catalog.catalogUrl)} AND repo_id=${quote(catalog.repoId)}`;
  const statements: string[] = [];
  for (const policy of approved) {
    if (
      policy.catalogUrl !== catalog.catalogUrl ||
      policy.repoId !== catalog.repoId
    )
      continue;
    const manifest = current.get(policy.packageName);
    if (!manifest) continue;
    // Preserve the approval bytes and status. Concurrent disable/policy changes
    // fail the NOT NULL guard and roll back the complete file transaction.
    statements.push(
      `UPDATE extension_builds SET bundle_sha256=CASE WHEN build_id=${quote(policy.buildId)} AND bundle_sha256=${quote(policy.bundleSha256)} AND status='verified' AND json(allowed_hosts_json)=json(${quote(policy.allowedHostsJson)}) THEN ${quote(manifest.bundle.sha256)} ELSE NULL END,build_id=${quote(manifest.buildId)} WHERE ${scope} AND package_name=${quote(policy.packageName)};`,
    );
  }
  const ids = [...current.values()].map((value) => value.buildId).sort();
  statements.push(
    'DELETE FROM extension_builds WHERE ' +
      scope +
      (ids.length ? ` AND build_id NOT IN (${ids.map(quote).join(',')})` : '') +
      ';',
  );
  return statements.join('\n') + '\n';
}

export async function networkPoliciesMain(
  args = process.argv.slice(2),
  execute: D1Executor = executeD1,
) {
  const { values } = parseArgs({
    args,
    options: { ...destinationOptions, help: { type: 'boolean' } },
  });
  if (values.help) {
    console.log(
      'node tools/extensions/network-policies.ts --remote | --local --static-root SNAPSHOT [--persist-to STATE]',
    );
    return;
  }
  const destination = policyDestination(values, true);
  if (!destination) throw new Error('Missing policy destination');
  const load = await destinationLoader(destination);
  const index = await loadStaticIndex(load);
  const catalog = {
    catalogUrl: await destinationCatalogUrl(destination),
    repoId: index.repoId,
  };
  const current = await currentBuilds(load, index);
  const approved = policyRows(
    await execute(
      [
        '--command',
        `SELECT catalog_url,repo_id,package_name,build_id,bundle_sha256,allowed_hosts_json FROM extension_builds WHERE status='verified' AND catalog_url=${quote(catalog.catalogUrl)} AND repo_id=${quote(catalog.repoId)}`,
      ],
      destination,
    ),
  );
  await writePolicyTransaction(
    synchronizationSql(current, approved, catalog),
    destination,
    execute,
  );
  console.log(
    JSON.stringify(
      {
        currentPackages: current.size,
        inheritedPolicies: approved.filter((policy) =>
          current.has(policy.packageName),
        ).length,
        newPackagesRemainUnapproved: [...current.keys()].filter(
          (packageName) =>
            !approved.some((policy) => policy.packageName === packageName),
        ).length,
        destination: destination.mode,
      },
      null,
      2,
    ),
  );
}
if (import.meta.main) await networkPoliciesMain();
