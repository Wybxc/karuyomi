import { cloudflare } from '@cloudflare/vite-plugin';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import { karuyomiStaticAssets } from './vite.assets.ts';

export default defineConfig({
  builder: { sharedConfigBuild: true },
  publicDir: fileURLToPath(new URL('../../dist/public', import.meta.url)),
  plugins: [
    karuyomiStaticAssets(),
    cloudflare({
      configPath: fileURLToPath(new URL('./wrangler.jsonc', import.meta.url)),
      remoteBindings: false,
    }),
  ],
  build: { target: 'es2022', sourcemap: true, emptyOutDir: true },
});
