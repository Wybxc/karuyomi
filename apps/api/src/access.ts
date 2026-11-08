import {
  createRemoteJWKSet,
  errors,
  jwtVerify,
  type JWTVerifyGetKey,
  type JWTPayload,
} from 'jose';

export interface AccessConfig {
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  APP_ORIGIN: string;
}

export interface AccessIdentity {
  subject: string;
  email: string;
  expiresAt: number;
}

export type VerifyAccess = (
  token: string,
  config: AccessConfig,
) => Promise<AccessIdentity>;

// Retain a bounded JWK cache across warm requests, including key rotation support.
const keySets = new Map<string, JWTVerifyGetKey>();

export class AccessError extends Error {
  constructor(
    public readonly code: 'access_required' | 'access_unavailable',
    public readonly status: 401 | 503,
  ) {
    super(code);
  }
}

export function accessIssuer(config: AccessConfig): string {
  if (
    !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(config.ACCESS_TEAM_DOMAIN) ||
    !config.ACCESS_AUD
  ) {
    throw new Error('Access is not configured');
  }
  const origin = new URL(config.APP_ORIGIN);
  if (
    origin.origin !== config.APP_ORIGIN ||
    (origin.protocol !== 'https:' &&
      !(
        origin.protocol === 'http:' &&
        ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname)
      ))
  )
    throw new Error('Invalid application origin');
  return `https://${config.ACCESS_TEAM_DOMAIN}`;
}

function accessIdentity(payload: JWTPayload): AccessIdentity {
  if (
    !payload.sub ||
    typeof payload.email !== 'string' ||
    typeof payload.exp !== 'number' ||
    !Number.isSafeInteger(payload.exp) ||
    payload.exp <= Date.now() / 1000
  ) {
    throw new AccessError('access_required', 401);
  }
  return { subject: payload.sub, email: payload.email, expiresAt: payload.exp };
}

export function createAccessVerifier(getKey?: JWTVerifyGetKey): VerifyAccess {
  return async (token, config) => {
    const issuer = accessIssuer(config);
    let keys = getKey ?? keySets.get(issuer);
    if (!keys) {
      keys = createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
      if (keySets.size >= 4) keySets.clear();
      keySets.set(issuer, keys);
    }
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer,
        audience: config.ACCESS_AUD,
        algorithms: ['RS256'],
        requiredClaims: ['sub', 'exp', 'iat', 'email'],
      });
      return accessIdentity(payload);
    } catch (error) {
      if (error instanceof AccessError) throw error;
      if (
        error instanceof errors.JWKSTimeout ||
        error instanceof TypeError ||
        (error instanceof errors.JOSEError && error.code === 'ERR_JOSE_GENERIC')
      ) {
        throw new AccessError('access_unavailable', 503);
      }
      // A JWK fetch may fail with a non-JOSE error; fail closed, but permit retry.
      if (!(error instanceof errors.JOSEError))
        throw new AccessError('access_unavailable', 503);
      throw new AccessError('access_required', 401);
    }
  };
}
