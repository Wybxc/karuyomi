import {
  createRemoteJWKSet,
  jwtVerify,
  type JWTVerifyGetKey,
  type JWTPayload,
} from 'jose';

export interface AccessConfig {
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  ACCESS_SUBJECT: string;
}

export interface AccessIdentity {
  subject: string;
  expiresAt: number;
}

export type VerifyAccess = (
  token: string,
  config: AccessConfig,
) => Promise<AccessIdentity>;

// Retain a bounded JWK cache across warm requests, including key rotation support.
const keySets = new Map<string, JWTVerifyGetKey>();

export function accessIssuer(config: AccessConfig): string {
  if (
    !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(config.ACCESS_TEAM_DOMAIN) ||
    !config.ACCESS_AUD ||
    !config.ACCESS_SUBJECT
  ) {
    throw new Error('Access is not configured');
  }
  return `https://${config.ACCESS_TEAM_DOMAIN}`;
}

export function accessIdentity(
  payload: JWTPayload,
  config: AccessConfig,
): AccessIdentity {
  if (
    payload.sub !== config.ACCESS_SUBJECT ||
    typeof payload.exp !== 'number' ||
    !Number.isSafeInteger(payload.exp) ||
    payload.exp <= Date.now() / 1000
  ) {
    throw new Error('Access identity rejected');
  }
  return { subject: payload.sub, expiresAt: payload.exp };
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
    const { payload } = await jwtVerify(token, keys, {
      issuer,
      audience: config.ACCESS_AUD,
      algorithms: ['RS256'],
      requiredClaims: ['sub', 'exp', 'iat'],
    });
    return accessIdentity(payload, config);
  };
}
