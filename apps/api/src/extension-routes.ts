import { create, toJson } from '@bufbuild/protobuf';
import {
  CatalogReferenceSchema,
  ExtensionNetworkPoliciesResponseSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  extensionNetworkPoliciesResponseSchema,
  validateCatalogReference,
} from '@karuyomi/contracts';
import { Hono } from 'hono';
import type { AppEnv } from './env.js';

export function createExtensionRoutes() {
  const app = new Hono<AppEnv>();
  app.get('/network-policies', async (c) => {
    if (c.req.header('X-App-Subject') !== c.get('identity').subject)
      return c.json({ error: 'identity_changed' }, 403);
    const catalog = create(CatalogReferenceSchema, {
      catalogUrl: c.req.query('catalogUrl') ?? '',
      repoId: c.req.query('repoId') ?? '',
    });
    try {
      validateCatalogReference(catalog);
    } catch {
      return c.json({ error: 'invalid_catalog' }, 400);
    }
    const rows = await c.env.DB.prepare(
      "SELECT build_id,package_name,bundle_sha256 FROM extension_builds WHERE catalog_url=? AND repo_id=? AND status='verified' ORDER BY package_name LIMIT 5001",
    )
      .bind(catalog.catalogUrl, catalog.repoId)
      .all<{ build_id: string; package_name: string; bundle_sha256: string }>();
    const result = extensionNetworkPoliciesResponseSchema.parse(
      toJson(
        ExtensionNetworkPoliciesResponseSchema,
        create(ExtensionNetworkPoliciesResponseSchema, {
          schemaVersion: businessSchemaVersion,
          catalog,
          builds: rows.results.map((row) => ({
            buildId: row.build_id,
            packageName: row.package_name,
            bundleSha256: row.bundle_sha256,
          })),
        }),
      ),
    );
    return c.json(toJson(ExtensionNetworkPoliciesResponseSchema, result));
  });
  return app;
}
