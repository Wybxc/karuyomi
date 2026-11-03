import { build } from 'esbuild';
import { cp, mkdir, rm } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });
await build({
  entryPoints: ['src/host.ts', 'src/worker.ts'],
  outdir: 'dist',
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
});
await cp('public/host.html', 'dist/host.html');
