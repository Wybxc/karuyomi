/** Reproducible browser ownership integration; the operator uses Codex's in-app browser. */
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createServer, type IncomingMessage } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { build } from 'vite';
import lockfile from 'proper-lockfile';
import sirv from 'sirv';
import writeFileAtomic from 'write-file-atomic';
import { z } from 'zod';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import { imageHeaderSchema } from '../../runtime/image-codec/worker-protocol.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const referenceSchema = z.object({
  name: z.string(),
  format: z.enum(['png', 'jpeg']),
  path: z.string().regex(/^\/fixtures\/[a-z-]+\.[a-z]+$/),
  encodedBytes: z.int().positive(),
  encodedSha256: z.string().regex(/^[a-f0-9]{64}$/),
  header: imageHeaderSchema,
  tiles: z
    .array(
      z.object({
        index: z.int().nonnegative(),
        x: z.literal(0),
        y: z.int().nonnegative(),
        width: z.int().positive(),
        height: z.int().positive(),
        sourceRect: z.object({
          x: z.literal(0),
          y: z.int().nonnegative(),
          width: z.int().positive(),
          height: z.int().positive(),
        }),
        byteLength: z.int().positive(),
        sha256: z.string().regex(/^[a-f0-9]{64}$/),
      }),
    )
    .nonempty(),
});
const referenceConfigSchema = z.object({
  schemaVersion: z.literal(1),
  materialVersion: z.string(),
  codecSource: z.object({
    buildIdentity: z.string(),
    abi: z.string(),
    encoderAbi: z.string(),
  }),
  cases: z.array(referenceSchema),
});
export interface ImageOwnersBrowserOptions {
  fixtureDirectory?: string;
  outputDirectory?: string;
  signal?: AbortSignal;
}

function ownerOutputDirectory(outputDirectory?: string): string {
  const directory = path.resolve(
    outputDirectory ?? path.join(ROOT, '.local/image-owners/acceptance'),
  );
  const relative = path.relative(ROOT, directory);
  if (
    relative.startsWith('..') ||
    path.isAbsolute(relative) ||
    relative.split(path.sep)[0] !== '.local'
  )
    throw new Error(
      'Ownership verification output must be inside this repository .local directory',
    );
  return directory;
}

/**
 * Reuse existing fixtures/oracles and rebuild maintained host/Worker JS.
 * Direct callers must hold a proper-lockfile lock on the resolved output directory
 * before preparation and keep it until any associated server has stopped.
 * main() owns this complete lock lifetime for the supported CLI entry point.
 */
export async function prepareImageOwnersBrowser(
  options: ImageOwnersBrowserOptions = {},
) {
  const directory = ownerOutputDirectory(options.outputDirectory);
  const fixtureDirectory = path.resolve(
    options.fixtureDirectory ??
      path.join(ROOT, '.local/image-codec-worker/acceptance/public'),
  );
  const reference = referenceConfigSchema.parse(
    JSON.parse(
      await readFile(path.join(fixtureDirectory, 'config.json'), 'utf8'),
    ),
  );
  const cases = reference.cases.filter(
    (item) => item.name === 'png' || item.name === 'jpeg',
  );
  assert.equal(
    cases.length,
    2,
    'Existing PNG and JPEG fixture oracles are required',
  );
  assert.deepEqual(cases.map((item) => item.name).sort(), ['jpeg', 'png']);
  const publicDirectory = path.join(directory, 'public');
  await mkdir(path.join(publicDirectory, 'fixtures'), { recursive: true });
  await mkdir(path.join(publicDirectory, 'runtime/materials'), {
    recursive: true,
  });
  options.signal?.throwIfAborted();
  const materials = await collectMaterials({
    includeImageCodecs: true,
    ...(options.signal ? { signal: options.signal } : {}),
  });
  assert.deepEqual(
    materials.catalog.sources.imageCodecs,
    reference.codecSource,
    'Codec build changed: regenerate the independent Node tile oracles before owner acceptance',
  );
  const contentTypes = new Map<string, string>();
  for (const [hash, artifact] of materials.data) {
    options.signal?.throwIfAborted();
    await writeFile(
      path.join(publicDirectory, 'runtime/materials', hash),
      artifact.bytes,
    );
    contentTypes.set('/runtime/materials/' + hash, artifact.contentType);
  }
  for (const fixture of cases) {
    options.signal?.throwIfAborted();
    assert(
      fixture.header.sourceWidth * fixture.header.sourceHeight >
        16 * 1024 * 1024,
      'Fixture must exceed the full-image pixel budget',
    );
    const bytes = await readFile(
      path.join(fixtureDirectory, fixture.path.slice(1)),
    );
    assert.equal(
      bytes.length,
      fixture.encodedBytes,
      'Fixture reference byte length',
    );
    assert.equal(
      createHash('sha256').update(bytes).digest('hex'),
      fixture.encodedSha256,
      'Fixture reference SHA-256',
    );
    await writeFile(path.join(publicDirectory, fixture.path.slice(1)), bytes);
  }
  const config = {
    schemaVersion: 1,
    runId: randomUUID(),
    materialVersion: materials.catalog.materialVersion,
    referenceMaterialVersion: reference.materialVersion,
    codecSource: materials.catalog.sources.imageCodecs,
    imageCodecs: materials.catalog.imageCodecs,
    cases,
    scope: {
      input:
        'Opaque Source-processed encoded bytes through real ImageSink/collector ACK and simulated Java publication; all image format/geometry inspection and codec work happen in the client; no real Source execution',
      owners:
        'Opaque Source Blob URL retained until client page cleanup; client-side format/geometry parsing, bounded tile display leases, invalidation and real codec Worker termination order',
      oracle:
        'Existing independent Node WASM tile PNG hashes and geometry from the identical fixed C codec build; current maintained host and Worker JS are freshly bundled',
      excluded:
        'No Reader integration, real extension/Source success, Native/device performance, RSS/GPU/physical memory reclamation or full-image bitmap decode claim',
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
      sourcemap: true,
      lib: {
        entry: path.join(
          ROOT,
          'runtime/image-codec/test/source-image-browser-suite.ts',
        ),
        formats: ['es'],
        fileName: () => 'runner.js',
      },
      rolldownOptions: { output: { codeSplitting: false, comments: false } },
    },
  });
  await writeFile(path.join(publicDirectory, 'index.html'), HTML);
  return { directory, publicDirectory, config, contentTypes };
}

async function body(request: IncomingMessage): Promise<Buffer> {
  const parts: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const value: unknown = chunk;
    if (!Buffer.isBuffer(value))
      throw new Error('Expected binary HTTP report body');
    size += value.length;
    if (size > 8 * 1024 * 1024)
      throw new Error('Owner report exceeds its 8 MiB budget');
    parts.push(value);
  }
  return Buffer.concat(parts, size);
}

export async function serveImageOwnersBrowser(
  prepared: Awaited<ReturnType<typeof prepareImageOwnersBrowser>>,
  { port = 8954, signal }: { port?: number; signal?: AbortSignal } = {},
) {
  signal?.throwIfAborted();
  let closed = false;
  let reportPassed: boolean | undefined;
  const callbacks: { resolve?: () => void } = {};
  const completion = new Promise<void>((resolve) => {
    callbacks.resolve = resolve;
  });
  assert(callbacks.resolve);
  const resolve = callbacks.resolve;
  const files = sirv(prepared.publicDirectory, {
    dev: true,
    setHeaders(response, pathname) {
      const type = prepared.contentTypes.get(pathname);
      if (type) response.setHeader('Content-Type', type);
      response.setHeader('Cache-Control', 'no-store');
    },
  });
  const reportSchema = z
    .object({
      schemaVersion: z.literal(1),
      runId: z.literal(prepared.config.runId),
      passed: z.boolean(),
      cases: z.array(z.json()),
    })
    .passthrough();
  const stop = () => {
    if (closed) return;
    closed = true;
    clearTimeout(deadline);
    signal?.removeEventListener('abort', stop);
    server.close(() => resolve());
    server.closeAllConnections();
  };
  const server = createServer((request, response) => {
    void (async () => {
      const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
      if (request.method === 'POST' && pathname === '/report') {
        const report = reportSchema.parse(
          JSON.parse((await body(request)).toString('utf8')),
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
            cases: report.cases.length,
          }),
        );
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end('{"saved":true}');
      } else if (request.method === 'POST' && pathname === '/shutdown') {
        response.once('finish', stop);
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end('{"closed":true}');
      } else if (request.method === 'GET' || request.method === 'HEAD') {
        files(request, response, () => {
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
  const deadline = setTimeout(stop, 30 * 60 * 1000);
  signal?.addEventListener('abort', stop, { once: true });
  try {
    signal?.throwIfAborted();
    await new Promise<void>((resolve, reject) => {
      const abort = () => reject(signal?.reason);
      const failed = (error: Error) => {
        signal?.removeEventListener('abort', abort);
        reject(error);
      };
      signal?.addEventListener('abort', abort, { once: true });
      server.once('error', failed);
      server.listen(
        { port, host: '127.0.0.1', ...(signal ? { signal } : {}) },
        () => {
          signal?.removeEventListener('abort', abort);
          server.off('error', failed);
          resolve();
        },
      );
    });
    const address = server.address();
    assert(address && typeof address !== 'string');
    console.log(
      JSON.stringify({
        browserUrl: 'http://127.0.0.1:' + address.port,
        outputDirectory: prepared.directory,
        runId: prepared.config.runId,
        shutdown: 'POST /shutdown or page close button',
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
      fixtures: { type: 'string' },
      output: { type: 'string' },
      port: { type: 'string' },
      'prepare-only': { type: 'boolean' },
    },
  });
  const port = Number(parsed.values.port ?? '8954');
  if (!Number.isInteger(port) || port < 0 || port > 65535)
    throw new Error('Invalid localhost port');
  const controller = new AbortController();
  const stop = () => controller.abort();
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
  try {
    const directory = ownerOutputDirectory(parsed.values.output);
    await mkdir(directory, { recursive: true });
    const release = await lockfile.lock(directory, {
      retries: 0,
      stale: 60_000,
    });
    try {
      controller.signal.throwIfAborted();
      const prepared = await prepareImageOwnersBrowser({
        ...(parsed.values.fixtures
          ? { fixtureDirectory: parsed.values.fixtures }
          : {}),
        outputDirectory: directory,
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
        const result = await serveImageOwnersBrowser(prepared, {
          port,
          signal: controller.signal,
        });
        // An absent or rejected report is never a successful browser acceptance.
        if (result.reportPassed !== true) process.exitCode = 1;
      }
    } finally {
      await release();
    }
  } finally {
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
  }
}

const HTML = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Karuyomi 图片所有权验收</title><style>body{font:16px system-ui;max-width:1100px;margin:24px auto;padding:0 16px;background:#f4f7fb;color:#182537}button{font:inherit;padding:10px;margin:4px}pre{white-space:pre-wrap;background:white;padding:16px;max-height:45vh;overflow:auto}#preview img{display:block;max-width:100%;max-height:260px;margin:8px 0}#status{font-weight:600}</style><h1>编码正文 → 有界 PNG tiles 所有权验收</h1><p>合成 Source 处理后正文通过不透明字节 ImageSink/collector，模拟 Java 返回并 publish；客户端接收 Blob 后自行识别图片并调用 codec Worker。覆盖首末中窗口、反向重扫、尾部坏流、取消和借用释放顺序。</p><p>此页不证明真实扩展 Source、Reader、Native、真机性能或物理内存回收。</p><button id="run">运行验收</button><button id="close">关闭服务</button><span id="status">准备就绪</span><div id="preview"></div><pre id="log"></pre><script type="module" src="/runner.js"></script></html>`;
