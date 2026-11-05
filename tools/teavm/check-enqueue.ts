/** Actual TeaVM/TeaHost callback ownership gate; uses controlled HTTP frames, not a real Source or Access. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { access, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { build } from 'esbuild';
import { zipSync } from 'fflate';
import { getStreamAsBuffer } from 'get-stream';
import isPlainObject from 'is-plain-obj';
import {
  hostAbi,
  HTTP_BRIDGE_MEDIA_TYPE,
  HttpFrameReader,
  httpRequestMetaSchema,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
} from '../../packages/contracts/src/index.ts';
import { compileBridge } from '../../packages/runtime-host/materials.ts';
import { compileExtension } from './build.ts';
import { prepareRuntime } from './runtime.ts';
import { prepareSources } from './upstream-sources.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const WORK = path.join(ROOT, '.local/v4-enqueue');
const sha256 = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');

async function compile(): Promise<void> {
  const runtime = await prepareRuntime();
  const java = path.join(WORK, 'java');
  await rm(java, { recursive: true, force: true });
  await mkdir(java, { recursive: true });
  for (const part of ['src', 'compat'])
    await cp(
      path.join(ROOT, 'runtime/teavm/java', part),
      path.join(java, part),
      { recursive: true },
    );
  prepareSources(path.join(java, 'src/main/java'), ROOT);
  await cp(
    path.join(ROOT, 'runtime/teavm/java/pom.xml'),
    path.join(java, 'pom.xml'),
  );
  await mkdir(path.join(java, 'src/main/java/keiyoushi/source'), {
    recursive: true,
  });
  const fixture = await readFile(
    path.join(ROOT, 'tools/teavm/fixtures/enqueue/Generated.java'),
  );
  await writeFile(
    path.join(java, 'src/main/java/keiyoushi/source/Generated.java'),
    fixture,
  );
  await mkdir(path.join(WORK, 'public/extensions'), { recursive: true });
  await cp(
    path.join(runtime.materials, 'public/runtime'),
    path.join(WORK, 'public/runtime'),
    { recursive: true },
  );
  const jar = zipSync({});
  await writeFile(path.join(WORK, 'public/extensions/probe.jar'), jar);
  const cache = path.join(WORK, 'cache');
  await mkdir(cache, { recursive: true });
  // A private copy permits parallel extension builds without writing their cache.
  try {
    await access(path.join(cache, 'm2'));
  } catch {
    await cp(
      path.join(ROOT, 'runtime/teavm/.local/build-cache/m2'),
      path.join(cache, 'm2'),
      { recursive: true },
    );
  }
  const result = await compileExtension({
    workRoot: WORK,
    sourceRoot: ROOT,
    entry: {
      key: 'enqueue',
      packageName: 'controlled.enqueue.fixture',
      jar: 'probe.jar',
      convertedSha256: sha256(jar),
      expectedSources: [],
    },
    cache,
    maven: runtime.maven,
    env: {
      ...process.env,
      JAVA_HOME: runtime.javaHome,
      PATH:
        path.join(runtime.javaHome, 'bin') +
        path.delimiter +
        (process.env.PATH ?? ''),
      GH_TOKEN: undefined,
      GITHUB_TOKEN: undefined,
      CLOUDFLARE_API_TOKEN: undefined,
    },
  });
  const compiled = await readFile(
    path.join(WORK, 'public/teavm/enqueue/app.js'),
  );
  const bridges = await Promise.all(
    ['crypto', 'cache', 'file'].map(compileBridge),
  );
  const driver = await build({
    absWorkingDir: ROOT,
    entryPoints: ['packages/runtime-host/test/enqueue-java-browser-worker.ts'],
    bundle: true,
    format: 'iife',
    platform: 'browser',
    target: 'es2022',
    write: false,
  });
  assert.equal(driver.outputFiles.length, 1);
  const worker = Buffer.concat([
    Buffer.from(
      "self.karuyomiWorkerContext={plugin:'enqueue-'+crypto.randomUUID()};\n",
    ),
    ...bridges,
    Buffer.from('\n'),
    Buffer.from(driver.outputFiles[0]!.contents),
    compiled,
    Buffer.from('\nself.main([]);self.enqueueFixtureStart();\n'),
  ]);
  await writeFile(path.join(WORK, 'worker.js'), worker);
  await writeFile(
    path.join(WORK, 'identity.json'),
    JSON.stringify(
      {
        hostAbi,
        javaBundleSha256: sha256(compiled),
        javaBundleBytes: compiled.length,
        fixtureSha256: sha256(fixture),
        workerSha256: sha256(worker),
        teavm: result.teavm,
        scope:
          'Actual TeaVM TeaHost and BrowserCall, controlled Source and HTTP-v2 frames; no workerd, production Access, official Source or Native gate',
      },
      null,
      2,
    ) + '\n',
  );
  console.log(
    'Prepared real TeaVM enqueue gate: ' + path.join(WORK, 'worker.js'),
  );
}

async function serve(port: number, timeoutMs: number): Promise<void> {
  const reportPath = path.join(WORK, 'browser-report.json');
  await writeFile(
    reportPath,
    JSON.stringify(
      { passed: false, stage: 'loading_prepared_worker' },
      null,
      2,
    ) + '\n',
  );
  const worker = await readFile(path.join(WORK, 'worker.js'));
  const identity: unknown = JSON.parse(
    await readFile(path.join(WORK, 'identity.json'), 'utf8'),
  );
  assert(
    isPlainObject(identity) && identity.workerSha256 === sha256(worker),
    'Prepared Worker identity mismatch',
  );
  await writeFile(
    reportPath,
    JSON.stringify(
      { passed: false, error: 'browser_not_run', identity },
      null,
      2,
    ) + '\n',
  );
  const network: {
    path: string;
    method: string;
    closed: boolean;
    completed: boolean;
  }[] = [];
  const pendingNext = new Set<() => void>();
  let lateReleased = false;
  let browserResult: Record<string, unknown> | undefined;
  let resolveResult: (value: Record<string, unknown>) => void = () => {};
  let rejectResult: (error: Error) => void = () => {};
  const result = new Promise<Record<string, unknown>>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', 'http://127.0.0.1');
      response.setHeader('Cache-Control', 'no-store');
      if (url.pathname === '/worker.js' && request.method === 'GET') {
        response.setHeader('Content-Type', 'text/javascript');
        response.end(worker);
      } else if (url.pathname === '/event' && request.method === 'POST') {
        const event = (
          await getStreamAsBuffer(request, { maxBuffer: 1024 })
        ).toString();
        assert.equal(event, 'expired-owner-rejected');
        lateReleased = true;
        for (const release of pendingNext) release();
        pendingNext.clear();
        response.end('ok');
      } else if (
        url.pathname === '/api/bridge/http' &&
        request.method === 'POST'
      ) {
        const bytes = await getStreamAsBuffer(request, { maxBuffer: 65536 });
        const body = new Response(new Uint8Array(bytes)).body;
        assert(body);
        const reader = new HttpFrameReader(body, 65536);
        const meta = httpRequestMetaSchema.parse(await reader.meta());
        const target = new URL(meta.url);
        assert.equal(target.origin, 'https://fixture.example.org');
        assert.equal(meta.method, 'POST');
        assert.equal(meta.runtimeGeneration, 'same-generation');
        while ((await reader.read(65536)) !== null) {
          /* Validate complete framed upload. */
        }
        const event = {
          path: target.pathname,
          method: meta.method,
          closed: false,
          completed: false,
        };
        network.push(event);
        response.once('close', () => {
          event.closed = true;
        });
        if (target.pathname === '/network-failure') {
          response.writeHead(502, { 'Content-Type': 'application/json' });
          response.end(JSON.stringify({ error: 'upstream_network_error' }));
          event.completed = true;
          return;
        }
        const encoded = new TextEncoder().encode('opaque encoded bytes');
        response.writeHead(200, { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE });
        response.write(encodePreamble());
        response.write(
          encodeMetaFrame({
            requestId: meta.requestId,
            runtimeGeneration: meta.runtimeGeneration,
            upstreamStatus: 200,
            message: 'OK',
            url: meta.url,
            headers: [],
            hasBody: true,
            bodyLength: encoded.length,
            decoded: true,
          }),
        );
        if (target.pathname === '/cancel') return; // Hold body until the actual Call cancels its fetch.
        const finish = () => {
          if (response.destroyed) return;
          response.write(encodeDataFrame(encoded));
          response.end(encodeEndFrame(encoded.length));
          event.completed = true;
        };
        if (target.pathname === '/next' && !lateReleased)
          pendingNext.add(finish);
        else finish();
      } else if (url.pathname === '/result' && request.method === 'POST') {
        const value: unknown = JSON.parse(
          (await getStreamAsBuffer(request, { maxBuffer: 65536 })).toString(),
        );
        assert(isPlainObject(value) && typeof value.passed === 'boolean');
        response.end('ok', () => resolveResult(value));
      } else if (url.pathname === '/' && request.method === 'GET') {
        response.setHeader('Content-Type', 'text/html; charset=utf-8');
        response.end(
          `<!doctype html><meta charset="utf-8"><title>Actual TeaVM enqueue gate</title><h1>Actual TeaVM enqueue gate</h1><p>Real TeaHost and BinaryHttpTransport. Controlled Source and HTTP-v2 endpoint; no production Access, official Source or Native claim.</p><pre>Running…</pre><script>const worker=new Worker('/worker.js');let reported=false;async function finish(report){if(reported)return;reported=true;report.userAgent=navigator.userAgent;document.querySelector('pre').textContent=JSON.stringify(report,null,2);try{await fetch('/result',{method:'POST',body:JSON.stringify(report)});}finally{worker.terminate();}}worker.onmessage=event=>{if(event.data.type==='enqueue-result')void finish(event.data);};worker.onerror=event=>void finish({passed:false,error:event.message,filename:event.filename,line:event.lineno,column:event.colno});</script>`,
        );
      } else {
        response.writeHead(404);
        response.end();
      }
    } catch (error) {
      if (!response.headersSent) response.writeHead(500);
      response.end(String(error));
      rejectResult(error instanceof Error ? error : Error(String(error)));
    }
  });
  const interrupted = () =>
    rejectResult(Error('TeaVM enqueue gate interrupted'));
  process.once('SIGINT', interrupted);
  process.once('SIGTERM', interrupted);
  const timer = setTimeout(
    () => rejectResult(Error('TeaVM enqueue browser deadline exceeded')),
    timeoutMs,
  );
  try {
    await new Promise<void>((resolve, reject) => {
      server.once('error', reject);
      server.listen(port, '127.0.0.1', resolve);
    });
    const address = server.address();
    assert(address && typeof address !== 'string');
    console.log(
      `Open in Codex built-in browser: http://127.0.0.1:${address.port}/`,
    );
    const browser = await result;
    browserResult = browser;
    const expected = [
      '/nested-first',
      '/nested-second',
      '/callback-failure',
      '/network-failure',
      '/cancel',
      '/next',
      '/deferred-foreground',
      '/deferred-background',
    ];
    const networkVerified =
      network.length === expected.length &&
      expected.every(
        (path) => network.filter((event) => event.path === path).length === 1,
      ) &&
      network.every((event) => event.method === 'POST') &&
      network.find((event) => event.path === '/cancel')?.closed === true &&
      lateReleased;
    const passed =
      browser.passed === true &&
      Array.isArray(browser.checks) &&
      browser.checks.length > 20 &&
      isPlainObject(browser.http) &&
      browser.http.open === 0 &&
      browser.entries === 9 &&
      networkVerified;
    const report = { ...browser, passed, networkVerified, network, identity };
    await writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    assert(passed, 'Actual TeaVM enqueue gate failed');
  } catch (error) {
    await writeFile(
      reportPath,
      JSON.stringify(
        {
          ...browserResult,
          passed: false,
          gateError: String(error),
          network,
          identity,
        },
        null,
        2,
      ) + '\n',
    );
    throw error;
  } finally {
    clearTimeout(timer);
    process.removeListener('SIGINT', interrupted);
    process.removeListener('SIGTERM', interrupted);
    pendingNext.clear();
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

if (import.meta.main) {
  await mkdir(WORK, { recursive: true });
  const reportPath = path.join(WORK, 'browser-report.json');
  await writeFile(
    reportPath,
    JSON.stringify({ passed: false, stage: 'initializing' }, null, 2) + '\n',
  );
  try {
    const { values } = parseArgs({
      options: {
        'build-only': { type: 'boolean' },
        'serve-only': { type: 'boolean' },
        port: { type: 'string' },
        'timeout-ms': { type: 'string' },
      },
    });
    assert(
      !(values['build-only'] && values['serve-only']),
      'Select only one gate stage',
    );
    const port = values.port === undefined ? 0 : Number(values.port);
    const timeoutMs =
      values['timeout-ms'] === undefined
        ? 180000
        : Number(values['timeout-ms']);
    assert(Number.isSafeInteger(port) && port >= 0 && port <= 65535);
    assert(
      Number.isSafeInteger(timeoutMs) &&
        timeoutMs >= 1000 &&
        timeoutMs <= 300000,
    );
    if (!values['serve-only']) await compile();
    if (!values['build-only']) await serve(port, timeoutMs);
  } catch (error) {
    let evidence: Record<string, unknown> = {};
    try {
      const value: unknown = JSON.parse(await readFile(reportPath, 'utf8'));
      if (isPlainObject(value)) evidence = value;
    } catch {
      /* Preserve the original CLI error if its diagnostic file is unavailable. */
    }
    await writeFile(
      reportPath,
      JSON.stringify(
        { ...evidence, passed: false, cliError: String(error) },
        null,
        2,
      ) + '\n',
    );
    throw error;
  }
}
