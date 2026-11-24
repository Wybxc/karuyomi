import type { AccessConfig, AccessIdentity } from './access.js';
import type { SourceDnsEgress } from './source-dns-egress.js';

export type Bindings = AccessConfig & {
  ASSETS: Fetcher;
  DB: D1Database;
  COVERS: R2Bucket;
  RUNTIME_SESSIONS: DurableObjectNamespace;
  SOURCE_DNS_EGRESS?: DurableObjectNamespace<SourceDnsEgress>;
};

export type AppEnv = {
  Bindings: Bindings;
  Variables: { identity: AccessIdentity };
};
