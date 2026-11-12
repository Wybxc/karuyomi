import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { z } from 'zod';

export const nativeFlutterAssets = 'assets/assets/runtime/';
export const immutableCache = 'public, max-age=31536000, immutable';

/** Flutter's bill of materials is also the boundary of its cache policy. */
export const flutterWebManifestSchema = z
  .object({
    version: z.literal(1),
    entries: z
      .array(
        z.object({
          url: z
            .string()
            .min(1)
            .max(2048)
            .refine(
              (url) =>
                !/[\\?#\r\n]/.test(url) &&
                url
                  .split('/')
                  .every(
                    (segment) =>
                      segment !== '' && segment !== '.' && segment !== '..',
                  ),
              'Flutter assets require relative file paths',
            ),
          hash: z.string().regex(/^[a-f0-9]{8}$/),
          size: z.number().int().nonnegative(),
          urlHashed: z.boolean(),
        }),
      )
      .min(1)
      .max(10000),
  })
  .superRefine(({ entries }, context) => {
    if (new Set(entries.map((entry) => entry.url)).size !== entries.length) {
      context.addIssue({
        code: 'custom',
        message: 'Duplicate Flutter asset URL',
      });
    }
    if (
      !entries.some(
        (entry) => entry.url === 'flutter_bootstrap.js' && !entry.urlHashed,
      ) ||
      !entries.some(
        (entry) =>
          /^main\.dart\.[a-f0-9]{8}\.js$/.test(entry.url) && entry.urlHashed,
      )
    ) {
      context.addIssue({
        code: 'custom',
        message: 'Flutter content-hashed entrypoint and bootstrap are required',
      });
    }
  });

export type FlutterWebManifest = z.infer<typeof flutterWebManifestSchema>;

export async function readFlutterWebManifest(
  directory: string,
): Promise<FlutterWebManifest> {
  const manifest = flutterWebManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(directory, 'precache_manifest.json'), 'utf8'),
    ),
  );
  // Native-only pubspec payloads are excluded from the public deployment too.
  return {
    ...manifest,
    entries: manifest.entries.filter(
      (entry) => !entry.url.startsWith(nativeFlutterAssets),
    ),
  };
}

export function flutterCacheRules({ entries }: FlutterWebManifest): string[] {
  const policies = new Map<string, boolean>();
  const grouped = new Set<string>();
  // Keep the rules below Cloudflare's 100-rule limit without treating unhashed
  // renderer binaries as immutable or mixing overlapping Cache-Control values.
  for (const prefix of ['assets/', 'canvaskit/', 'icons/']) {
    const group = entries.filter((entry) => entry.url.startsWith(prefix));
    const first = group[0];
    if (first && group.every((entry) => entry.urlHashed === first.urlHashed)) {
      policies.set('/' + prefix + '*', first.urlHashed);
      for (const entry of group) grouped.add(entry.url);
    }
  }
  for (const entry of entries) {
    if (!grouped.has(entry.url))
      policies.set(
        entry.url === 'index.html' ? '/' : '/' + entry.url,
        entry.urlHashed,
      );
  }
  policies.set('/precache_manifest.json', false);
  return [...policies].map(
    ([url, immutable]) =>
      `${url}\n  Cache-Control: ${immutable ? immutableCache : 'no-cache'}`,
  );
}
