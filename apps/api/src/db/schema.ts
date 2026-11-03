import {
  integer,
  primaryKey,
  sqliteTable,
  text,
} from 'drizzle-orm/sqlite-core';

// Business tables follow their P0/P1 contracts; no deferred modules are seeded.
export const appMetadata = sqliteTable('app_metadata', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});

export const extensionBuilds = sqliteTable('extension_builds', {
  buildId: text('build_id').primaryKey(),
  packageName: text('package_name').notNull(),
  manifestJson: text('manifest_json').notNull(),
  status: text('status', { enum: ['verified', 'disabled'] }).notNull(),
  createdAt: integer('created_at').notNull(),
  allowedHostsJson: text('allowed_hosts_json').notNull().default('[]'),
});

export const extensionArtifacts = sqliteTable('extension_artifacts', {
  sha256: text('sha256').primaryKey(),
  objectKey: text('object_key').notNull().unique(),
  size: integer('size').notNull(),
  contentType: text('content_type').notNull(),
});

export const buildArtifacts = sqliteTable(
  'build_artifacts',
  {
    buildId: text('build_id')
      .notNull()
      .references(() => extensionBuilds.buildId),
    sha256: text('sha256')
      .notNull()
      .references(() => extensionArtifacts.sha256),
  },
  (table) => [primaryKey({ columns: [table.buildId, table.sha256] })],
);
