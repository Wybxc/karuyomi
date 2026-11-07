import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import { StateMutationSchema } from '@karuyomi/protocol';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { isAbsolute } from 'node:path';
import { createInterface } from 'node:readline';
import { getStreamAsBuffer } from 'get-stream';
import { z } from 'zod';
import {
  loadStaticIndex,
  MANIFEST_METADATA_LIMIT,
  registrationSql,
  verifyMetadata,
  verifyStaticAuthority,
  type MetadataLoader,
} from '../../../tools/extensions/registration.ts';
import { parseManifest } from '../../../tools/extensions/verify-manifest.ts';
import { fileURLToPath, URL } from 'node:url';
import { createTestHarness, type TestHarnessOptions } from 'wrangler';
import type { AcceptanceBindings } from './acceptance-entry.ts';
import {
  ackAttempts,
  ackLossLabel,
  isAckLossFixture,
  prepareAckLoss,
} from './acceptance-ack.ts';

const keys = await generateKeyPair('RS256', { extractable: true });
const publicKey = await exportJWK(keys.publicKey);
publicKey.kid = 'acceptance';
const configPath = fileURLToPath(
  new URL('./dist/karuyomi/wrangler.json', import.meta.url),
);
const nextConfigPath = process.env.ACCEPTANCE_NEXT_CONFIG;
if (nextConfigPath !== undefined && !isAbsolute(nextConfigPath)) {
  throw new Error('ACCEPTANCE_NEXT_CONFIG must be an absolute path');
}
const vars = {
  PROBE_ACCESS_JWKS: JSON.stringify({ keys: [publicKey] }),
  ACCESS_TEAM_DOMAIN: 'acceptance.cloudflareaccess.com',
  ACCESS_AUD: 'acceptance',
  ACCESS_SUBJECT: 'acceptance-owner',
  OWNER_EMAIL: 'acceptance@example.com',
};
const privateKey = await exportPKCS8(keys.privateKey);
const fixture = process.env.ACCEPTANCE_FIXTURE ?? '';
if (nextConfigPath && fixture !== '') {
  throw new Error(
    'Snapshot switching cannot be combined with another acceptance fixture',
  );
}
const ackLoss = isAckLossFixture(fixture) ? fixture : undefined;
const sourcePolicies = process.env.ACCEPTANCE_SOURCE_POLICIES;
const options = (
  publicOrigin: string,
  workerConfig = configPath,
): TestHarnessOptions => ({
  workers: [
    {
      configPath: workerConfig,
      vars: {
        ...vars,
        APP_ORIGIN: publicOrigin,
        ...(ackLoss ? { ACCEPTANCE_ACK_LOSS: ackLoss } : {}),
      },
      secrets: { ACCEPTANCE_PRIVATE_KEY: privateKey },
    },
  ],
});
const server = createTestHarness(options(''));
let stopRequested = false;
let requestStop: () => void = () => {};
const stopped = new Promise<void>((resolve) => {
  requestStop = () => {
    stopRequested = true;
    resolve();
  };
});
process.once('SIGINT', requestStop);
process.once('SIGTERM', requestStop);
process.stdin.once('end', requestStop);
const commands = nextConfigPath
  ? createInterface({ input: process.stdin })
  : undefined;
if (commands) {
  commands.on('line', (line) => {
    if (line === 'stop') requestStop();
  });
} else {
  process.stdin.once('data', requestStop);
  process.stdin.resume();
}

let ackAuditDb: D1Database | undefined;
try {
  if (fixture !== '' && fixture !== 'categories' && !ackLoss) {
    throw new Error(
      'ACCEPTANCE_FIXTURE must be categories, settings-ack-loss, progress-ack-loss or empty',
    );
  }
  const { url } = await server.listen();
  if (
    url.hostname !== '127.0.0.1' ||
    !['http:', 'https:'].includes(url.protocol)
  ) {
    throw new Error('Acceptance requires the official loopback listener');
  }
  await server.update(options(url.origin));
  const current = await server.listen();
  if (current.url.origin !== url.origin) {
    throw new Error('Acceptance listener changed while configuring its origin');
  }
  const worker = server.getWorker<AcceptanceBindings>();
  await worker.applyD1Migrations('DB');
  if (!stopRequested && ackLoss) {
    const db = (await worker.getEnv()).DB;
    await prepareAckLoss(db);
    ackAuditDb = db;
  }
  if (!stopRequested && sourcePolicies) {
    await initializeSourcePolicies(url.origin, sourcePolicies);
  }
  if (!stopRequested && fixture === 'categories') {
    await initializeCategoryFixture(url.origin);
  }
  if (!stopRequested) {
    console.log(`ACCEPTANCE_URL=${url.href}`);
    console.log(`ACCEPTANCE_SUBJECT=${vars.ACCESS_SUBJECT}`);
    if (commands && nextConfigPath) {
      const requested = new Promise<void>((resolve) => {
        commands.on('line', (line) => {
          if (line === 'switch') resolve();
        });
      });
      console.log('ACCEPTANCE_SWITCH=ready');
      console.log(
        'Type switch to activate the next snapshot, or stop to close the server.',
      );
      await Promise.race([requested, stopped]);
      if (!stopRequested) {
        await server.update(options(url.origin, nextConfigPath));
        const switched = await server.listen();
        if (switched.url.origin !== url.origin) {
          throw new Error(
            'Acceptance listener changed while switching snapshots',
          );
        }
        const { DB: db } = await server
          .getWorker<AcceptanceBindings>()
          .getEnv();
        const migrated = await db
          .prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'reader_settings'",
          )
          .first();
        if (!migrated) {
          throw new Error(
            'Acceptance snapshot switch did not preserve the migrated D1',
          );
        }
        if (!stopRequested && sourcePolicies) {
          await initializeSourcePolicies(url.origin, sourcePolicies);
        }
        if (!stopRequested) console.log('ACCEPTANCE_SWITCH=switched');
      }
    } else {
      console.log(
        'Use independent clients at this URL. Press Enter or Ctrl-C to stop.',
      );
    }
    await stopped;
  }
} finally {
  commands?.close();
  process.stdin.pause();
  process.stdin.removeListener('data', requestStop);
  process.stdin.removeListener('end', requestStop);
  process.removeListener('SIGINT', requestStop);
  process.removeListener('SIGTERM', requestStop);
  try {
    if (ackLoss && ackAuditDb) {
      console.log(
        ackLossLabel(ackLoss) +
          '_AUDIT=' +
          JSON.stringify(await ackAttempts(ackAuditDb, ackLoss)),
      );
    }
  } finally {
    await server.close();
  }
}

async function initializeCategoryFixture(origin: string): Promise<void> {
  const packageName = 'eu.kanade.test';
  const sourceId = '123';
  for (const suffix of ['甲', '乙']) {
    if (stopRequested) return;
    const mangaUrl = `/category-native/${suffix}`;
    const title = `分类同步·${suffix}`;
    const mangaKey = createHash('sha256')
      .update(JSON.stringify([packageName, sourceId, mangaUrl]))
      .digest('hex');
    const mutation = create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision: 0,
      operation: {
        case: 'setFavorite',
        value: {
          favorite: true,
          metadata: {
            packageName,
            sourceId,
            sourceName: '分类同步夹具',
            sourceLang: 'zh',
            manga: { url: mangaUrl, title },
          },
        },
      },
    });
    const response = await fetch(new URL('/api/state/mutations', origin), {
      method: 'POST',
      headers: {
        Origin: origin,
        'X-App-Subject': vars.ACCESS_SUBJECT,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: toJsonString(StateMutationSchema, mutation),
      redirect: 'error',
      signal: AbortSignal.timeout(15_000),
    });
    const result = stateMutationResponseSchema.parse(await response.json());
    if (
      response.status !== 200 ||
      result.error !== undefined ||
      result.mutationId !== mutation.mutationId ||
      result.manga?.mangaKey !== mangaKey ||
      result.manga.revision !== 1 ||
      !result.manga.favorite ||
      result.manga.metadata?.manga?.title !== title ||
      result.manga.metadata.manga.url !== mangaUrl
    ) {
      throw new Error(`Category fixture was not confirmed for ${title}`);
    }
  }
}

/** Local Source acceptance still uses current static metadata and explicit hosts. */
async function initializeSourcePolicies(
  origin: string,
  input: string,
): Promise<void> {
  if (Buffer.byteLength(input, 'utf8') > 32 * 1024)
    throw new Error('Oversized acceptance Source policies');
  const policies = z
    .array(
      z
        .object({
          packageName: z.string().min(1).max(200),
          allowedHosts: z.array(z.string().min(1).max(253)).min(1).max(32),
        })
        .strict(),
    )
    .min(1)
    .max(16)
    .parse(JSON.parse(input));
  if (
    new Set(policies.map((value) => value.packageName)).size !== policies.length
  ) {
    throw new Error('Duplicate acceptance Source package policy');
  }
  const load: MetadataLoader = async (pathname, maximum) => {
    const response = await server.fetch(new URL(pathname, origin).href, {
      redirect: 'manual',
    });
    if (response.status !== 200 || !response.body) {
      throw new Error(`Acceptance static metadata HTTP ${response.status}`);
    }
    return getStreamAsBuffer(response.body, { maxBuffer: maximum });
  };
  const index = await loadStaticIndex(load);
  const bindings = await server.getWorker<AcceptanceBindings>().getEnv();
  for (const policy of policies) {
    if (stopRequested) return;
    const entry = index.builds.find(
      (value) => value.packageName === policy.packageName,
    );
    if (!entry)
      throw new Error(
        'Acceptance Source is absent from the current static index',
      );
    const manifest = await verifyMetadata(
      await parseManifest(
        await load(entry.manifestPath, MANIFEST_METADATA_LIMIT),
      ),
    );
    await verifyStaticAuthority(manifest, load);
    await bindings.DB.exec(
      registrationSql(manifest, policy.allowedHosts, {
        catalogUrl: origin + '/extensions/index.json',
        repoId: manifest.repoId,
      }),
    );
  }
  console.log(`ACCEPTANCE_SOURCE_POLICY_COUNT=${policies.length}`);
}
