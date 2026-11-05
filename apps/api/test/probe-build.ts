import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, URL } from 'node:url';
import { createBuilder } from 'vite';
import { z } from 'zod';

/** Build the isolated JWT-verifying API fixture through the product's Cloudflare Vite configuration. */
export async function buildProbeApi(
  directory: string,
  assetsDirectory?: string,
): Promise<{ script: string; configPath: string }> {
  const output = path.join(directory, 'api-build');
  const builder = await createBuilder({
    root: directory,
    configFile: fileURLToPath(new URL('../vite.config.ts', import.meta.url)),
    mode: 'probe',
    publicDir: assetsDirectory ?? false,
    logLevel: 'error',
    build: {
      outDir: output,
      emptyOutDir: true,
      rolldownOptions: {
        output: { entryFileNames: 'index.js', codeSplitting: false },
      },
    },
  });
  await builder.buildApp();
  const workerOutput = path.join(output, 'karuyomi');
  const configPath = path.join(workerOutput, 'wrangler.json');
  const config = z
    .object({ main: z.string() })
    .parse(JSON.parse(await readFile(configPath, 'utf8')));
  return {
    script: await readFile(path.resolve(workerOutput, config.main), 'utf8'),
    configPath,
  };
}
