import { preview } from '@vitest/browser-preview';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Preview calls Vite's opener even when server.open is false. Keep this
// official provider available for manual use in the Codex in-app browser.
process.env.BROWSER = 'none';

export default defineConfig({
  root: fileURLToPath(new URL('./', import.meta.url)),
  publicDir: false,
  server: { host: '127.0.0.1', open: false },
  worker: { format: 'es' },
  test: {
    name: 'browser',
    include: ['test/browser/**/*.browser.test.ts'],
    open: false,
    testTimeout: 15000,
    browser: {
      enabled: true,
      connectTimeout: 300000,
      provider: preview(),
      instances: [{ browser: 'chromium' }],
      headless: false,
      api: { host: '127.0.0.1' },
    },
  },
});
