import { cloudflare } from '@cloudflare/vite-plugin';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

// Separate output and Wrangler redirection from production and unit fixtures.
export default defineConfig({
  builder: { sharedConfigBuild: true },
  root: fileURLToPath(new URL('./test', import.meta.url)),
  publicDir: fileURLToPath(new URL('../../dist/public', import.meta.url)),
  plugins: [
    cloudflare({
      configPath: fileURLToPath(new URL('./wrangler.jsonc', import.meta.url)),
      remoteBindings: false,
      config: {
        main: fileURLToPath(
          new URL('./test/acceptance-entry.ts', import.meta.url),
        ),
      },
    }),
  ],
  build: { target: 'es2022', emptyOutDir: true },
});
