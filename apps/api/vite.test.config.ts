import { cloudflare } from '@cloudflare/vite-plugin';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

export default defineConfig({
  builder: { sharedConfigBuild: true },
  root: fileURLToPath(new URL('./test/fixture', import.meta.url)),
  publicDir: fileURLToPath(new URL('./test/fixture/public', import.meta.url)),
  plugins: [
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
