/** Manual original-JVM / actual TeaVM CacheInterceptor gate against a deterministic real HTTP origin. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import {
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
  access,
} from 'node:fs/promises';
import {
  createServer,
  request as httpRequest,
  type IncomingMessage,
} from 'node:http';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { build } from 'esbuild';
import { execa } from 'execa';
import { zipSync } from 'fflate';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import isPlainObject from 'is-plain-obj';
import { unstable_readConfig } from 'wrangler';
import { compileBridge } from '../../../packages/runtime-host/materials.ts';
import { compileExtension } from '../../../tools/teavm/build.ts';
import {
  prepareRuntime,
  type PreparedRuntime,
} from '../../../tools/teavm/runtime.ts';
import { prepareSources } from '../../../tools/teavm/upstream-sources.ts';
import { createCacheHttpOrigin } from '../../../tools/teavm/cache-http-origin.ts';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const hash = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
const ORIGINAL_SHA =
  '234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52';

async function originalJvm(work: string, runtime: PreparedRuntime) {
  const original = path.join(work, 'dependencies/okhttp-jvm-5.5.0.jar');
  await mkdir(path.dirname(original), { recursive: true });
  try {
    await access(original);
  } catch {
    const response = await fetch(
      'https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp-jvm/5.5.0/okhttp-jvm-5.5.0.jar',
    );
    assert(response.ok, 'Original OkHttp download failed');
    const bytes = new Uint8Array(await response.arrayBuffer());
    assert.equal(hash(bytes), ORIGINAL_SHA, 'Original OkHttp download SHA');
    await writeFile(original, bytes);
  }
  assert.equal(
    hash(await readFile(original)),
    ORIGINAL_SHA,
    'Original OkHttp cached SHA',
  );
  const seed = path.join(runtime.materials, 'public/runtime');
  const jars = (await readdir(seed)).filter(
    (name) =>
      name.endsWith('.jar') &&
      !name.startsWith('host-') &&
      name !== 'okhttp-jvm-5.5.0.jar',
  );
  const classpath = [
    original,
    ...jars.map((name) => path.join(seed, name)),
  ].join(path.delimiter);
  const classes = path.join(work, 'oracle-classes'),
    storage = path.join(work, 'oracle-storage');
  await rm(classes, { recursive: true, force: true });
  await rm(storage, { recursive: true, force: true });
  await mkdir(classes, { recursive: true });
  await execa(
    path.join(runtime.javaHome, 'bin/javac'),
    [
      '--release',
      '17',
      '-cp',
      classpath,
      '-d',
      classes,
      ...[
        'CacheScenarios.java',
        'CacheFailureScenarios.java',
        'CacheFailureOracle.java',
      ].map((name) => path.join(ROOT, 'tools/teavm', name)),
    ],
    { cwd: ROOT },
  );
  const origin = await createCacheHttpOrigin();
  try {
    const result = await execa(
      path.join(runtime.javaHome, 'bin/java'),
      [
        '-cp',
        classes + path.delimiter + classpath,
        'prototype.CacheFailureOracle',
        origin.origin,
        storage,
      ],
      { cwd: ROOT, timeout: 60000 },
    );
    const value: unknown = JSON.parse(result.stdout);
    assert(
      isPlainObject(value) && value.passed === true && value.checks === 50,
      'Original JVM failure scenarios',
    );
    await origin.waitForFailureCloses(5000);
    const report = {
      oracle: value,
      originalOkHttpSha256: ORIGINAL_SHA,
      events: origin.events,
    };
    await writeFile(
      path.join(work, 'jvm-report.json'),
      JSON.stringify(report, null, 2) + '\n',
    );
    console.log('Original JVM Cache failure scenarios: 50 checks passed');
    return report;
  } finally {
    await origin.close();
  }
}

async function teaVm(work: string, runtime: PreparedRuntime) {
  const java = path.join(work, 'java');
  await rm(java, { recursive: true, force: true });
  await mkdir(java, { recursive: true });
  for (const part of ['src', 'compat'])
    await cp(
      path.join(ROOT, 'runtime/teavm/java', part),
      path.join(java, part),
      { recursive: true },
    );
  prepareSources(path.join(java, 'src/main/java'), ROOT);
  const pom = (
    await readFile(path.join(ROOT, 'runtime/teavm/java/pom.xml'), 'utf8')
  ).replace(
    '<mainClass>prototype.TeaHost</mainClass>',
    '<mainClass>prototype.CacheFailureProbe</mainClass>',
  );
  await writeFile(path.join(java, 'pom.xml'), pom);
  await mkdir(path.join(java, 'src/main/java/keiyoushi/source'), {
    recursive: true,
  });
  await writeFile(
    path.join(java, 'src/main/java/keiyoushi/source/Generated.java'),
    'package keiyoushi.source; public class Generated {}\n',
  );
  for (const name of ['CacheScenarios.java', 'CacheFailureScenarios.java'])
    await cp(
      path.join(ROOT, 'tools/teavm', name),
      path.join(java, 'src/main/java/prototype', name),
    );
  await cp(
    path.join(
      ROOT,
      'tools/teavm/fixtures/cache-failure/CacheFailureProbe.java',
    ),
    path.join(java, 'src/main/java/prototype/CacheFailureProbe.java'),
  );
  await mkdir(path.join(work, 'public/extensions'), { recursive: true });
  await cp(
    path.join(runtime.materials, 'public/runtime'),
    path.join(work, 'public/runtime'),
    { recursive: true },
  );
  const jar = zipSync({});
  await writeFile(path.join(work, 'public/extensions/probe.jar'), jar);
  const cache = path.join(work, 'cache');
  await mkdir(cache, { recursive: true });
  try {
    await access(path.join(cache, 'm2'));
  } catch {
    await symlink(
      path.join(ROOT, 'runtime/teavm/.local/build-cache/m2'),
      path.join(cache, 'm2'),
      'dir',
    );
  }
  const env = {
    ...process.env,
    JAVA_HOME: runtime.javaHome,
    PATH:
      path.join(runtime.javaHome, 'bin') +
      path.delimiter +
      (process.env.PATH ?? ''),
    GH_TOKEN: undefined,
    GITHUB_TOKEN: undefined,
    CLOUDFLARE_API_TOKEN: undefined,
  };
  const result = await compileExtension({
    workRoot: work,
    sourceRoot: ROOT,
    entry: {
      key: 'cache-failure',
      packageName: 'cache.failure.probe',
      jar: 'probe.jar',
      convertedSha256: hash(jar),
      expectedSources: [],
    },
    maven: runtime.maven,
    cache,
    env,
  });
  return {
    result,
    bytes: await readFile(path.join(work, 'public/teavm/cache-failure/app.js')),
  };
}

export async function checkCacheHttp({
  jvmOnly = false,
  port = 0,
  timeoutMs = 300000,
}: {
  jvmOnly?: boolean;
  port?: number;
  timeoutMs?: number;
} = {}) {
  const work = path.join(ROOT, '.local/cache-failure-http');
  await mkdir(work, { recursive: true });
  await writeFile(
    path.join(work, 'browser-report.json'),
    JSON.stringify({ passed: false, error: 'initializing' }, null, 2) + '\n',
  );
  let identity: Record<string, unknown> | undefined;
  let jvm: Awaited<ReturnType<typeof originalJvm>> | undefined;
  let runningOrigin:
    Awaited<ReturnType<typeof createCacheHttpOrigin>> | undefined;
  let runningWorker: Miniflare | undefined;
  let runningServer: ReturnType<typeof createServer> | undefined;
  let browserTimer: ReturnType<typeof setTimeout> | undefined;
  let rejectWait: ((error: Error) => void) | undefined;
  let browserResult: Record<string, unknown> | undefined;
  let finalReport: Record<string, unknown> | undefined;
  let primaryFailure: unknown;
  const resourcePorts: { browser?: number; api?: number; origin?: number } = {};
  const lifecycle = new AbortController();
  const interrupted = () => {
    const error = Error('Cache HTTP gate interrupted');
    // Miniflare's own SIGTERM/SIGINT hook exits synchronously after its cleanup.
    // Preserve this run's terminal failure before yielding to that upstream hook.
    writeFileSync(
      path.join(work, 'browser-report.json'),
      JSON.stringify(
        {
          ...browserResult,
          ...finalReport,
          passed: false,
          error: String(error),
          interrupted: true,
          resourcePorts,
          identity,
          jvm,
          events: runningOrigin?.events ?? [],
        },
        null,
        2,
      ) + '\n',
    );
    lifecycle.abort(error);
    rejectWait?.(error);
  };
  process.on('SIGINT', interrupted);
  process.on('SIGTERM', interrupted);
  try {
    assert(Number.isSafeInteger(port) && port >= 0 && port <= 65535);
    assert(
      Number.isSafeInteger(timeoutMs) &&
        timeoutMs >= 1000 &&
        timeoutMs <= 900000,
    );
    const runtime = await prepareRuntime();
    lifecycle.signal.throwIfAborted();
    jvm = await originalJvm(work, runtime);
    lifecycle.signal.throwIfAborted();
    if (jvmOnly) return;
    const compiled = await teaVm(work, runtime);
    lifecycle.signal.throwIfAborted();
    const [cache, crypto, driver] = await Promise.all([
      compileBridge('cache'),
      compileBridge('crypto'),
      build({
        absWorkingDir: ROOT,
        entryPoints: [
          'packages/runtime-host/test/cache-failure-java-browser-worker.ts',
        ],
        bundle: true,
        format: 'iife',
        platform: 'browser',
        target: 'es2022',
        write: false,
      }),
    ]);
    assert(driver.outputFiles.length === 1);
    const worker = Buffer.concat([
      Buffer.from(
        "self.karuyomiWorkerContext={plugin:'cache-failure-'+crypto.randomUUID()};\n",
      ),
      crypto,
      cache,
      Buffer.from('\n'),
      Buffer.from(driver.outputFiles[0]!.contents),
      compiled.bytes,
      Buffer.from('\nself.main([]);self.cacheFailureRun();\n'),
    ]);
    identity = {
      originalOkHttpSha256: ORIGINAL_SHA,
      workerSha256: hash(worker),
      runnerSha256: hash(await readFile(fileURLToPath(import.meta.url))),
      javaBundleSha256: hash(compiled.bytes),
      javaBundleBytes: compiled.bytes.length,
      cacheBridgeSha256: hash(cache),
      javaScenariosSha256: hash(
        await readFile(
          path.join(
            work,
            'java/src/main/java/prototype/CacheFailureScenarios.java',
          ),
        ),
      ),
    };
    const origin = await createCacheHttpOrigin();
    runningOrigin = origin;
    resourcePorts.origin = origin.port;
    const keys = await generateKeyPair('RS256'),
      jwk = await exportJWK(keys.publicKey);
    jwk.kid = 'cache-failure-fixture';
    const api = await build({
      absWorkingDir: ROOT,
      entryPoints: ['apps/api/test/workerd-entry.ts'],
      bundle: true,
      format: 'esm',
      platform: 'browser',
      target: 'es2022',
      write: false,
    });
    assert(api.outputFiles.length === 1);
    const configuration = unstable_readConfig({
      config: path.join(ROOT, 'apps/api/wrangler.jsonc'),
    });
    assert(
      configuration.compatibility_date,
      'API compatibility date is required',
    );
    const flags = configuration.compatibility_flags;
    assert(
      flags.includes('enable_request_signal'),
      'API must enable client disconnect signals',
    );
    await rm(path.join(work, 'workerd-state'), {
      recursive: true,
      force: true,
    });
    const workerOptions: Parameters<typeof convertV4MiniflareOptions>[0] = {
      modules: true,
      script: api.outputFiles[0]!.text,
      compatibilityDate: configuration.compatibility_date,
      compatibilityFlags: flags,
      resourcePersistencePath: path.join(work, 'workerd-state'),
      d1Databases: { DB: 'cache-failure-fixture' },
      bindings: {
        ACCESS_TEAM_DOMAIN: 'probe.cloudflareaccess.com',
        ACCESS_AUD: 'cache-failure',
        ACCESS_SUBJECT: 'probe-owner',
        OWNER_EMAIL: 'probe@example.com',
        APP_ORIGIN: 'https://read.example.com',
        PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
      },
      outboundService: {
        node: (request, response) =>
          new Promise<void>((resolve) => {
            const target = new URL(
              request.url ?? '/',
              'http://fixture.example.org',
            );
            const outbound = httpRequest(
              {
                hostname: '127.0.0.1',
                port: origin.port,
                path: target.pathname + target.search,
                method: request.method,
                headers: request.headers,
              },
              (upstream) => {
                response.writeHead(
                  upstream.statusCode ?? 502,
                  upstream.headers,
                );
                void pipeline(upstream, response)
                  .catch(() => response.destroy())
                  .finally(resolve);
                response.once('close', () => {
                  upstream.destroy();
                  outbound.destroy();
                  resolve();
                });
              },
            );
            outbound.once('error', () => {
              response.destroy();
              resolve();
            });
            request.once('aborted', () => outbound.destroy());
            request.pipe(outbound);
          }),
      },
    };
    const mf = new Miniflare(convertV4MiniflareOptions(workerOptions));
    runningWorker = mf;
    // Keep the random loopback listener while configuring its exact application
    // origin. Host, Origin and the signed test identity still pass the product checks.
    const endpoint = await mf.ready;
    resourcePorts.api = Number(endpoint.port);
    await mf.setOptions(
      convertV4MiniflareOptions({
        ...workerOptions,
        host: endpoint.hostname,
        port: Number(endpoint.port),
        bindings: { ...workerOptions.bindings, APP_ORIGIN: endpoint.origin },
      }),
    );
    assert.equal((await mf.ready).origin, endpoint.origin);
    const apiEndpoint = new URL('/api/bridge/http', endpoint);
    let backendResets = 0;
    const db = await mf.getD1Database('DB');
    for (const name of (await readdir(path.join(ROOT, 'apps/api/migrations')))
      .filter((name) => name.endsWith('.sql'))
      .sort())
      for (const statement of (
        await readFile(path.join(ROOT, 'apps/api/migrations', name), 'utf8')
      ).split('--> statement-breakpoint'))
        if (statement.trim()) await db.exec(statement.replace(/\n/g, ' '));
    await db
      .prepare(
        'INSERT OR REPLACE INTO extension_builds (build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (?,?,?,?,?,?)',
      )
      .bind(
        'v2-fixture',
        'fixture',
        'a'.repeat(64),
        'verified',
        0,
        '["fixture.example.org"]',
      )
      .run();
    const token = await new SignJWT({ email: 'probe@example.com' })
      .setProtectedHeader({ alg: 'RS256', kid: String(jwk.kid) })
      .setSubject('probe-owner')
      .setIssuer('https://probe.cloudflareaccess.com')
      .setAudience('cache-failure')
      .setIssuedAt()
      .setExpirationTime('30m')
      .sign(keys.privateKey);
    lifecycle.signal.throwIfAborted();
    let finish: (value: Record<string, unknown>) => void = () => {},
      fail: (error: Error) => void = () => {};
    const completed = new Promise<Record<string, unknown>>(
      (resolve, reject) => {
        finish = resolve;
        fail = reject;
      },
    );
    const reportFile = path.join(work, 'browser-report.json');
    await writeFile(
      reportFile,
      JSON.stringify(
        { passed: false, error: 'browser_not_run', identity },
        null,
        2,
      ) + '\n',
    );
    const server = createServer(async (request, response) => {
      try {
        const url = new URL(request.url ?? '/', 'http://127.0.0.1');
        response.setHeader('Cache-Control', 'no-store');
        if (url.pathname === '/worker.js') {
          response.setHeader('Content-Type', 'text/javascript');
          response.end(worker);
          return;
        }
        if (url.pathname === '/api/bridge/http') {
          const abort = new AbortController();
          response.once('close', () => {
            if (!response.writableFinished) abort.abort();
          });
          const headers = new Headers();
          for (const [name, value] of Object.entries(request.headers)) {
            if (Array.isArray(value))
              for (const part of value) headers.append(name, part);
            else if (value !== undefined) headers.set(name, value);
          }
          headers.set('Origin', apiEndpoint.origin);
          headers.set('Cf-Access-Jwt-Assertion', token);
          for (const key of [
            'host',
            'content-length',
            'connection',
            'transfer-encoding',
          ])
            headers.delete(key);
          let cancelBackend: (() => void) | undefined;
          try {
            const result = await new Promise<IncomingMessage>(
              (resolve, reject) => {
                const backend = httpRequest(
                  apiEndpoint,
                  {
                    method: 'POST',
                    headers: Object.fromEntries(headers),
                  },
                  resolve,
                );
                cancelBackend = () => {
                  const socket = backend.socket;
                  if (socket && !socket.destroyed && !socket.connecting) {
                    // Only an actual client disconnect resets this relay's HTTP/1 socket.
                    // This is a local RST gate, not production HTTP/2 or HTTP/3 evidence.
                    backendResets++;
                    socket.resetAndDestroy();
                  } else backend.destroy();
                };
                abort.signal.addEventListener('abort', cancelBackend, {
                  once: true,
                });
                if (abort.signal.aborted) cancelBackend();
                backend.once('error', reject);
                void pipeline(request, backend, { signal: abort.signal }).catch(
                  reject,
                );
              },
            );
            const outgoing = new Headers();
            for (const [name, value] of Object.entries(result.headers)) {
              if (Array.isArray(value))
                for (const item of value) outgoing.append(name, item);
              else if (value !== undefined) outgoing.set(name, value);
            }
            for (const key of [
              'content-length',
              'connection',
              'transfer-encoding',
            ])
              outgoing.delete(key);
            response.writeHead(
              result.statusCode ?? 502,
              Object.fromEntries(outgoing),
            );
            await pipeline(result, response, { signal: abort.signal });
          } finally {
            if (cancelBackend)
              abort.signal.removeEventListener('abort', cancelBackend);
          }
          return;
        }
        if (url.pathname === '/result' && request.method === 'POST') {
          const chunks: Buffer[] = [];
          let size = 0;
          for await (const value of request) {
            const part = Buffer.from(value);
            size += part.length;
            if (size > 65536) throw Error('Browser report exceeds64KiB');
            chunks.push(part);
          }
          const value: unknown = JSON.parse(Buffer.concat(chunks).toString());
          assert(isPlainObject(value) && typeof value.passed === 'boolean');
          response.end('ok', () => finish(value));
          return;
        }
        response.setHeader('Content-Type', 'text/html; charset=utf-8');
        response.end(
          `<!doctype html><title>Shared Java Cache HTTP failures</title><h1>Original JVM / real TeaVM Cache HTTP failures</h1><p>Four deterministic controlled-HTTP cases, 50 shared Java checks. Actual product HTTP v2, CacheInterceptor and IDB/Web Locks. Test RS256 identity, no production Access or Source claim.</p><button>Run shared Java failures</button><pre>pending</pre><script>document.querySelector('button').onclick=()=>{document.querySelector('button').disabled=true;const worker=new Worker('/worker.js');worker.onmessage=async event=>{if(event.data.type!=='cache-failure-result')return;const report={...event.data,userAgent:navigator.userAgent};document.querySelector('pre').textContent=JSON.stringify(report,null,2);await fetch('/result',{method:'POST',body:JSON.stringify(report)});worker.terminate();};worker.onerror=async event=>{const report={passed:false,error:event.message,filename:event.filename,line:event.lineno,column:event.colno};document.querySelector('pre').textContent=JSON.stringify(report,null,2);await fetch('/result',{method:'POST',body:JSON.stringify(report)});worker.terminate();};};</script>`,
        );
      } catch (error) {
        if (!response.headersSent) response.writeHead(500);
        response.destroy(error instanceof Error ? error : undefined);
      }
    });
    runningServer = server;
    rejectWait = fail;
    lifecycle.signal.throwIfAborted();
    browserTimer = setTimeout(() => {
      const error = Error('Cache HTTP browser deadline exceeded');
      lifecycle.abort(error);
      fail(error);
    }, timeoutMs);
    try {
      await new Promise<void>((resolve, reject) => {
        server.once('error', reject);
        server.listen(port, '127.0.0.1', resolve);
      });
      const address = server.address();
      assert(address && typeof address !== 'string');
      resourcePorts.browser = address.port;
      console.log(
        `Open in Codex built-in browser: http://127.0.0.1:${address.port}/`,
      );
      console.log(JSON.stringify(identity));
      const browser = await completed;
      browserResult = browser;
      let upstreamClosed = true;
      let upstreamCloseError: string | undefined;
      try {
        await origin.waitForFailureCloses(5000, lifecycle.signal);
      } catch (error) {
        upstreamClosed = false;
        upstreamCloseError = String(error);
      }
      lifecycle.signal.throwIfAborted();
      const failures = origin.events.filter(
        (event) => event.mode !== 'complete',
      );
      const expectedFailures = [
        { path: '/failure/truncate-empty', mode: 'truncate' },
        { path: '/failure/truncate-replacement', mode: 'truncate' },
        { path: '/failure/cancel-empty', mode: 'cancel' },
        { path: '/failure/cancel-replacement', mode: 'cancel' },
      ];
      const originVerified =
        failures.length === 4 &&
        expectedFailures.every((expected) => {
          const actual = failures.filter(
            (event) =>
              event.path === expected.path && event.mode === expected.mode,
          );
          return (
            actual.length === 1 &&
            actual.every(
              (event) =>
                event.closed &&
                event.advertisedBytes === 131079 &&
                event.writtenBytes === 8192 &&
                (event.mode !== 'truncate' || event.prefixAcknowledged),
            )
          );
        });
      const passed =
        browser.passed === true &&
        browser.checks === 50 &&
        Array.isArray(browser.cases) &&
        browser.cases.length === 4 &&
        browser.cases.every(
          (result) => isPlainObject(result) && result.passed === true,
        ) &&
        isPlainObject(browser.http) &&
        browser.http.open === 0 &&
        browser.http.cancellations === 2 &&
        upstreamClosed &&
        originVerified &&
        backendResets === 2;
      const report = {
        ...browser,
        passed,
        javaSemanticsPassed: browser.passed === true,
        identity,
        jvm,
        events: origin.events,
        realWorkerd: true,
        compatibilityDate: configuration.compatibility_date,
        compatibilityFlags: flags,
        testRS256Identity: true,
        productionAccessVerified: false,
        relay: {
          transport: 'loopback-http1',
          cancellation: 'tcp-reset-on-client-disconnect',
          appOrigin: apiEndpoint.origin,
          backendResets,
        },
        upstreamClosed,
        originVerified,
        upstreamCloseError,
      };
      finalReport = report;
      await writeFile(reportFile, JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify(report, null, 2));
      assert(passed, 'TeaVM shared Cache HTTP failure gate');
    } finally {
      if (browserTimer) clearTimeout(browserTimer);
    }
  } catch (error) {
    primaryFailure = error;
    await writeFile(
      path.join(work, 'browser-report.json'),
      JSON.stringify(
        {
          ...browserResult,
          ...finalReport,
          passed: false,
          error: String(error),
          identity,
          jvm,
          events: runningOrigin?.events ?? [],
        },
        null,
        2,
      ) + '\n',
    );
    throw error;
  } finally {
    if (browserTimer) clearTimeout(browserTimer);
    const server = runningServer;
    const cleanup = await Promise.allSettled([
      ...(server?.listening
        ? [
            new Promise<void>((resolve) => {
              server.closeAllConnections();
              server.close(() => resolve());
            }),
          ]
        : []),
      ...(runningWorker ? [runningWorker.dispose()] : []),
      ...(runningOrigin ? [runningOrigin.close()] : []),
    ]);
    process.removeListener('SIGINT', interrupted);
    process.removeListener('SIGTERM', interrupted);
    const failures = cleanup.filter(
      (result): result is PromiseRejectedResult => result.status === 'rejected',
    );
    if (failures.length) {
      const error = new AggregateError(
        [
          ...(primaryFailure === undefined ? [] : [primaryFailure]),
          ...failures.map((result) => result.reason),
        ],
        'Cache HTTP gate resource cleanup failed',
      );
      await writeFile(
        path.join(work, 'browser-report.json'),
        JSON.stringify(
          {
            ...browserResult,
            ...finalReport,
            passed: false,
            error: String(error),
            identity,
            jvm,
          },
          null,
          2,
        ) + '\n',
      );
      throw error;
    }
  }
}

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      'jvm-only': { type: 'boolean' },
      port: { type: 'string' },
      'timeout-ms': { type: 'string' },
    },
  });
  await checkCacheHttp({
    jvmOnly: values['jvm-only'] ?? false,
    ...(values.port ? { port: Number(values.port) } : {}),
    ...(values['timeout-ms']
      ? { timeoutMs: Number(values['timeout-ms']) }
      : {}),
  });
}
