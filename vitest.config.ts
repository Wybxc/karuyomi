import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: [
      'apps/api/test/**/*.test.ts',
      'packages/*/test/**/*.test.ts',
      'runtime/image-codec/test/**/*.test.ts',
    ],
    environment: 'node',
  },
});
