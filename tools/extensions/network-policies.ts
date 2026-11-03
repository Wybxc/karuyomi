#!/usr/bin/env node
// Trusted post-deployment operation; AOT jobs never receive D1 credentials.
import { parseArgs } from 'node:util';
import { z } from 'zod';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import { parseManifest } from './verify-manifest.ts';
import type { BuildManifest } from '../../packages/contracts/src/index.ts';
import {
  assertIndexIdentity,
  destinationLoader,
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
  packageName: string;
  buildId: string;
  bundleSha256: string;
  allowedHostsJson: string;
}
const rowSchema = z.object({
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
    if (packages.has(row.package_name))
      throw new Error('Duplicate approved network policy package');
    packages.add(row.package_name);
    const hosts: unknown = JSON.parse(row.allowed_hosts_json);
    networkHosts(z.array(z.string()).parse(hosts));
    return {
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
): Promise<Map<string, BuildManifest>> {
  const index = await loadStaticIndex(load);
  let catalog: MaterialCatalogRefs | undefined;
  const current = new Map<string, BuildManifest>();
  for (const descriptor of index.builds) {
    const manifest = await parseManifest(
      await load(descriptor.manifestPath, MANIFEST_METADATA_LIMIT),
    );
    assertIndexIdentity(manifest, descriptor);
    if (manifest.hostScripts.length || manifest.resources.length)
      catalog ??= (await collectMaterials({ includeWasmBytes: false })).catalog;
    await verifyMetadata(manifest, catalog);
    current.set(manifest.packageName, manifest);
  }
  return current;
}

export function synchronizationSql(
  current: ReadonlyMap<string, BuildManifest>,
  approved: readonly ApprovedPolicy[],
): string {
  const statements: string[] = [];
  for (const policy of approved) {
    const manifest = current.get(policy.packageName);
    if (!manifest) continue;
    // Preserve the approval bytes and status. Concurrent disable/policy changes
    // fail the NOT NULL guard and roll back the complete file transaction.
    statements.push(
      `UPDATE extension_builds SET bundle_sha256=CASE WHEN build_id=${quote(policy.buildId)} AND bundle_sha256=${quote(policy.bundleSha256)} AND status='verified' AND json(allowed_hosts_json)=json(${quote(policy.allowedHostsJson)}) THEN ${quote(manifest.bundle.sha256)} ELSE NULL END,build_id=${quote(manifest.buildId)} WHERE package_name=${quote(policy.packageName)};`,
    );
  }
  const ids = [...current.values()].map((value) => value.buildId).sort();
  statements.push(
    'DELETE FROM extension_builds' +
      (ids.length
        ? ` WHERE build_id NOT IN (${ids.map(quote).join(',')})`
        : '') +
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
  const current = await currentBuilds(await destinationLoader(destination));
  const approved = policyRows(
    await execute(
      [
        '--command',
        "SELECT package_name,build_id,bundle_sha256,allowed_hosts_json FROM extension_builds WHERE status='verified'",
      ],
      destination,
    ),
  );
  await writePolicyTransaction(
    synchronizationSql(current, approved),
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
