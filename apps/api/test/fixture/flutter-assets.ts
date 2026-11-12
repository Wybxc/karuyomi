import { createHash } from 'node:crypto';
import { flutterWebManifestSchema } from '../../../../tools/flutter/web-assets.ts';

const shortHash = (bytes: string) =>
  createHash('sha256').update(bytes).digest('hex').slice(0, 8);
const main = 'fixture application';
const asset = 'fixture asset';
const pluginHtml = '<html>fixture plugin</html>';
export const flutterFixtureFiles = new Map([
  ['flutter_bootstrap.js', 'fixture bootstrap'],
  [`main.dart.${shortHash(main)}.js`, main],
  [`assets/notice.${shortHash(asset)}`, asset],
  [`assets/packages/webview/page.${shortHash(pluginHtml)}.html`, pluginHtml],
  ['canvaskit/canvaskit.wasm', 'fixture renderer'],
]);
export const flutterFixtureManifest = flutterWebManifestSchema.parse({
  version: 1,
  entries: [...flutterFixtureFiles].map(([url, bytes]) => ({
    url,
    size: Buffer.byteLength(bytes),
    hash: shortHash(bytes),
    urlHashed: url.includes(shortHash(bytes)),
  })),
});
