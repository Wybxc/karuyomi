#!/usr/bin/env node
// Loopback-only live-Source probe. Production entry points never import this.
// Real workerd, D1/R2, RS256 verification and the product HTTP bridge are used.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const api = path.join(root, 'apps/api');
const manifestFile = process.argv[2];
assert(
  manifestFile,
  'Usage: node apps/api/test/source-metadata-probe.mjs MANIFEST',
);
const manifestPath = path.resolve(manifestFile);
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-source-probe-'));
const state = path.join(temporary, 'state');
const evidenceFile = path.join(
  root,
  'runtime/teavm/.local/probes/source-metadata.json',
);
const apiOrigin = 'https://read.example.com';
const environment = {
  ...process.env,
  CLOUDFLARE_SEND_METRICS: 'false',
  WRANGLER_LOG_PATH: path.join(temporary, 'wrangler.log'),
};
const require = createRequire(path.join(api, 'package.json'));
const wranglerRequire = createRequire(require.resolve('wrangler'));
const { build } = await import(wranglerRequire.resolve('esbuild'));
const { Miniflare, convertV4MiniflareOptions } = await import(
  wranglerRequire.resolve('miniflare')
);
const { generateKeyPair, exportJWK, SignJWT } = await import(
  require.resolve('jose')
);
const wrangler = (...args) =>
  execFileSync(
    'pnpm',
    ['exec', 'wrangler', ...args, '--local', '--persist-to', state],
    {
      cwd: api,
      env: environment,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

console.log(
  'Registering the verified product build in isolated local D1/R2 state',
);
for (const name of [
  '0000_special_thing.sql',
  '0001_many_major_mapleleaf.sql',
]) {
  wrangler(
    'd1',
    'execute',
    'DB',
    '--file',
    path.join(api, 'migrations', name),
    '--yes',
  );
}
execFileSync(
  'python3',
  [
    path.join(root, 'scripts/register-build.py'),
    manifestPath,
    '--artifacts',
    path.join(root, 'runtime/teavm/.local/artifacts'),
    '--local',
    '--persist-to',
    state,
    '--allow-host',
    'www.mangadraft.com',
  ],
  { cwd: root, env: environment, stdio: ['ignore', 'pipe', 'pipe'] },
);

const keys = await generateKeyPair('RS256');
const jwk = await exportJWK(keys.publicKey);
jwk.kid = 'isolated-live-source-probe';
const compiled = await build({
  entryPoints: [path.join(api, 'test/workerd-entry.ts')],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  write: false,
});
const databaseId = /"database_id":\s*"([^"]+)"/.exec(
  await readFile(path.join(api, 'wrangler.jsonc'), 'utf8'),
)[1];
const mf = new Miniflare(
  convertV4MiniflareOptions({
    modules: true,
    script: compiled.outputFiles[0].text,
    compatibilityDate: '2026-11-03',
    resourcePersistencePath: path.join(state, 'v3'),
    d1Databases: { DB: databaseId },
    r2Buckets: { ARTIFACTS: 'karuyomi-private' },
    bindings: {
      ACCESS_TEAM_DOMAIN: 'probe.cloudflareaccess.com',
      ACCESS_AUD: 'probe-app',
      ACCESS_SUBJECT: 'probe-owner',
      OWNER_EMAIL: 'probe@example.com',
      APP_ORIGIN: apiOrigin,
      PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
    },
  }),
);
const token = await new SignJWT({ email: 'probe@example.com' })
  .setProtectedHeader({ alg: 'RS256', kid: jwk.kid })
  .setSubject('probe-owner')
  .setIssuer('https://probe.cloudflareaccess.com')
  .setAudience('probe-app')
  .setIssuedAt()
  .setExpirationTime('30m')
  .sign(keys.privateKey);
const network = [];
const evidence = {
  probe: 'live-source-real-workerd',
  buildId: manifest.buildId,
  bundleSha256: manifest.bundle.sha256,
  realRS256Verification: true,
  allowedHosts: ['www.mangadraft.com'],
  productionAccessVerified: false,
  testOnlyOriginAlias: true,
  network,
  browser: null,
};
const persist = async () => {
  await mkdir(path.dirname(evidenceFile), { recursive: true });
  await writeFile(evidenceFile, JSON.stringify(evidence, null, 2) + '\n');
};
const html = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Karuyomi live Source metadata probe</title>
<style>body{font:14px system-ui;margin:24px;max-width:1000px}pre{white-space:pre-wrap;overflow-wrap:anywhere}button{padding:12px}</style>
<h1>Live Source metadata probe</h1>
<p>Loopback only: verified real TeaVM product, local D1/R2, signed test Access identity, real workerd HTTP bridge and live MangaDraft. No image bytes are requested.</p>
<button id="run" disabled>Run real metadata operations</button><pre id="output">Loading...</pre>
<script type="module">
import '/runtime/host.js';
const runtime = window.karuyomiRuntime;
const output = document.querySelector('#output');
const report = {userAgent:navigator.userAgent, events:[], operations:[], finished:false};
const record = async (event, value) => {
  report.events.push({event,value}); output.textContent = JSON.stringify(report,null,2);
  await fetch('/probe-result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(report)});
};
const failure = error => ({code:error.code ?? 'unknown',name:error.name,message:String(error.message ?? error).slice(0,1400),javaClass:error.javaClass});
window.addEventListener('unhandledrejection',event=>record('unhandledRejection',failure(event.reason)));
await record('hello', await runtime.ready);
const button = document.querySelector('#run');button.disabled = false;
button.onclick = async () => {
  button.disabled = true;
  try {
    const session = await runtime.open({
      manifestPath:${JSON.stringify(`/api/extensions/builds/${manifest.buildId}/manifest`)},
      identity:'probe-owner', userAgent:navigator.userAgent,
      expectedBuildId:${JSON.stringify(manifest.buildId)}, expectedBundleSha256:${JSON.stringify(manifest.bundle.sha256)}
    });
    await record('session',session);
    const sourceId=session.sources[0].id;
    const call=async(operation,args)=>{
      const started=performance.now();
      try {
        const {data}=await runtime.invoke({requestId:crypto.randomUUID(),sourceId,operation,args,timeoutMs:60000});
        const summary={operation,ok:true,elapsedMs:Math.round(performance.now()-started),keys:Object.keys(data),...(args.page?{page:args.page}:{}),...(operation==='search'?{query:args.query}:{})};
        if(Array.isArray(data.mangas)){summary.count=data.mangas.length;summary.hasNextPage=data.hasNextPage;summary.firstTitle=data.mangas[0]?.title;}
        if(Array.isArray(data.chapters)){summary.count=data.chapters.length;summary.firstName=data.chapters[0]?.name;}
        if(Array.isArray(data.pages)){summary.count=data.pages.length;summary.firstKeys=data.pages[0]?Object.keys(data.pages[0]):[];}
        if(operation==='details'){summary.title=data.title;summary.descriptionLength=data.description?.length??0;summary.genreCount=data.genres?.length??0;}
        report.operations.push(summary);await record('operation',summary);return data;
      }catch(error){const summary={operation,ok:false,elapsedMs:Math.round(performance.now()-started),error:failure(error)};report.operations.push(summary);await record('operation',summary);return null;}
    };
    const popular=await call('popular',{page:1});
    if(popular?.hasNextPage)await call('popular',{page:2});
    const searched=await call('search',{page:1,query:popular?.mangas?.[0]?.title??'a'});
    if(session.sources[0].supportsLatest!==false)await call('latest',{page:1});
    const manga=popular?.mangas?.[0]??searched?.mangas?.[0];
    if(manga){
      const details=await call('details',{manga});
      const chapters=await call('chapters',{manga:details??manga});
      if(chapters?.chapters?.[0])await call('pages',{chapter:chapters.chapters[0]});
      else await record('pagesBlocked','No real chapter reference was returned');
    }else await record('referenceOperationsBlocked','No real manga reference was returned; details/chapters/pages were not fabricated');
  }catch(error){await record('openError',failure(error));}
  finally{report.finished=true;await runtime.dispose();await record('finished',true);}
};
</script></html>`;

async function readBody(request, limit = 12 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) throw new Error('probe_request_limit');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (request.method === 'POST' && pathname === '/probe-result') {
      evidence.browser = JSON.parse(
        (await readBody(request, 128 * 1024)).toString(),
      );
      await persist();
      console.log(JSON.stringify(evidence.browser.events.at(-1)));
      response.writeHead(204).end();
      return;
    }
    if (pathname.startsWith('/api/')) {
      const body = await readBody(request);
      const headers = new Headers(request.headers);
      headers.set('Cf-Access-Jwt-Assertion', token);
      headers.set('Origin', apiOrigin);
      headers.delete('host');
      headers.delete('content-length');
      const started = performance.now();
      const result = await mf.dispatchFetch(apiOrigin + request.url, {
        method: request.method,
        headers,
        ...(body.length ? { body } : {}),
      });
      const bytes = Buffer.from(await result.arrayBuffer());
      if (pathname === '/api/bridge/http') {
        const descriptor = JSON.parse(body.toString());
        const upstream = JSON.parse(bytes.toString());
        const entry = {
          method: descriptor.method,
          target:
            new URL(descriptor.url).origin + new URL(descriptor.url).pathname,
          elapsedMs: Math.round(performance.now() - started),
          bridgeStatus: result.status,
          upstreamStatus: upstream.status,
        };
        const target = new URL(descriptor.url);
        entry.queryKeys = [...target.searchParams.keys()];
        // Only this public catalog request is inspected; never record Source
        // cookies, authorization or signed image query strings.
        if (target.pathname === '/api/catalog/projects') {
          entry.catalogQuery = Object.fromEntries(target.searchParams);
        }
        if (upstream.error) entry.bridgeError = upstream.error;
        if (upstream.body) {
          const data = Buffer.from(upstream.body, 'base64');
          entry.bodyBytes = data.length;
          entry.bodySha256 = createHash('sha256').update(data).digest('hex');
          entry.contentType = upstream.headers?.find(
            ([name]) => name.toLowerCase() === 'content-type',
          )?.[1];
          if (entry.contentType?.includes('text/html')) {
            const text = data.toString();
            entry.htmlTitle = /<title[^>]*>([^<]*)<\/title>/i
              .exec(text)?.[1]
              ?.slice(0, 120);
            entry.challengeDetected =
              /cf-chl-|challenge-platform|Just a moment|bot-verification|Human Verification/i.test(
                text,
              );
          }
        }
        network.push(entry);
        await persist();
        console.log(JSON.stringify(entry));
      }
      response.writeHead(result.status, Object.fromEntries(result.headers));
      response.end(bytes);
      return;
    }
    if (request.method === 'GET' && pathname === '/') {
      response
        .writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        })
        .end(html);
      return;
    }
    if (
      request.method === 'GET' &&
      ['/runtime/host.js', '/runtime/worker.js'].includes(pathname)
    ) {
      response.writeHead(200, {
        'Content-Type': 'application/javascript',
        'Cache-Control': 'no-store',
      });
      response.end(
        await readFile(
          path.join(
            root,
            'packages/runtime-host/dist',
            path.basename(pathname),
          ),
        ),
      );
      return;
    }
    response.writeHead(404).end();
  } catch (error) {
    console.error(error);
    if (!response.headersSent)
      response.writeHead(500, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ error: 'probe_failed' }));
  }
});
await new Promise((resolve) =>
  server.listen(
    Number(process.env.SOURCE_PROBE_PORT ?? 8897),
    '127.0.0.1',
    resolve,
  ),
);
console.log(
  `Live Source metadata probe: http://127.0.0.1:${server.address().port}/`,
);
console.log(`Evidence: ${evidenceFile}`);
let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  server.close();
  await mf.dispose();
  await rm(temporary, { recursive: true, force: true });
  process.exit(0);
}
process.on('SIGINT', () => void close());
process.on('SIGTERM', () => void close());
