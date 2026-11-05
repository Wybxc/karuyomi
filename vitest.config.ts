import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: 'node',
          include: [
            'apps/api/test/**/*.test.ts',
            'packages/*/test/**/*.test.ts',
          ],
          exclude: [
            'apps/api/test/state-workerd.test.ts',
            'apps/api/test/*-worker.test.ts',
            '**/*.browser.test.ts',
          ],
          environment: 'node',
        },
      },
      'apps/api/vitest.config.ts',
    ],
  },
});
