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
            'runtime/image-codec/test/**/*.test.ts',
          ],
          exclude: ['apps/api/test/state-workerd.test.ts'],
          environment: 'node',
        },
      },
      'apps/api/vitest.config.ts',
    ],
  },
});
