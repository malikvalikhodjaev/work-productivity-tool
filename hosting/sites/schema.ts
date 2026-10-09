import { sqliteTable, text } from 'drizzle-orm/sqlite-core';
export const snapshotVersions=sqliteTable('snapshot_versions',{
  sha:text('sha').primaryKey(),payload:text('payload').notNull(),capturedAt:text('captured_at').notNull(),importedAt:text('imported_at').notNull()
});
export const snapshotHead=sqliteTable('snapshot_head',{
  id:text('id').primaryKey(),sha:text('sha').notNull().references(()=>snapshotVersions.sha)
});
