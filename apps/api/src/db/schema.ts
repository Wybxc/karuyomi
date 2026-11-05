import {
  integer,
  foreignKey,
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
  packageName: text('package_name').notNull().unique(),
  bundleSha256: text('bundle_sha256').notNull(),
  status: text('status', { enum: ['verified', 'disabled'] }).notNull(),
  createdAt: integer('created_at').notNull(),
  allowedHostsJson: text('allowed_hosts_json').notNull().default('[]'),
});

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
    kind: text('kind', { enum: ['manga', 'category'] })
      .notNull()
      .default('manga'),
  },
  (table) => [primaryKey({ columns: [table.subject, table.mutationId] })],
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
