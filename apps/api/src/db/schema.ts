import {
  integer,
  foreignKey,
  primaryKey,
  sqliteTable,
  text,
  uniqueIndex,
} from 'drizzle-orm/sqlite-core';

// Business tables follow their P0/P1 contracts; no deferred modules are seeded.
export const appMetadata = sqliteTable('app_metadata', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});

export const extensionBuilds = sqliteTable(
  'extension_builds',
  {
    buildId: text('build_id').primaryKey(),
    packageName: text('package_name').notNull(),
    catalogUrl: text('catalog_url').notNull(),
    repoId: text('repo_id').notNull(),
    bundleSha256: text('bundle_sha256').notNull(),
    status: text('status', { enum: ['verified', 'disabled'] }).notNull(),
    createdAt: integer('created_at').notNull(),
    allowedHostsJson: text('allowed_hosts_json').notNull().default('[]'),
  },
  (table) => [
    uniqueIndex('extension_builds_catalog_package_unique').on(
      table.catalogUrl,
      table.repoId,
      table.packageName,
    ),
  ],
);

export const accountState = sqliteTable('account_state', {
  subject: text('subject').primaryKey(),
  revision: integer('revision').notNull().default(0),
  categoriesRevision: integer('categories_revision').notNull().default(0),
});

export const categories = sqliteTable(
  'categories',
  {
    subject: text('subject').notNull(),
    id: text('id').notNull(),
    name: text('name').notNull(),
    sortOrder: integer('sort_order').notNull(),
  },
  (table) => [primaryKey({ columns: [table.subject, table.id] })],
);

export const mangaState = sqliteTable(
  'manga_state',
  {
    subject: text('subject').notNull(),
    mangaKey: text('manga_key').notNull(),
    revision: integer('revision').notNull(),
    favorite: integer('favorite', { mode: 'boolean' }).notNull(),
    stateJson: text('state_json').notNull(),
  },
  (table) => [primaryKey({ columns: [table.subject, table.mangaKey] })],
);

export const coverAssets = sqliteTable(
  'cover_assets',
  {
    subject: text('subject').notNull(),
    mangaKey: text('manga_key').notNull(),
    assetId: text('asset_id').notNull(),
    objectKey: text('object_key').notNull(),
    descriptorJson: text('descriptor_json').notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.subject, table.mangaKey] }),
    uniqueIndex('cover_assets_subject_asset').on(table.subject, table.assetId),
    uniqueIndex('cover_assets_object_key').on(table.objectKey),
    foreignKey({
      columns: [table.subject, table.mangaKey],
      foreignColumns: [mangaState.subject, mangaState.mangaKey],
    }).onDelete('cascade'),
  ],
);

export const chapterProgress = sqliteTable(
  'chapter_progress',
  {
    subject: text('subject').notNull(),
    mangaKey: text('manga_key').notNull(),
    chapterKey: text('chapter_key').notNull(),
    stateJson: text('state_json').notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.subject, table.mangaKey, table.chapterKey] }),
  ],
);

export const chapterBookmarks = sqliteTable(
  'chapter_bookmarks',
  {
    subject: text('subject').notNull(),
    mangaKey: text('manga_key').notNull(),
    chapterKey: text('chapter_key').notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.subject, table.mangaKey, table.chapterKey] }),
  ],
);

export const stateMutations = sqliteTable(
  'state_mutations',
  {
    subject: text('subject').notNull(),
    mutationId: text('mutation_id').notNull(),
    requestHash: text('request_hash').notNull(),
    attemptNonce: text('attempt_nonce').notNull(),
    responseJson: text('response_json').notNull(),
    kind: text('kind', {
      enum: ['manga', 'category', 'settings', 'source_preferences'],
    })
      .notNull()
      .default('manga'),
  },
  (table) => [primaryKey({ columns: [table.subject, table.mutationId] })],
);

export const readerSettings = sqliteTable(
  'reader_settings',
  {
    subject: text('subject').notNull(),
    // Empty key is the account default; manga overrides use canonical manga keys.
    scopeKey: text('scope_key').notNull(),
    revision: integer('revision').notNull(),
    valuesJson: text('values_json').notNull(),
  },
  (table) => [primaryKey({ columns: [table.subject, table.scopeKey] })],
);

export const mangaCategories = sqliteTable(
  'manga_categories',
  {
    subject: text('subject').notNull(),
    mangaKey: text('manga_key').notNull(),
    categoryId: text('category_id').notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.subject, table.mangaKey, table.categoryId] }),
    foreignKey({
      columns: [table.subject, table.mangaKey],
      foreignColumns: [mangaState.subject, mangaState.mangaKey],
    }).onDelete('cascade'),
    foreignKey({
      columns: [table.subject, table.categoryId],
      foreignColumns: [categories.subject, categories.id],
    }).onDelete('cascade'),
  ],
);

export const sourcePreferences = sqliteTable(
  'source_preferences',
  {
    subject: text('subject').notNull(),
    catalogUrl: text('catalog_url').notNull(),
    repoId: text('repo_id').notNull(),
    packageName: text('package_name').notNull(),
    sourceId: text('source_id').notNull(),
    revision: integer('revision').notNull(),
    entriesJson: text('entries_json').notNull(),
  },
  (table) => [
    primaryKey({
      columns: [
        table.subject,
        table.catalogUrl,
        table.repoId,
        table.packageName,
        table.sourceId,
      ],
    }),
  ],
);
