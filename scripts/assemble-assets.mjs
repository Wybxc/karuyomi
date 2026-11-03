import { cp, mkdir, rm } from 'node:fs/promises';

const publicDir = new URL('../dist/public/', import.meta.url);
await rm(publicDir, { recursive: true, force: true });
await mkdir(publicDir, { recursive: true });
await cp(new URL('../apps/reader/build/web/', import.meta.url), publicDir, {
  recursive: true,
});
await cp(
  new URL('../packages/runtime-host/dist/', import.meta.url),
  new URL('runtime/', publicDir),
  { recursive: true },
);
