import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-plugin';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      main: fileURLToPath(new URL('./test/workerd-entry.ts', import.meta.url)),
      wrangler: {
        configPath: fileURLToPath(new URL('./wrangler.jsonc', import.meta.url)),
      },
      remoteBindings: false,
      miniflare: {
        bindings: {
          ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
          ACCESS_AUD: 'state-fixture',
          ACCESS_SUBJECT: '',
          OWNER_EMAIL: 'owner@example.com',
          APP_ORIGIN: 'https://read.example.com',
          PROBE_ACCESS_JWKS: '{"keys":[]}',
          TEST_MIGRATIONS: await readD1Migrations(
            fileURLToPath(new URL('./migrations', import.meta.url)),
          ),
        },
      },
    })),
  ],
  test: {
    name: 'workers',
    include: ['test/state-workerd.test.ts', 'test/*-worker.test.ts'],
  },
});
