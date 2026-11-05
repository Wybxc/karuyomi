/** Actual TeaVM/TeaHost callback ownership gate; uses controlled HTTP frames, not a real Source or Access. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { access, cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { gzipSync } from 'node:zlib';
import { build } from 'vite';
import { zipSync } from 'fflate';
import { getStreamAsBuffer } from 'get-stream';
import isPlainObject from 'is-plain-obj';
import sirv from 'sirv';
import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  buildManifestSchema,
  type BuildManifest,
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
  const hostScripts: BuildManifest['hostScripts'] = [];
  await mkdir(path.join(WORK, 'public/runtime/materials'), { recursive: true });
  for (const bytes of bridges) {
    const hash = sha256(bytes);
    await writeFile(path.join(WORK, 'public/runtime/materials', hash), bytes);
    hostScripts.push({
      path: '/runtime/materials/' + hash,
      sha256: hash,
      size: bytes.length,
      contentType: 'application/javascript',
    });
  }
  const encoded = gzipSync(compiled);
  const bundleSha256 = sha256(compiled);
  await mkdir(path.join(WORK, 'public/extensions/artifacts'), {
    recursive: true,
  });
  await writeFile(
    path.join(WORK, 'public/extensions/artifacts', bundleSha256 + '.gz'),
    encoded,
  );
  const manifest = buildManifestSchema.parse({
    protocolVersion,
    hostAbi,
    runtimeBaseline,
    bridgeVersion: 2,
    buildId: 'enqueue-manager',
    repoId: 'controlled-enqueue',
    packageName: 'controlled.enqueue.fixture',
    version: '1',
    storageSchema: '1',
    sourceIds: ['1'],
    bundle: {
      path: '/extensions/artifacts/' + bundleSha256 + '.gz',
      sha256: bundleSha256,
      size: compiled.length,
      contentType: 'application/javascript',
      encoding: 'gzip',
      encodedSha256: sha256(encoded),
      encodedSize: encoded.length,
    },
    hostScripts,
    resources: [],
  });
  await mkdir(path.join(WORK, 'public/extensions/builds/enqueue-manager'), {
    recursive: true,
  });
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  await writeFile(
    path.join(WORK, 'public/extensions/builds/enqueue-manager/manifest.json'),
    manifestBytes,
  );
  const scripts: Record<string, string> = {};
  for (const [name, entry, format] of [
    [
      'manager-worker',
      'packages/runtime-host/test/enqueue-java-manager-browser-worker.ts',
      'iife',
    ],
    [
      'manager-suite',
      'packages/runtime-host/test/enqueue-java-manager-browser-suite.ts',
      'esm',
    ],
  ] as const) {
    const output = await build({
      configFile: false,
      root: ROOT,
      publicDir: false,
      logLevel: 'silent',
      build: {
        target: 'es2022',
        minify: false,
        write: false,
        lib: {
          entry: path.join(ROOT, entry),
          name: 'KaruyomiEnqueueManager',
          formats: [format === 'esm' ? 'es' : format],
          fileName: () => name + '.js',
        },
        rolldownOptions: { output: { codeSplitting: false } },
      },
    });
    const chunks = (Array.isArray(output) ? output : [output]).flatMap(
      (value) => ('output' in value ? value.output : []),
    );
    assert(
      chunks.length === 1 &&
        chunks[0]?.type === 'chunk' &&
        chunks[0].isEntry &&
        !chunks[0].imports.length &&
        !chunks[0].dynamicImports.length,
    );
    const bytes = Buffer.from(chunks[0].code);
    await writeFile(path.join(WORK, 'public', name + '.js'), bytes);
    scripts[name] = sha256(bytes);
  }
  const driver = await build({
    configFile: false,
    root: ROOT,
    publicDir: false,
    logLevel: 'silent',
    build: {
      target: 'es2022',
      minify: false,
      write: false,
      lib: {
        entry: path.join(
          ROOT,
          'packages/runtime-host/test/enqueue-java-browser-worker.ts',
        ),
        name: 'KaruyomiEnqueueWorker',
        formats: ['iife'],
        fileName: () => 'enqueue-java-browser-worker.js',
      },
      rolldownOptions: { output: { codeSplitting: false } },
    },
  });
  const driverOutput = (Array.isArray(driver) ? driver : [driver]).flatMap(
    (value) => ('output' in value ? value.output : []),
  );
  assert(
    driverOutput.length === 1 &&
      driverOutput[0]?.type === 'chunk' &&
      driverOutput[0].isEntry &&
      !driverOutput[0].imports.length &&
      !driverOutput[0].dynamicImports.length,
  );
  const worker = Buffer.concat([
    Buffer.from(
      "self.karuyomiWorkerContext={plugin:'enqueue-'+crypto.randomUUID()};\n",
    ),
    ...bridges,
    Buffer.from('\n'),
    Buffer.from(driverOutput[0].code),
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
        managerScripts: scripts,
        managerManifestSha256: sha256(manifestBytes),
        managerBundleEncodedSha256: sha256(encoded),
        hostScripts: hostScripts.map((value) => value.sha256),
        teavm: result.teavm,
        scope:
          'Actual TeaVM TeaHost/BrowserCall and product manager/WorkerRuntime/TeaVMDriver/loader, controlled Source and HTTP-v2 frames; no workerd, production Access, official Source or Native gate',
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
  assert(
    isPlainObject(identity.managerScripts),
    'Missing prepared manager script identities',
  );
  for (const name of ['manager-worker', 'manager-suite'])
    assert.equal(
      sha256(await readFile(path.join(WORK, 'public', name + '.js'))),
      identity.managerScripts[name],
      'Prepared manager script identity mismatch',
    );
  const manifestBytes = await readFile(
    path.join(WORK, 'public/extensions/builds/enqueue-manager/manifest.json'),
  );
  assert.equal(
    sha256(manifestBytes),
    identity.managerManifestSha256,
    'Prepared manifest identity mismatch',
  );
  const manifest = buildManifestSchema.parse(
    JSON.parse(manifestBytes.toString()),
  );
  const encodedBundle = await readFile(
    path.join(WORK, 'public', manifest.bundle.path),
  );
  assert.equal(
    sha256(encodedBundle),
    identity.managerBundleEncodedSha256,
    'Prepared manager bundle identity mismatch',
  );
  for (const artifact of manifest.hostScripts)
    assert.equal(
      sha256(await readFile(path.join(WORK, 'public', artifact.path))),
      artifact.sha256,
      'Prepared manager bridge identity mismatch',
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
  const staticFiles = sirv(path.join(WORK, 'public'), {
    dev: true,
    setHeaders(response, pathname) {
      response.setHeader('Cache-Control', 'no-store');
      if (pathname.includes('/runtime/materials/'))
        response.setHeader('Content-Type', 'application/javascript');
      if (pathname.endsWith('.gz'))
        response.setHeader('Content-Type', 'application/gzip');
    },
  });
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? '/', 'http://127.0.0.1');
      response.setHeader('Cache-Control', 'no-store');
      if (url.pathname === '/worker.js' && request.method === 'GET') {
        response.setHeader('Content-Type', 'text/javascript');
        response.end(worker);
      } else if (
        url.pathname === manifest.bundle.path &&
        request.method === 'GET'
      ) {
        // The gzip artifact is opaque transport bytes, not HTTP content encoding.
        response.writeHead(200, {
          'Content-Type': 'application/gzip',
          'Content-Length': encodedBundle.length,
        });
        response.end(encodedBundle);
      } else if (
        url.pathname === '/network-state' &&
        request.method === 'GET'
      ) {
        response.setHeader('Content-Type', 'application/json');
        response.end(JSON.stringify({ network }));
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
        if (target.pathname === '/drain-timeout') {
          assert.match(meta.runtimeGeneration, /^[a-f0-9-]{36}$/);
          assert.equal(request.headers['x-runtime-build'], 'enqueue-manager');
          assert.equal(meta.timeoutMs, 90000);
        } else assert.equal(meta.runtimeGeneration, 'same-generation');
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
        if (
          target.pathname === '/cancel' ||
          target.pathname === '/drain-timeout'
        )
          return;
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
          `<!doctype html><meta charset="utf-8"><title>Actual TeaVM enqueue gate</title><h1>Actual TeaVM enqueue gate</h1><p>Real TeaHost, product manager/Worker/driver and HTTP-v2. Controlled Source and endpoint; no production Access, official Source or Native claim. The unchanged Java drain takes 30 seconds.</p><pre>Running basic owner cases…</pre><script type="module">import {runEnqueueManagerSuite} from '/manager-suite.js';const worker=new Worker('/worker.js');let reported=false;async function finish(basic){if(reported)return;reported=true;worker.terminate();let manager;try{if(basic.passed){document.querySelector('pre').textContent='Running pending limit and real 30-second fatal drain…';manager=await runEnqueueManagerSuite();}}catch(error){manager={passed:false,error:String(error),cleanupPassed:false};}const report={...basic,manager,passed:basic.passed===true&&manager?.passed===true,userAgent:navigator.userAgent};document.querySelector('pre').textContent=JSON.stringify(report,null,2);await fetch('/result',{method:'POST',body:JSON.stringify(report)});}worker.onmessage=event=>{if(event.data.type==='enqueue-result')void finish(event.data);};worker.onerror=event=>void finish({passed:false,error:event.message,filename:event.filename,line:event.lineno,column:event.colno});</script>`,
        );
      } else {
        staticFiles(request, response);
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
      '/drain-timeout',
    ];
    const networkVerified =
      network.length === expected.length &&
      expected.every(
        (path) => network.filter((event) => event.path === path).length === 1,
      ) &&
      network.every((event) => event.method === 'POST') &&
      network.find((event) => event.path === '/cancel')?.closed === true &&
      network.find((event) => event.path === '/drain-timeout')?.closed ===
        true &&
      network.find((event) => event.path === '/drain-timeout')?.completed ===
        false &&
      lateReleased;
    const passed =
      browser.passed === true &&
      Array.isArray(browser.checks) &&
      browser.checks.length > 20 &&
      isPlainObject(browser.http) &&
      browser.http.open === 0 &&
      browser.entries === 9 &&
      isPlainObject(browser.manager) &&
      browser.manager.passed === true &&
      browser.manager.cleanupPassed === true &&
      browser.manager.upstreamClosedBeforeServiceCleanup === true &&
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
