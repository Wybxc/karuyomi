/** Manual real-manager/storage gate with a controlled TypeScript host ABI; no Source/JVM dependency. */
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { gzipSync } from 'node:zlib';
import { build } from 'esbuild';
import sirv from 'sirv';
import { getStreamAsBuffer } from 'get-stream';
import writeFileAtomic from 'write-file-atomic';
import isPlainObject from 'is-plain-obj';
import { compileBridge } from '../../packages/runtime-host/materials.ts';
import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  buildManifestSchema,
  type BuildManifest,
} from '../../packages/contracts/src/index.ts';
const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const digest = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
export async function checkRuntimeStorage({
  port = 0,
  timeoutMs = 300000,
}: { port?: number; timeoutMs?: number } = {}) {
  const work = path.join(ROOT, '.local/runtime-storage'),
    publicDir = path.join(work, 'public'),
    reportFile = path.join(work, 'browser-report.json');
  await mkdir(work, { recursive: true });
  await writeFileAtomic(
    reportFile,
    JSON.stringify({ passed: false, error: 'initializing' }) + '\n',
  );
  let browserResult: Record<string, unknown> | undefined;
  let primaryFailure: unknown;
  let identity: Record<string, unknown> | undefined,
    server: ReturnType<typeof createServer> | undefined,
    timer: ReturnType<typeof setTimeout> | undefined,
    received = false;
  const controller = new AbortController(),
    interrupted = () =>
      controller.abort(Error('Runtime storage gate interrupted'));
  process.on('SIGINT', interrupted);
  process.on('SIGTERM', interrupted);
  try {
    assert(Number.isInteger(port) && port >= 0 && port <= 65535);
    assert(
      Number.isInteger(timeoutMs) && timeoutMs >= 1000 && timeoutMs <= 900000,
    );
    await rm(publicDir, { recursive: true, force: true });
    await mkdir(publicDir, { recursive: true });
    const run = randomUUID(),
      hostScripts: BuildManifest['hostScripts'] = [],
      bridgeIdentity: Record<string, string> = {};
    for (const name of ['cache', 'file']) {
      const bytes = await compileBridge(name),
        sha256 = digest(bytes),
        relative = '/runtime/materials/' + sha256;
      await mkdir(path.join(publicDir, 'runtime/materials'), {
        recursive: true,
      });
      await writeFile(path.join(publicDir, relative), bytes);
      hostScripts.push({
        path: relative,
        sha256,
        size: bytes.length,
        contentType: 'application/javascript',
      });
      bridgeIdentity[name] = sha256;
    }
    const scriptIdentity: Record<string, string> = {};
    for (const [name, entry, format] of [
      ['worker', 'packages/runtime-host/src/worker.ts', 'iife'],
      [
        'suite',
        'packages/runtime-host/test/storage-namespace-browser-suite.ts',
        'esm',
      ],
    ] as const) {
      const result = await build({
        absWorkingDir: ROOT,
        entryPoints: [entry],
        bundle: true,
        platform: 'browser',
        format,
        target: 'es2022',
        write: false,
      });
      assert(result.outputFiles.length === 1);
      const bytes = result.outputFiles[0]!.contents;
      await writeFile(path.join(publicDir, name + '.js'), bytes);
      scriptIdentity[name] = digest(bytes);
    }
    const bundles: BuildManifest['bundle'][] = [];
    const transports = new Map<string, Buffer>();
    for (const label of ['a', 'b']) {
      const result = await build({
        absWorkingDir: ROOT,
        entryPoints: [
          'packages/runtime-host/test/fixtures/storage-namespace-host.ts',
        ],
        bundle: true,
        platform: 'browser',
        format: 'iife',
        target: 'es2022',
        write: false,
        define: { STORAGE_FIXTURE_BUILD: JSON.stringify(label) },
      });
      assert(result.outputFiles.length === 1);
      const bytes = result.outputFiles[0]!.contents,
        sha256 = digest(bytes),
        encoded = gzipSync(bytes),
        relative = '/extensions/artifacts/' + sha256 + '.gz';
      await mkdir(path.join(publicDir, 'extensions/artifacts'), {
        recursive: true,
      });
      await writeFile(path.join(publicDir, relative), encoded);
      transports.set(relative, encoded);
      bundles.push({
        path: relative,
        sha256,
        size: bytes.length,
        contentType: 'application/javascript',
        encoding: 'gzip',
        encodedSha256: digest(encoded),
        encodedSize: encoded.length,
      });
    }
    for (const name of ['a', 'b', 'repo', 'package', 'schema']) {
      const manifest: BuildManifest = {
        protocolVersion,
        hostAbi,
        runtimeBaseline,
        bridgeVersion: 2,
        buildId: 'storage-' + name,
        repoId: (name === 'repo' ? 'other-repo-' : 'storage-repo-') + run,
        packageName:
          name === 'package' ? 'other.storage.fixture' : 'storage.fixture',
        version: name === 'a' ? '1' : '2',
        storageSchema: name === 'schema' ? '2' : '1',
        sourceIds: ['1'],
        bundle: bundles[name === 'a' ? 0 : 1]!,
        hostScripts,
        resources: [],
      };
      buildManifestSchema.parse(manifest);
      const dir = path.join(publicDir, 'extensions/builds', manifest.buildId);
      await mkdir(dir, { recursive: true });
      await writeFile(
        path.join(dir, 'manifest.json'),
        JSON.stringify(manifest),
      );
    }
    await writeFile(
      path.join(publicDir, 'fixture.json'),
      JSON.stringify({ run }),
    );
    identity = {
      run,
      controlledAbi: true,
      bridges: bridgeIdentity,
      scripts: scriptIdentity,
      bundles: bundles.map((value) => value.sha256),
      runnerSha256: digest(await readFile(fileURLToPath(import.meta.url))),
    };
    await writeFile(
      path.join(publicDir, 'index.html'),
      `<!doctype html><meta charset="utf-8"><title>Runtime storage namespace gate</title><h1>Runtime storage namespace gate</h1><p>Real manager, verified static loader and product Worker/driver. Controlled TypeScript host ABI; no Java, official Source, Access, Native or physical-memory claim. This writes 256 MiB allocated in two real IDB partitions.</p><pre>Running…</pre><script type="module">import {runStorageNamespaceSuite} from '/suite.js';let report;try{report=await runStorageNamespaceSuite();}catch(error){report={passed:false,error:String(error),stack:error instanceof Error?error.stack:undefined,cleanupConfirmed:false};}document.querySelector('pre').textContent=JSON.stringify(report,null,2);await fetch('/result',{method:'POST',body:JSON.stringify(report)});</script>`,
    );
    controller.signal.throwIfAborted();
    const staticFiles = sirv(publicDir, {
      dev: true,
      setHeaders(response, pathname) {
        response.setHeader('Cache-Control', 'no-store');
        if (pathname.includes('/runtime/materials/'))
          response.setHeader('Content-Type', 'application/javascript');
      },
    });
    let complete: (value: Record<string, unknown>) => void = () => {};
    const completed = new Promise<Record<string, unknown>>((resolve) => {
      complete = resolve;
    });
    server = createServer((request, response) => {
      if (request.url === '/result' && request.method === 'POST') {
        void (async () => {
          try {
            const value: unknown = JSON.parse(
              (await getStreamAsBuffer(request, { maxBuffer: 65536 })).toString(
                'utf8',
              ),
            );
            assert(isPlainObject(value) && typeof value.passed === 'boolean');
            response.end('ok', () => {
              if (!received) {
                received = true;
                complete(value);
              }
            });
          } catch (error) {
            response.writeHead(400).end(String(error));
            controller.abort(error);
          }
        })();
      } else {
        const artifact = transports.get(request.url ?? '');
        if (artifact && request.method === 'GET') {
          // A .gz artifact is opaque transport bytes, not HTTP Content-Encoding.
          response
            .writeHead(200, {
              'Content-Type': 'application/gzip',
              'Content-Length': artifact.length,
              'Cache-Control': 'no-store',
            })
            .end(artifact);
        } else staticFiles(request, response);
      }
    });
    const listening = once(server, 'listening', { signal: controller.signal });
    server.listen(port, '127.0.0.1');
    await listening;
    const address = server.address();
    assert(address && typeof address !== 'string');
    await writeFileAtomic(
      reportFile,
      JSON.stringify({ passed: false, error: 'browser_not_run', identity }) +
        '\n',
    );
    console.log(
      'Open in Codex built-in browser: http://127.0.0.1:' + address.port + '/',
    );
    console.log(JSON.stringify(identity));
    timer = setTimeout(
      () =>
        controller.abort(Error('Runtime storage browser deadline exceeded')),
      timeoutMs,
    );
    const abort = new Promise<never>((_, reject) =>
      controller.signal.addEventListener(
        'abort',
        () => reject(controller.signal.reason),
        { once: true },
      ),
    );
    controller.signal.throwIfAborted();
    const result = await Promise.race([completed, abort]);
    browserResult = result;
    const passed =
      result.passed === true &&
      result.controlledAbi === true &&
      result.cleanupPassed === true &&
      Array.isArray(result.checks) &&
      result.checks.length === 11 &&
      new Set(result.checks).size === 11;
    const report = { ...result, passed, identity };
    await writeFileAtomic(reportFile, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    assert(passed, 'Real manager / combined storage gate');
  } catch (error) {
    primaryFailure = error;
    await writeFileAtomic(
      reportFile,
      JSON.stringify(
        {
          ...browserResult,
          passed: false,
          error:
            typeof browserResult?.error === 'string'
              ? browserResult.error
              : String(error),
          terminalError: String(error),
          identity,
          cleanupConfirmed: browserResult?.cleanupPassed === true,
        },
        null,
        2,
      ) + '\n',
    );
    throw error;
  } finally {
    clearTimeout(timer);
    try {
      const activeServer = server;
      if (activeServer?.listening) {
        activeServer.closeAllConnections();
        await new Promise<void>((resolve, reject) =>
          activeServer.close((error) => (error ? reject(error) : resolve())),
        );
      }
    } catch (cleanup) {
      const errors = [
        ...(primaryFailure === undefined ? [] : [primaryFailure]),
        cleanup,
      ];
      const error = new AggregateError(
        errors,
        'Runtime storage server cleanup failed: ' +
          errors.map(String).join(' | '),
      );
      await writeFileAtomic(
        reportFile,
        JSON.stringify(
          {
            ...browserResult,
            passed: false,
            error: String(error),
            identity,
            cleanupConfirmed: false,
          },
          null,
          2,
        ) + '\n',
      );
      throw error;
    } finally {
      process.removeListener('SIGINT', interrupted);
      process.removeListener('SIGTERM', interrupted);
    }
  }
}
if (import.meta.main) {
  const { values } = parseArgs({
    options: { port: { type: 'string' }, 'timeout-ms': { type: 'string' } },
  });
  await checkRuntimeStorage({
    ...(values.port ? { port: Number(values.port) } : {}),
    ...(values['timeout-ms']
      ? { timeoutMs: Number(values['timeout-ms']) }
      : {}),
  });
}
