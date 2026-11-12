import { cloudflare } from '@cloudflare/vite-plugin';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { defineConfig } from 'vite';
import { flutterCacheRules } from '../../tools/flutter/web-assets.ts';
import {
  flutterFixtureFiles,
  flutterFixtureManifest,
} from './test/fixture/flutter-assets.ts';

export default defineConfig({
  builder: { sharedConfigBuild: true },
  root: fileURLToPath(new URL('./test/fixture', import.meta.url)),
  publicDir: fileURLToPath(new URL('./test/fixture/public', import.meta.url)),
  plugins: [
    {
      name: 'fixture-flutter-assets',
      apply: 'build',
      applyToEnvironment: (environment) => environment.name === 'client',
      async generateBundle() {
        for (const [fileName, source] of flutterFixtureFiles)
          this.emitFile({ type: 'asset', fileName, source });
        const original = await readFile(
          new URL('./test/fixture/public/_headers', import.meta.url),
          'utf8',
        );
        this.emitFile({
          type: 'asset',
          fileName: '_headers',
          source:
            original +
            '\n' +
            flutterCacheRules(flutterFixtureManifest).join('\n\n') +
            '\n',
        });
      },
    },
    cloudflare({
      configPath: fileURLToPath(new URL('./wrangler.jsonc', import.meta.url)),
      remoteBindings: false,
      config: {
        main: fileURLToPath(
          new URL('./test/workerd-entry.ts', import.meta.url),
        ),
      },
    }),
  ],
  build: { target: 'es2022', emptyOutDir: true },
});
