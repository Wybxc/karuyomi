import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { fileURLToPath, URL } from 'node:url';
import { createTestHarness, type TestHarnessOptions } from 'wrangler';
import type { AcceptanceBindings } from './acceptance-entry.ts';

const keys = await generateKeyPair('RS256', { extractable: true });
const publicKey = await exportJWK(keys.publicKey);
publicKey.kid = 'acceptance';
const configPath = fileURLToPath(
  new URL('./dist/karuyomi/wrangler.json', import.meta.url),
);
const vars = {
  PROBE_ACCESS_JWKS: JSON.stringify({ keys: [publicKey] }),
  ACCESS_TEAM_DOMAIN: 'acceptance.cloudflareaccess.com',
  ACCESS_AUD: 'acceptance',
  ACCESS_SUBJECT: 'acceptance-owner',
  OWNER_EMAIL: 'acceptance@example.com',
};
const privateKey = await exportPKCS8(keys.privateKey);
const options = (publicOrigin: string): TestHarnessOptions => ({
  workers: [
    {
      configPath,
      vars: { ...vars, APP_ORIGIN: publicOrigin },
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
process.stdin.once('data', requestStop);
process.stdin.once('end', requestStop);
process.stdin.resume();

try {
  const { url } = await server.listen();
  if (url.hostname !== '127.0.0.1' || url.protocol !== 'http:') {
    throw new Error('Acceptance requires the official loopback listener');
  }
  await server.update(options(url.origin));
  const current = await server.listen();
  if (current.url.origin !== url.origin) {
    throw new Error('Acceptance listener changed while configuring its origin');
  }
  await server.getWorker<AcceptanceBindings>().applyD1Migrations('DB');
  if (!stopRequested) {
    console.log(`ACCEPTANCE_URL=${url.href}`);
    console.log(`ACCEPTANCE_SUBJECT=${vars.ACCESS_SUBJECT}`);
    console.log('Open two Codex browser tabs. Press Enter or Ctrl-C to stop.');
    await stopped;
  }
} finally {
  process.stdin.pause();
  process.stdin.removeListener('data', requestStop);
  process.stdin.removeListener('end', requestStop);
  process.removeListener('SIGINT', requestStop);
  process.removeListener('SIGTERM', requestStop);
  await server.close();
}
