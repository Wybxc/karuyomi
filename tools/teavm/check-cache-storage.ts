/** Manual real-browser gate for the product Cache bridge; no JVM or Source network. */
import { createServer } from 'node:http';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { build } from 'esbuild';
import isPlainObject from 'is-plain-obj';
import writeFileAtomic from 'write-file-atomic';
import { compileBridge } from '../../packages/runtime-host/materials.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function checkCacheStorage({
  report = path.join(ROOT, '.local/cache-lifecycle/browser-result.json'),
  timeoutMs = 180000,
  port = 0,
}: { report?: string; timeoutMs?: number; port?: number } = {}): Promise<void> {
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 1000 ||
    timeoutMs > 300000
  )
    throw Error('Cache browser timeout must be 1000..300000 ms');
  if (!Number.isSafeInteger(port) || port < 0 || port > 65535)
    throw Error('Cache browser port must be 0..65535');
  const reportPath = path.resolve(report);
  await mkdir(path.dirname(reportPath), { recursive: true });
  // An interrupted or never-opened run must not leave a previous passed report.
  await writeFileAtomic(
    reportPath,
    JSON.stringify({ passed: false, error: 'browser_not_run' }, null, 2) + '\n',
  );
  const cache = await compileBridge('cache');
  const [driver, suite] = await Promise.all(
    ['cache-lifecycle-worker', 'cache-lifecycle-browser-suite'].map((name) =>
      build({
        absWorkingDir: ROOT,
        entryPoints: ['packages/runtime-host/test/' + name + '.ts'],
        bundle: true,
        platform: 'browser',
        format: name.endsWith('worker') ? 'iife' : 'esm',
        target: 'es2022',
        write: false,
      }),
    ),
  );
  const driverBytes = driver?.outputFiles?.[0]?.contents,
    suiteBytes = suite?.outputFiles?.[0]?.contents;
  if (!driverBytes || !suiteBytes)
    throw Error('Missing Cache browser test output');
  const worker = Buffer.concat([cache, Buffer.from('\n'), driverBytes]);
  let resolveReport: (value: Record<string, unknown>) => void = () => {},
    rejectReport: (error: Error) => void = () => {},
    received = false;
  const result = new Promise<Record<string, unknown>>((resolve, reject) => {
    resolveReport = resolve;
    rejectReport = reject;
  });
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', 'http://127.0.0.1');
      response.setHeader('Cache-Control', 'no-store');
      if (request.method === 'GET' && url.pathname === '/worker.js') {
        response.setHeader('Content-Type', 'application/javascript');
        response.end(worker);
      } else if (request.method === 'GET' && url.pathname === '/suite.js') {
        response.setHeader('Content-Type', 'application/javascript');
        response.end(suiteBytes);
      } else if (request.method === 'POST' && url.pathname === '/result') {
        const chunks: Buffer[] = [];
        let length = 0;
        for await (const chunk of request) {
          const bytes = Buffer.isBuffer(chunk)
            ? chunk
            : Buffer.from(String(chunk));
          length += bytes.length;
          if (length > 65536)
            throw Error('Cache browser report exceeds 64 KiB');
          chunks.push(bytes);
        }
        const value: unknown = JSON.parse(
          Buffer.concat(chunks).toString('utf8'),
        );
        if (
          !isPlainObject(value) ||
          typeof value.passed !== 'boolean' ||
          (value.passed &&
            (!Array.isArray(value.checks) ||
              value.checks.length === 0 ||
              !value.checks.every(
                (check: unknown) => typeof check === 'string',
              )))
        )
          throw Error('Invalid Cache browser report');
        response.end('ok', () => {
          if (!received) {
            received = true;
            resolveReport(value);
          }
        });
      } else if (request.method === 'GET' && url.pathname === '/') {
        response.setHeader('Content-Type', 'text/html; charset=utf-8');
        response.end(
          `<!doctype html><meta charset="utf-8"><title>Cache storage regression</title><h1>Cache storage regression</h1><p>Product bridge, actual Worker, IndexedDB and Web Locks. No Java, Source or Native gate.</p><pre id="result">Running…</pre><script type="module">import {runCacheLifecycleSuite} from '/suite.js';let result;try{result=await runCacheLifecycleSuite('/worker.js');}catch(error){result={passed:false,error:String(error),stack:error instanceof Error?error.stack:undefined,userAgent:navigator.userAgent};}document.querySelector('#result').textContent=JSON.stringify(result,null,2);await fetch('/result',{method:'POST',body:JSON.stringify(result)});</script>`,
        );
      } else {
        response.writeHead(404);
        response.end();
      }
    } catch (error) {
      response.writeHead(400);
      response.end(
        error instanceof Error ? error.message : 'Invalid browser request',
      );
    }
  });
  const interrupted = () =>
    rejectReport(Error('Cache browser gate interrupted'));
  process.once('SIGINT', interrupted);
  process.once('SIGTERM', interrupted);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', resolve);
    });
    const address = server.address();
    if (!address || typeof address === 'string')
      throw Error('Missing browser gate address');
    console.log(
      `Open in the Codex built-in browser: http://127.0.0.1:${address.port}/`,
    );
    timer = setTimeout(
      () =>
        rejectReport(Error('Cache browser was not completed before timeout')),
      timeoutMs,
    );
    const completed = await result;
    await writeFileAtomic(
      reportPath,
      JSON.stringify(completed, null, 2) + '\n',
    );
    console.log(JSON.stringify(completed, null, 2));
    console.log('Report: ' + reportPath);
    if (!completed.passed)
      throw Error('Real-browser Cache storage gate failed');
  } catch (error) {
    if (!received)
      await writeFileAtomic(
        reportPath,
        JSON.stringify(
          {
            passed: false,
            error:
              error instanceof Error
                ? error.message
                : 'Cache browser gate failed',
          },
          null,
          2,
        ) + '\n',
      );
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
    process.removeListener('SIGINT', interrupted);
    process.removeListener('SIGTERM', interrupted);
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      report: { type: 'string' },
      'timeout-ms': { type: 'string' },
      port: { type: 'string' },
    },
  });
  await checkCacheStorage({
    ...(values.report ? { report: values.report } : {}),
    ...(values['timeout-ms']
      ? { timeoutMs: Number(values['timeout-ms']) }
      : {}),
    ...(values.port ? { port: Number(values.port) } : {}),
  });
}
