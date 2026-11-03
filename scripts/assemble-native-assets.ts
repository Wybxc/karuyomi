import { cp, mkdir } from 'node:fs/promises';

// Product packaging composes package outputs at the repository entry layer.
// The runtime-host package builds its own dist without writing into the app.
const source = new URL(
  '../packages/runtime-host/dist/native/',
  import.meta.url,
);
const destination = new URL('../apps/reader/assets/runtime/', import.meta.url);
await mkdir(destination, { recursive: true });
for (const name of ['host.js', 'worker.js', 'manifest.json']) {
  await cp(new URL(name, source), new URL(name, destination));
}
