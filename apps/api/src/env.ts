import type { AccessConfig, AccessIdentity } from './access.js';

export type Bindings = AccessConfig & {
  ASSETS: Fetcher;
  DB: D1Database;
  RUNTIME_SESSIONS: DurableObjectNamespace;
};

export type AppEnv = {
  Bindings: Bindings;
  Variables: { identity: AccessIdentity };
};
