import { sqliteTable, text } from 'drizzle-orm/sqlite-core';

// Business tables follow their P0/P1 contracts; no deferred modules are seeded.
export const appMetadata = sqliteTable('app_metadata', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});
