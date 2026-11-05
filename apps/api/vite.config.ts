import { cloudflare } from '@cloudflare/vite-plugin';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

export default defineConfig(({ mode }) => ({
  publicDir:
    mode === 'probe'
      ? false
      : fileURLToPath(new URL('../../dist/public', import.meta.url)),
  plugins: [
    cloudflare({
      configPath: fileURLToPath(new URL('./wrangler.jsonc', import.meta.url)),
      remoteBindings: false,
      ...(mode === 'probe'
        ? {
            config: {
              main: fileURLToPath(
                new URL('./test/workerd-entry.ts', import.meta.url),
              ),
            },
          }
        : {}),
    }),
  ],
  build: { target: 'es2022', sourcemap: true, emptyOutDir: true },
}));
