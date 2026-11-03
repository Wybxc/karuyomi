import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

// Business tables follow their P0/P1 contracts; no deferred modules are seeded.
export const appMetadata = sqliteTable('app_metadata', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});

export const extensionBuilds = sqliteTable('extension_builds', {
  buildId: text('build_id').primaryKey(),
  packageName: text('package_name').notNull().unique(),
  bundleSha256: text('bundle_sha256').notNull(),
  status: text('status', { enum: ['verified', 'disabled'] }).notNull(),
  createdAt: integer('created_at').notNull(),
  allowedHostsJson: text('allowed_hosts_json').notNull().default('[]'),
});
