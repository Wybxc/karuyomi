// Only the official binding methods used by the maintenance command cross this boundary.
export type CoverCleanupBindings = {
  DB: {
    prepare(query: string): {
      bind(...values: unknown[]): { first(): Promise<unknown> };
      first(): Promise<unknown>;
    };
  };
  COVERS: {
    list(options: { prefix: string; limit: number; cursor?: string }): Promise<{
      objects: { key: string; uploaded: Date }[];
      truncated: boolean;
      cursor?: string;
    }>;
    delete(key: string): Promise<void>;
  };
};
export const COVER_ORPHAN_GRACE_MS = 60 * 60 * 1000;

export async function cleanupCoverOrphans(
  db: CoverCleanupBindings['DB'],
  bucket: CoverCleanupBindings['COVERS'],
  options: { now?: Date; graceMs?: number; cursor?: string } = {},
) {
  const graceMs = options.graceMs ?? COVER_ORPHAN_GRACE_MS;
  if (!Number.isFinite(graceMs) || graceMs < COVER_ORPHAN_GRACE_MS)
    throw new Error('Cover orphan grace must be at least one hour');
  const cutoff = (options.now ?? new Date()).getTime() - graceMs;
  if (!Number.isFinite(cutoff)) throw new Error('Invalid cleanup clock');
  // Fail visibly if migrations are missing, even when the bucket is empty.
  await db.prepare('SELECT 1 FROM cover_assets LIMIT 1').first();
  const page = await bucket.list({
    prefix: 'covers/',
    limit: 100,
    ...(options.cursor ? { cursor: options.cursor } : {}),
  });
  let deleted = 0;
  for (const object of page.objects) {
    if (object.uploaded.getTime() >= cutoff) continue;
    const current = await db
      .prepare('SELECT 1 FROM cover_assets WHERE object_key = ?')
      .bind(object.key)
      .first();
    if (current) continue;
    await bucket.delete(object.key);
    deleted += 1;
  }
  return {
    scanned: page.objects.length,
    deleted,
    truncated: page.truncated,
    ...(page.truncated ? { cursor: page.cursor } : {}),
  };
}
