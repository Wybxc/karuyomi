/** Real browser/Worker acceptance. The browser operator uses the Codex in-app browser. */
import assert from 'node:assert/strict';
import { createCipheriv, createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer, type IncomingMessage } from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { build, transformWithOxc } from 'vite';
import sharp from 'sharp';
import sirv from 'sirv';
import writeFileAtomic from 'write-file-atomic';
import { z } from 'zod';
import {
  collectMaterials,
  type ImageCodecMaterialInput,
} from '../../packages/runtime-host/materials.ts';
import {
  decodeImage,
  type ImageHeader,
} from '../../runtime/image-codec/decoder.ts';
import {
  loadPngEncoder,
  type PngEncoder,
} from '../../runtime/image-codec/encoder.ts';
import {
  imageCodecBuildIdentity,
  imageCodecBuildManifestSchema,
} from './build.ts';
import { fixtures } from './verify-runtime.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const sha256 = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');
interface TileReference {
  index: number;
  x: 0;
  y: number;
  width: number;
  height: number;
  sourceRect: { x: 0; y: number; width: number; height: number };
  byteLength: number;
  sha256: string;
}
interface BrowserFixture {
  name: string;
  format: 'png' | 'jpeg';
  path: string;
  encodedBytes: number;
  encodedSha256: string;
  header: ImageHeader;
  tiles: TileReference[];
}
export interface ImageCodecWorkerBrowserOptions {
  buildDirectory?: string;
  outputDirectory?: string;
  signal?: AbortSignal;
}

async function verifiedBuild(
  directory: string,
): Promise<ImageCodecMaterialInput> {
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(directory, 'build-manifest.json'), 'utf8'),
    ),
  );
  assert.equal(manifest.identity, imageCodecBuildIdentity(manifest.inputs));
  for (const [name, artifact] of Object.entries(manifest.artifacts)) {
    assert.equal(
      path.basename(name),
      name.startsWith('licenses/') ? name.slice(9) : name,
    );
    const bytes = await readFile(path.join(directory, name));
    assert.equal(bytes.length, artifact.size, name + ' length');
    assert.equal(sha256(bytes), artifact.sha256, name + ' SHA-256');
  }
  return { directory, manifest };
}

/** This oracle buffers one RGBA strip, never a complete decoded raster. */
async function tileReferences(
  bytes: Uint8Array,
  format: 'png' | 'jpeg',
  codecUrl: URL,
  encoder: PngEncoder,
  signal?: AbortSignal,
): Promise<{ header: ImageHeader; tiles: TileReference[] }> {
  const session = decodeImage({
    bytes,
    format,
    codecUrl,
    ...(signal ? { signal } : {}),
  });
  const tiles: TileReference[] = [];
  let header: ImageHeader | undefined;
  let strip:
    | { start: number; rows: number; bytes: Uint8Array; received: number }
    | undefined;
  try {
    for await (const event of session) {
      signal?.throwIfAborted();
      if (event.kind === 'header') {
        const { kind: _kind, ...value } = event;
        header = value;
      } else if (event.kind === 'chunk') {
        assert(header);
        if (!strip) {
          assert.equal(event.offset, event.stripStart * header.rowBytes);
          strip = {
            start: event.stripStart,
            rows: event.stripRows,
            bytes: new Uint8Array(header.rowBytes * event.stripRows),
            received: 0,
          };
        }
        assert.equal(event.stripStart, strip.start);
        assert.equal(event.stripRows, strip.rows);
        assert.equal(
          event.offset,
          strip.start * header.rowBytes + strip.received,
        );
        assert(strip.bytes.length <= 4 * 1024 * 1024);
        strip.bytes.set(event.bytes, strip.received);
        strip.received += event.bytes.length;
        if (strip.received === strip.bytes.length) {
          const lease = encoder.acquire();
          try {
            const png = lease.encode(strip.bytes, header.width, strip.rows);
            tiles.push({
              index: tiles.length,
              x: 0,
              y: strip.start,
              width: header.width,
              height: strip.rows,
              sourceRect: {
                x: 0,
                y: strip.start,
                width: header.sourceWidth,
                height: strip.rows,
              },
              byteLength: png.length,
              sha256: sha256(png),
            });
          } finally {
            const cleanup = lease.close();
            assert.equal(
              cleanup.succeeded,
              true,
              cleanup.error ?? 'PNG encoder close',
            );
            assert.equal(cleanup.liveBytes, 0);
            assert.equal(cleanup.allocations, 0);
          }
          strip = undefined;
        }
      }
    }
    const terminal = await session.completion;
    assert.equal(terminal.status, 'complete', JSON.stringify(terminal));
    assert.equal(terminal.closeSucceeded, true);
    assert.equal(terminal.liveBytes, 0);
    assert.equal(terminal.allocations, 0);
    assert.equal(strip, undefined);
    assert(header);
    assert.equal(tiles.length, Math.ceil(header.height / 256));
    return { header, tiles };
  } finally {
    await session.cancel();
  }
}

async function entropyFixture(): Promise<Uint8Array<ArrayBuffer>> {
  const width = 4096,
    height = 256;
  const key = createHash('sha256')
    .update('karuyomi-png-tile-reference-v1')
    .digest();
  const generator = createCipheriv('aes-256-ctr', key, Buffer.alloc(16));
  const rgba = generator.update(Buffer.alloc(width * height * 4));
  assert.equal(generator.final().length, 0);
  return new Uint8Array(
    await sharp(rgba, { raw: { width, height, channels: 4 } })
      .png({ palette: false, progressive: false, compressionLevel: 6 })
      .toBuffer(),
  );
}

export async function prepareImageCodecWorkerBrowser(
  options: ImageCodecWorkerBrowserOptions = {},
) {
  const directory = path.resolve(
    options.outputDirectory ??
      path.join(
        ROOT,
        '.local/image-codec-worker',
        new Date().toISOString().replaceAll(':', '-'),
      ),
  );
  const relative = path.relative(ROOT, directory);
  if (
    relative.startsWith('..') ||
    path.isAbsolute(relative) ||
    !relative.split(path.sep).includes('.local')
  )
    throw new Error(
      'Browser verification output must be inside a repository .local directory',
    );
  const publicDirectory = path.join(directory, 'public');
  await mkdir(path.join(publicDirectory, 'runtime/materials'), {
    recursive: true,
  });
  await mkdir(path.join(publicDirectory, 'fixtures'), { recursive: true });
  await mkdir(path.join(directory, 'oracle'), { recursive: true });
  const imageCodecArtifacts = options.buildDirectory
    ? await verifiedBuild(path.resolve(options.buildDirectory))
    : undefined;
  const materials = await collectMaterials({
    includeImageCodecs: true,
    ...(imageCodecArtifacts ? { imageCodecArtifacts } : {}),
    ...(options.signal ? { signal: options.signal } : {}),
  });
  const contentTypes = new Map<string, string>();
  for (const [hash, artifact] of materials.data) {
    await writeFile(
      path.join(publicDirectory, 'runtime/materials', hash),
      artifact.bytes,
    );
    contentTypes.set('/runtime/materials/' + hash, artifact.contentType);
  }
  // Node's independent module instances consume the same final material bytes.
  for (const name of [
    'png.mjs',
    'png.wasm',
    'jpeg.mjs',
    'jpeg.wasm',
    'encoder.mjs',
    'encoder.wasm',
  ]) {
    const material = materials.catalog.imageCodecs.find(
      (item) => item.logicalName === name,
    );
    assert(material, name);
    const artifact = materials.data.get(material.sha256);
    assert(artifact, name);
    await writeFile(path.join(directory, 'oracle', name), artifact.bytes);
  }
  const generated = await fixtures(options.signal);
  const inputs = [
    { name: 'png', ...generated.png },
    { name: 'png-tall', ...generated.pngTall },
    { name: 'jpeg', ...generated.jpeg },
    { name: 'jpeg-tall', ...generated.jpegTall },
    {
      name: 'png-entropy',
      format: 'png' as const,
      bytes: await entropyFixture(),
    },
  ];
  const encoder = await loadPngEncoder(
    pathToFileURL(path.join(directory, 'oracle/encoder.mjs')),
  );
  const cases: BrowserFixture[] = [];
  for (const input of inputs) {
    options.signal?.throwIfAborted();
    assert(input.bytes.length <= 8 * 1024 * 1024);
    const filename = input.name + '.' + input.format;
    await writeFile(
      path.join(publicDirectory, 'fixtures', filename),
      input.bytes,
    );
    const expected = await tileReferences(
      input.bytes,
      input.format,
      pathToFileURL(path.join(directory, 'oracle', input.format + '.mjs')),
      encoder,
      options.signal,
    );
    if (input.name === 'png-entropy')
      assert(expected.tiles.some((tile) => tile.byteLength > 65536));
    else
      assert(expected.header.width * expected.header.height > 16 * 1024 * 1024);
    cases.push({
      name: input.name,
      format: input.format,
      path: '/fixtures/' + filename,
      encodedBytes: input.bytes.length,
      encodedSha256: sha256(input.bytes),
      ...expected,
    });
  }
  const config = {
    schemaVersion: 1,
    runId: randomUUID(),
    materialVersion: materials.catalog.materialVersion,
    codecSource: materials.catalog.sources.imageCodecs,
    imageCodecs: materials.catalog.imageCodecs,
    cases,
    scope: {
      input:
        'Synthetic RGBA8 PNG and sequential baseline JPEG; not Source image processing',
      oracle:
        'Per-tile PNG SHA and geometry from the same fixed decoder/encoder in independent Node WASM instances; independent Sharp pixel correctness is the separate 24-case gate',
      display:
        'Three HTML image previews; no Canvas alpha round-trip pixel oracle',
      memory:
        'C allocation ledgers and logical Worker/module release calls; no RSS, GPU, physical heap reclamation, Reader, Flutter, Native or device performance claim',
    },
  };
  await writeFile(
    path.join(publicDirectory, 'config.json'),
    JSON.stringify(config),
  );
  await writeFile(
    path.join(publicDirectory, 'materials.json'),
    JSON.stringify(materials.catalog),
  );
  // Evaluation tooling supplies its transport verifier; the candidate client has no Source dependency.
  await build({
    configFile: false,
    root: ROOT,
    publicDir: false,
    logLevel: 'silent',
    build: {
      outDir: publicDirectory,
      emptyOutDir: false,
      copyPublicDir: false,
      target: 'es2022',
      minify: false,
      lib: {
        entry: path.join(ROOT, 'packages/runtime-host/src/verified-loader.ts'),
        formats: ['es'],
        fileName: () => 'verified-loader.js',
      },
      rolldownOptions: { output: { codeSplitting: false, comments: false } },
    },
  });
  // The inline browser program is intentionally JavaScript; Vite's transformer checks its syntax.
  const script = await transformWithOxc(
    BROWSER_SCRIPT,
    'image-codec-worker.browser.js',
    {
      target: 'es2022',
    },
  );
  await writeFile(path.join(publicDirectory, 'runner.js'), script.code);
  await writeFile(path.join(publicDirectory, 'index.html'), HTML);
  return { directory, publicDirectory, config, contentTypes };
}

async function body(request: IncomingMessage, limit: number): Promise<Buffer> {
  const parts: Buffer[] = [];
  let length = 0;
  for await (const item of request) {
    const chunk: unknown = item;
    if (!Buffer.isBuffer(chunk))
      throw new Error('Expected binary HTTP request body');
    length += chunk.length;
    if (length > limit)
      throw new Error('Verification request exceeds its size budget');
    parts.push(chunk);
  }
  return Buffer.concat(parts, length);
}

export async function serveImageCodecWorkerBrowser(
  prepared: Awaited<ReturnType<typeof prepareImageCodecWorkerBrowser>>,
  { port = 8953, signal }: { port?: number; signal?: AbortSignal } = {},
) {
  let closed = false;
  let reportPassed: boolean | undefined;
  const callbacks: { resolve?: () => void } = {};
  const completion = new Promise<void>((resolve) => {
    callbacks.resolve = resolve;
  });
  assert(callbacks.resolve);
  const resolveClosed = callbacks.resolve;
  const staticFiles = sirv(prepared.publicDirectory, {
    dev: true,
    setHeaders(response, pathname) {
      const contentType = prepared.contentTypes.get(pathname);
      if (contentType) response.setHeader('Content-Type', contentType);
      response.setHeader('Cache-Control', 'no-store');
    },
  });
  const stop = () => {
    if (closed) return;
    closed = true;
    clearTimeout(deadline);
    signal?.removeEventListener('abort', stop);
    server.close(() => resolveClosed());
    server.closeAllConnections();
  };
  const reportSchema = z
    .object({
      schemaVersion: z.literal(1),
      runId: z.literal(prepared.config.runId),
      passed: z.boolean(),
      cases: z.array(z.json()),
    })
    .passthrough();
  const server = createServer((request, response) => {
    void (async () => {
      const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
      if (request.method === 'POST' && pathname === '/report') {
        const report = reportSchema.parse(
          JSON.parse((await body(request, 8 * 1024 * 1024)).toString('utf8')),
        );
        await writeFileAtomic(
          path.join(prepared.directory, 'result.json'),
          JSON.stringify(report, null, 2) + '\n',
        );
        reportPassed = report.passed;
        console.log(
          JSON.stringify({
            reportFile: path.join(prepared.directory, 'result.json'),
            passed: report.passed,
          }),
        );
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end('{"saved":true}');
      } else if (
        request.method === 'POST' &&
        pathname.startsWith('/preview/')
      ) {
        const match = /^\/preview\/([a-z-]+)\/(first|middle|last)\.png$/.exec(
          pathname,
        );
        const name = match?.[1],
          slot = match?.[2];
        if (
          !name ||
          !slot ||
          !prepared.config.cases.some((item) => item.name === name)
        )
          throw new Error('Unknown preview');
        const png = await body(request, 8 * 1024 * 1024);
        const previewDirectory = path.join(
          prepared.publicDirectory,
          'previews',
          name,
        );
        await mkdir(previewDirectory, { recursive: true });
        await writeFile(path.join(previewDirectory, slot + '.png'), png);
        response.writeHead(200).end('saved');
      } else if (request.method === 'POST' && pathname === '/shutdown') {
        response.once('finish', stop);
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end('{"closed":true}');
      } else if (request.method === 'GET' || request.method === 'HEAD') {
        staticFiles(request, response, () => {
          response.writeHead(404).end('Not found');
        });
      } else response.writeHead(405).end('Method not allowed');
    })().catch((error: unknown) => {
      console.error(error);
      if (!response.headersSent)
        response.writeHead(400, { 'Content-Type': 'text/plain' });
      response.end(error instanceof Error ? error.message : String(error));
    });
  });
  // A forgotten manual acceptance server has a bounded lifetime as well as UI/signal shutdown.
  const deadline = setTimeout(stop, 30 * 60 * 1000);
  signal?.addEventListener('abort', stop, { once: true });
  try {
    signal?.throwIfAborted();
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', () => {
        server.off('error', reject);
        resolve();
      });
    });
    const address = server.address();
    assert(address && typeof address !== 'string');
    console.log(
      JSON.stringify({
        browserUrl: 'http://127.0.0.1:' + address.port,
        outputDirectory: prepared.directory,
        shutdown: 'POST /shutdown or the page’s 关闭服务 button',
      }),
    );
    await completion;
    return { reportPassed };
  } finally {
    stop();
  }
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const parsed = parseArgs({
    args,
    options: {
      build: { type: 'string' },
      output: { type: 'string' },
      port: { type: 'string' },
      'prepare-only': { type: 'boolean' },
    },
  });
  const controller = new AbortController();
  const stop = () => controller.abort();
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  try {
    const prepared = await prepareImageCodecWorkerBrowser({
      ...(parsed.values.build ? { buildDirectory: parsed.values.build } : {}),
      ...(parsed.values.output
        ? { outputDirectory: parsed.values.output }
        : {}),
      signal: controller.signal,
    });
    console.log(
      JSON.stringify({
        prepared: prepared.directory,
        runId: prepared.config.runId,
        fixtures: prepared.config.cases.map((item) => ({
          name: item.name,
          tiles: item.tiles.length,
        })),
      }),
    );
    if (!parsed.values['prepare-only']) {
      const port = Number(parsed.values.port ?? '8953');
      if (!Number.isInteger(port) || port < 0 || port > 65535)
        throw new Error('Invalid localhost port');
      const result = await serveImageCodecWorkerBrowser(prepared, {
        port,
        signal: controller.signal,
      });
      if (result.reportPassed === false) process.exitCode = 1;
    }
  } finally {
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
  }
}

const HTML = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Karuyomi codec Worker 验收</title><style>body{font:16px system-ui;margin:24px;color:#182537;background:#f4f7fb}button,select{font:inherit;padding:10px;margin:4px}pre{white-space:pre-wrap;max-height:38vh;overflow:auto;background:white;padding:16px}.previews{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}figure{margin:0;background:white;padding:10px}img{width:100%;image-rendering:auto}figcaption{overflow-wrap:anywhere}#status{font-weight:600}</style><h1>独立 codec Worker / PNG 条带验收</h1><p>合成长图与真实 WASM、材料完整性校验、逐片 PNG 摘要、pull/ACK 与取消；不代表 Source、Reader 或真机验收。</p><button id="run">运行验收</button><button id="close">关闭服务</button><span id="status">准备就绪</span><p><label>查看首/中/末条带 <select id="fixture"></select></label></p><div id="previews" class="previews"></div><pre id="log"></pre><script type="module" src="/runner.js"></script></html>`;

const BROWSER_SCRIPT = String.raw`
import { VerifiedLoader } from './verified-loader.js';
const $ = id => document.getElementById(id);
const check = (value, message) => { if (!value) throw new Error(message); };
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), n => n.toString(16).padStart(2, '0')).join('');
const config = await (await fetch('/config.json')).json();
const log = message => { $('log').textContent += message + '\n'; };
const activeSessions = new Set();
let clientUrl;
let running = false;
let closing = false;
let requestNumber = 0;
let activeWorkers = 0;
let maximumActiveWorkers = 0;
let imported;
let provider;
const previews = new Map();
function showPreviews(name) {
  $('previews').replaceChildren();
  for (const item of [...(previews.get(name) ?? [])].sort((a, b) => ['first', 'middle', 'last'].indexOf(a.slot) - ['first', 'middle', 'last'].indexOf(b.slot))) {
    const figure = document.createElement('figure');
    const image = document.createElement('img');
    image.src = item.url;
    image.alt = name + ' ' + item.slot + ' tile ' + item.index;
    const caption = document.createElement('figcaption');
    caption.textContent = name + ' / ' + item.slot + ' / y=' + item.y + ' / ' + item.sha256.slice(0, 16);
    figure.append(image, caption);
    $('previews').append(figure);
  }
}
$('fixture').onchange = () => showPreviews($('fixture').value);
async function rememberPreview(fixture, tile, sha256, slot) {
  const response = await fetch('/preview/' + fixture.name + '/' + slot + '.png', { method: 'POST', body: tile.png });
  check(response.ok, 'Preview persistence failed');
  const previous = previews.get(fixture.name) ?? [];
  const list = previous.filter(item => item.slot !== slot);
  list.push({ slot, index: tile.index, y: tile.y, sha256, url: '/previews/' + fixture.name + '/' + slot + '.png?run=' + config.runId });
  previews.set(fixture.name, list);
  if (previous.length === 0) {
    const option = document.createElement('option'); option.value = fixture.name; option.textContent = fixture.name;
    $('fixture').append(option);
  }
  $('fixture').value = fixture.name;
  showPreviews(fixture.name);
  await Promise.all(Array.from($('previews').querySelectorAll('img'), image => image.decode()));
}
async function initialize() {
  if (imported) return;
  const material = config.imageCodecs.find(item => item.logicalName === 'client.js');
  check(material, 'Missing catalog client.js');
  const response = await fetch(material.path, { credentials: 'omit' });
  check(response.ok, 'Client download failed');
  check(response.headers.get('content-type')?.split(';')[0] === material.contentType, 'Client content type');
  const bytes = await response.arrayBuffer();
  check(bytes.byteLength === material.size && await hash(bytes) === material.sha256, 'Client transfer integrity');
  clientUrl = URL.createObjectURL(new Blob([bytes], { type: material.contentType }));
  imported = await import(clientUrl);
  check(typeof imported.decodeImageTiles === 'function' && typeof imported.createImageCodecAssetProvider === 'function', 'Catalog client exports');
  provider = imported.createImageCodecAssetProvider(config.imageCodecs, new VerifiedLoader(location.origin));
}
async function inputBlob(fixture, truncate = 0) {
  const response = await fetch(fixture.path, { credentials: 'omit' });
  check(response.ok, 'Fixture fetch failed');
  const bytes = await response.arrayBuffer();
  check(bytes.byteLength === fixture.encodedBytes && await hash(bytes) === fixture.encodedSha256, 'Fixture integrity');
  return new Blob([truncate ? bytes.slice(0, -truncate) : bytes], { type: 'image/' + fixture.format });
}
async function open(fixture, mode = 'normal', truncate = 0) {
  const controller = new AbortController();
  const assets = await provider.prepare(fixture.format, controller.signal);
  const state = { mode, messages: [], lifecycle: [], errors: [], workerCreated: 0, terminated: 0, released: 0, terminalCount: 0,
    maximumDataBytes: 0, maximumInflight: 0, outstanding: null, dataCount: 0, tileStarts: 0, tileEnds: 0, pulls: 0, heldAck: false, lastSequence: 0, lateMessages: 0 };
  const note = (direction, message) => {
    const entry = { direction, type: message.type, milliseconds: Math.round(performance.now()), requestId: message.requestId, generation: message.generation };
    if (message.type === 'data') { entry.seq = message.seq; entry.byteLength = message.buffer.byteLength; }
    if (message.type === 'ack') entry.seq = message.seq;
    if (message.type === 'tile-start') { entry.index = message.tile.index; entry.byteLength = message.tile.byteLength; }
    if (message.type === 'tile-end') entry.index = message.index;
    if (message.type === 'terminal') entry.status = message.terminal.status;
    state.messages.push(entry);
  };
  let session;
  try {
    session = imported.decodeImageTiles({ ...assets, blob: await inputBlob(fixture, truncate), format: fixture.format,
      requestId: 'browser-' + (++requestNumber), generation: config.runId + '-' + requestNumber, signal: controller.signal,
      timeoutMs: 300000, cancelGraceMs: 3000 }, {
      createWorker(url) {
        const worker = new Worker(url, { type: 'module' });
        state.workerCreated++; activeWorkers++; maximumActiveWorkers = Math.max(maximumActiveWorkers, activeWorkers);
        const endpoint = { onmessage: null, onerror: null, onmessageerror: null,
          postMessage(message, transfer) {
            if (message.type === 'ack' && mode === 'ack-cancel' && !state.heldAck) {
              state.heldAck = true;
              state.messages.push({ direction: 'withheld', type: 'ack', seq: message.seq, milliseconds: Math.round(performance.now()) });
              queueMicrotask(() => controller.abort());
              return;
            }
            worker.postMessage(message, transfer);
            note('client-to-worker', message);
            if (message.type === 'ack') {
              if (state.outstanding !== message.seq) state.errors.push('ACK sequence mismatch');
              state.outstanding = null;
            }
            if (message.type === 'pull') state.pulls++;
            if (message.type === 'start' && mode === 'start-cancel') queueMicrotask(() => controller.abort());
          },
          terminate() { state.terminated++; state.lifecycle.push('terminate'); worker.terminate(); activeWorkers--; },
        };
        worker.onmessage = event => {
          if (state.terminated) state.lateMessages++;
          const message = event.data;
          note('worker-to-client', message);
          if (message.type === 'data') {
            state.dataCount++;
            state.maximumDataBytes = Math.max(state.maximumDataBytes, message.buffer.byteLength);
            const inflight = state.outstanding === null ? 1 : 2;
            state.maximumInflight = Math.max(state.maximumInflight, inflight);
            if (message.seq !== state.lastSequence + 1) state.errors.push('Nonsequential DATA');
            state.lastSequence = message.seq;
            state.outstanding = message.seq;
          }
          if (message.type === 'tile-start') state.tileStarts++;
          if (message.type === 'tile-end') state.tileEnds++;
          if (message.type === 'terminal') { state.terminalCount++; state.lifecycle.push('terminal'); state.outstandingAtTerminal = state.outstanding; }
          endpoint.onmessage?.(event);
        };
        worker.onerror = event => { state.errors.push('Worker error: ' + event.message); endpoint.onerror?.(event); };
        worker.onmessageerror = event => { state.errors.push('Worker messageerror'); endpoint.onmessageerror?.(event); };
        return endpoint;
      },
      releaseModules() { state.released++; state.lifecycle.push('release'); assets.release(); },
    });
    activeSessions.add(session);
    return { session, controller, state };
  } catch (error) { assets.release(); throw error; }
}
function cleanTerminal(terminal, state, expectedStatus) {
  check(terminal.status === expectedStatus, 'Terminal ' + terminal.status + ': ' + JSON.stringify(terminal.error));
  check(terminal.invalidatesTiles === (expectedStatus !== 'complete'), 'Provisional tile invalidation');
  check(!terminal.forced, 'Unexpected forced termination');
  check(state.workerCreated === 1 && state.terminated === 1 && state.released === 1, 'Worker/module lifecycle counts');
  check(state.terminalCount === 1 && state.lifecycle.join(',') === 'terminal,terminate,release', 'Cooperative lifecycle order');
  check(state.maximumDataBytes <= 65536 && state.maximumInflight <= 1 && state.errors.length === 0 && state.lateMessages === 0, 'DATA/ACK bounds: ' + state.errors.join(';'));
  if (expectedStatus === 'complete') check(terminal.decoder && terminal.encoder, 'Complete C instance ledgers');
  if (terminal.decoder && terminal.decoder.liveBytes !== null) {
    check(terminal.decoder.closeSucceeded && terminal.decoder.liveBytes === 0 && terminal.decoder.allocations === 0, 'Decoder C close ledger');
  }
  if (terminal.encoder) check(terminal.encoder.succeeded && terminal.encoder.liveBytes === 0 && terminal.encoder.allocations === 0, 'Encoder C close ledger');
}
async function tracedFailure(error, session, state) {
  await session.cancel();
  const failure = error instanceof Error ? error : new Error(String(error));
  failure.evidence = { terminal: await session.completion, trace: state };
  throw failure;
}
async function complete(fixture, pause = false) {
  const { session, state } = await open(fixture);
  let tileCount = 0, headerCount = 0, terminalCount = 0, pauseEvidence;
  const digest = [];
  try {
    for await (const event of session) {
      if (event.kind === 'header') {
        headerCount++;
        for (const [key, value] of Object.entries(fixture.header)) check(event[key] === value, 'Header ' + key);
      } else if (event.kind === 'tile') {
        const expected = fixture.tiles[tileCount];
        check(expected && event.index === tileCount && event.provisional === true, 'Tile order/provisional');
        for (const key of ['x', 'y', 'width', 'height', 'byteLength']) check(event[key] === expected[key], 'Tile geometry ' + key);
        for (const key of ['x', 'y', 'width', 'height']) check(event.sourceRect[key] === expected.sourceRect[key], 'Source geometry ' + key);
        const pngHash = await hash(await event.png.arrayBuffer());
        check(pngHash === expected.sha256 && event.png.size === expected.byteLength, 'Tile PNG SHA ' + tileCount);
        digest.push({ index: tileCount, sha256: pngHash, byteLength: event.png.size });
        const slots = [[0, 'first'], [Math.floor(fixture.tiles.length / 2), 'middle'], [fixture.tiles.length - 1, 'last']];
        for (const [index, slot] of slots) if (tileCount === index) await rememberPreview(fixture, event, pngHash, slot);
        tileCount++;
        if (pause && tileCount === 1) {
          const before = { data: state.dataCount, starts: state.tileStarts, ends: state.tileEnds, pulls: state.pulls };
          await delay(250);
          const after = { data: state.dataCount, starts: state.tileStarts, ends: state.tileEnds, pulls: state.pulls };
          check(JSON.stringify(before) === JSON.stringify(after), 'No-pull pause produced another tile/message');
          pauseEvidence = { milliseconds: 250, before, after };
        }
      } else terminalCount++;
    }
    const terminal = await session.completion;
    await delay(25);
    cleanTerminal(terminal, state, 'complete');
    check(headerCount === 1 && terminalCount === 1 && tileCount === fixture.tiles.length, 'Complete stream coverage');
    if (fixture.name === 'png-entropy') check(state.dataCount > 1 && fixture.tiles[0].byteLength > 65536, 'Real multi-block PNG ACK coverage');
    return { name: fixture.name + '-complete', passed: true, headerCount, terminalCount, tileCount, tileDigests: digest, pauseEvidence, terminal, trace: state };
  } catch (error) { return await tracedFailure(error, session, state); }
  finally { await session.cancel(); activeSessions.delete(session); }
}
async function cancellation(fixture, mode) {
  const { session, state } = await open(fixture, mode);
  let deliveredTiles = 0;
  try {
    for await (const event of session) {
      if (event.kind === 'tile') { deliveredTiles++; await session.cancel(); break; }
    }
    const terminal = await session.completion;
    await delay(25);
    cleanTerminal(terminal, state, 'cancelled');
    if (mode === 'normal') check(deliveredTiles === 1, 'First tile cancellation boundary');
    if (mode === 'ack-cancel') check(state.heldAck && state.outstandingAtTerminal === 1 && deliveredTiles === 0, 'Real ACK-wait cancellation');
    return { name: mode === 'normal' ? 'first-tile-cancel' : mode, passed: true, deliveredTiles, terminal, trace: state,
      limitation: mode === 'start-cancel' ? 'Cancel immediately after the real start post; does not prove which import/instantiation instruction was active' : undefined };
  } catch (error) { return await tracedFailure(error, session, state); }
  finally { await session.cancel(); activeSessions.delete(session); }
}
async function truncated(fixture) {
  const { session, state } = await open(fixture, 'normal', fixture.format === 'png' ? 12 : 2);
  let provisionalTiles = 0;
  try {
    for await (const event of session) if (event.kind === 'tile') provisionalTiles++;
    const terminal = await session.completion;
    await delay(25);
    cleanTerminal(terminal, state, 'failed');
    check(provisionalTiles > 0, 'Tail failure must invalidate delivered provisional tiles');
    return { name: fixture.format + '-tail-failure', passed: true, provisionalTiles, terminal, trace: state };
  } catch (error) { return await tracedFailure(error, session, state); }
  finally { await session.cancel(); activeSessions.delete(session); }
}
$('run').onclick = async () => {
  if (running || closing) return;
  running = true; $('run').disabled = true; $('status').textContent = '验收中';
  const cases = [];
  const report = { schemaVersion: 1, runId: config.runId, passed: false, materialVersion: config.materialVersion,
    codecSource: config.codecSource, scope: config.scope, environment: { userAgent: navigator.userAgent,
      crossOriginIsolated, sharedArrayBufferUsed: false }, startedAt: new Date().toISOString(), cases };
  const run = async (name, task) => {
    if (closing) return;
    log('运行 ' + name);
    try { const result = await task(); cases.push(result); log('通过 ' + result.name); }
    catch (error) { cases.push({ name, passed: false, error: error instanceof Error ? error.stack : String(error), evidence: error?.evidence }); log('失败 ' + name + ': ' + error); }
  };
  try {
    await initialize();
    for (const fixture of config.cases) await run(fixture.name, () => complete(fixture, fixture.name === 'png'));
    const png = config.cases.find(item => item.name === 'png');
    const jpeg = config.cases.find(item => item.name === 'jpeg');
    await run('first-tile-cancel', () => cancellation(png, 'normal'));
    await run('ack-cancel', () => cancellation(png, 'ack-cancel'));
    await run('start-cancel', () => cancellation(png, 'start-cancel'));
    await run('png-tail-failure', () => truncated(png));
    await run('jpeg-tail-failure', () => truncated(jpeg));
    await run('recovery-after-errors', async () => { const result = await complete(config.cases.find(item => item.name === 'png-entropy')); return { ...result, name: 'recovery-after-errors' }; });
  } catch (error) { cases.push({ name: 'initialization', passed: false, error: String(error) }); }
  finally {
    await Promise.all(Array.from(activeSessions, session => session.cancel())); activeSessions.clear();
    report.activeWorkers = activeWorkers; report.maximumActiveWorkers = maximumActiveWorkers;
    report.finishedAt = new Date().toISOString();
    report.passed = cases.length === 11 && cases.every(item => item.passed) && activeWorkers === 0;
    const response = await fetch('/report', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(report) });
    check(response.ok, 'Report persistence failed');
    window.codecWorkerReport = report;
    $('status').textContent = report.passed ? '全部通过 · Worker 已关闭' : '存在失败 · 查看报告';
    $('run').disabled = false; running = false;
    log('报告 ' + (report.passed ? 'PASS' : 'FAIL') + '，activeWorkers=' + activeWorkers);
  }
};
$('close').onclick = async () => {
  if (closing) return;
  closing = true; $('run').disabled = true; $('close').disabled = true;
  await Promise.all(Array.from(activeSessions, session => session.cancel()));
  while (running) await delay(50);
  if (clientUrl) URL.revokeObjectURL(clientUrl);
  $('previews').replaceChildren();
  const response = await fetch('/shutdown', { method: 'POST' });
  check(response.ok, 'Shutdown request failed');
  $('status').textContent = '服务已关闭';
};
`;
