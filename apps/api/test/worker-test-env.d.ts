import type { D1Migration } from '@cloudflare/vitest-plugin';

declare global {
  namespace Cloudflare {
    interface Env {
      PROBE_ACCESS_JWKS: string;
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
