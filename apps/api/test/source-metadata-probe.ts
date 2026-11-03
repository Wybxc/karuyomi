#!/usr/bin/env node
// Loopback-only live-Source probe. Production entry points never import this.
// Real workerd, policy-only D1, RS256 verification and the product HTTP bridge.
import assert from 'node:assert/strict';
import { parseManifest } from '../../../tools/extensions/verify-manifest.ts';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { IncomingMessage } from 'node:http';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { byteStream, relayFrames, streamChunks } from './http-probe-streams.ts';
import {
  createStaticSnapshot,
  migrationFiles,
  staticProbeFile,
} from './static-extension-probe.ts';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  HttpFrameError,
  httpRequestMetaSchema,
  httpResponseMetaSchema,
} from '../../../packages/contracts/src/http-frames.ts';
import { collectMaterials } from '../../../packages/runtime-host/materials.ts';
import { isRecord } from '../../../tools/extensions/types.ts';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const api = path.join(root, 'apps/api');
const manifestFile = process.argv[2];
assert(
  manifestFile,
  'Usage: node apps/api/test/source-metadata-probe.ts MANIFEST [ARTIFACT_FOLDER]',
);
const manifestPath = path.resolve(manifestFile);
const manifest = await parseManifest(await readFile(manifestPath));
const artifactFolder = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(path.dirname(manifestPath), 'artifacts');
const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-source-probe-'));
const state = path.join(temporary, 'state');
const staticRoot = await createStaticSnapshot(
  path.join(temporary, 'public'),
  manifest,
  artifactFolder,
  await readFile(manifestPath),
);
const evidenceFile = process.env.SOURCE_PROBE_EVIDENCE
  ? path.resolve(process.env.SOURCE_PROBE_EVIDENCE)
  : path.join(root, 'runtime/teavm/.local/probes/source-metadata.json');
const allowedHosts = (
  process.env.SOURCE_PROBE_ALLOWED_HOSTS ?? 'www.mangadraft.com'
)
  .split(',')
  .map((host) => host.trim())
  .filter(Boolean);
assert(allowedHosts.length > 0, 'Explicit Source allowed hosts are required');
const apiOrigin = 'https://read.example.com';
const environment = {
  ...process.env,
  CLOUDFLARE_SEND_METRICS: 'false',
  WRANGLER_LOG_PATH: path.join(temporary, 'wrangler.log'),
};
const require = createRequire(path.join(api, 'package.json'));
const wranglerRequire = createRequire(require.resolve('wrangler'));
const { build }: typeof import('esbuild') = await import(
  wranglerRequire.resolve('esbuild')
);
const { Miniflare, convertV4MiniflareOptions }: typeof import('miniflare') =
  await import(wranglerRequire.resolve('miniflare'));
const { generateKeyPair, exportJWK, SignJWT }: typeof import('jose') =
  await import(require.resolve('jose'));
const wrangler = (...args: string[]) =>
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
  'Registering current static build network policy in isolated local D1',
);
for (const file of await migrationFiles(api)) {
  wrangler('d1', 'execute', 'DB', '--file', file, '--yes');
}
execFileSync(
  'python3',
  [
    path.join(root, 'scripts/register-build.py'),
    manifestPath,
    '--artifacts',
    artifactFolder,
    '--local',
    '--persist-to',
    state,
    '--static-root',
    staticRoot,
    ...allowedHosts.flatMap((host) => ['--allow-host', host]),
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
assert(
  compiled.outputFiles.length === 1,
  'Expected one compiled Worker module',
);
const databaseId = /"database_id":\s*"([^"]+)"/.exec(
  await readFile(path.join(api, 'wrangler.jsonc'), 'utf8'),
)?.[1];
assert(databaseId, 'D1 database identity missing from Wrangler configuration');
const mf = new Miniflare(
  convertV4MiniflareOptions({
    modules: true,
    script: compiled.outputFiles[0]!.text,
    compatibilityDate: '2026-11-03',
    resourcePersistencePath: path.join(state, 'v3'),
    d1Databases: { DB: databaseId },
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
  .setProtectedHeader({ alg: 'RS256', kid: String(jwk.kid) })
  .setSubject('probe-owner')
  .setIssuer('https://probe.cloudflareaccess.com')
  .setAudience('probe-app')
  .setIssuedAt()
  .setExpirationTime('30m')
  .sign(keys.privateKey);
interface NetworkEntry {
  method: string;
  target: string;
  elapsedMs: number;
  bridgeStatus: number;
  upstreamStatus?: number;
  queryKeys: string[];
  catalogQuery?: Record<string, string>;
  bridgeError?: string;
  bodyBytes?: number;
  bodySha256?: string;
  contentType?: string;
  htmlTitle?: string;
  challengeDetected?: boolean;
}
const { data: materials } = await collectMaterials();
const network: NetworkEntry[] = [];
interface LiveEvidence {
  probe: string;
  buildId: string;
  bundleSha256: string;
  realRS256Verification: boolean;
  allowedHosts: string[];
  productionAccessVerified: boolean;
  testOnlyOriginAlias: boolean;
  network: NetworkEntry[];
  browser: unknown;
}
const evidence: LiveEvidence = {
  probe: 'live-source-real-workerd',
  buildId: manifest.buildId,
  bundleSha256: manifest.bundle.sha256,
  realRS256Verification: true,
  allowedHosts,
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
<p>Loopback only: verified real TeaVM product, direct static gzip assets, policy-only local D1, signed test Access identity and real workerd HTTP bridge. No image bytes are requested.</p>
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
      manifestPath:${JSON.stringify(`/extensions/builds/${manifest.buildId}/manifest.json`)},
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
    else await record('operationSkipped',{operation:'latest',reason:'source_unsupported'});
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

async function readBody(request: IncomingMessage, limit = 12 * 1024 * 1024) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const value of request) {
    const chunk = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
    size += chunk.length;
    if (size > limit) throw new Error('probe_request_limit');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
    if (request.method === 'POST' && pathname === '/probe-result') {
      evidence.browser = JSON.parse(
        (await readBody(request, 128 * 1024)).toString(),
      );
      await persist();
      const browser = evidence.browser;
      if (isRecord(browser) && Array.isArray(browser.events))
        console.log(JSON.stringify(browser.events.at(-1)));
      response.writeHead(204).end();
      return;
    }
    const staticFile = await staticProbeFile(staticRoot, pathname, manifest);
    if (request.method === 'GET' && staticFile) {
      response
        .writeHead(200, {
          'Content-Type': staticFile.contentType,
          'Content-Length': staticFile.bytes.length,
          'Cache-Control': 'no-store',
        })
        .end(staticFile.bytes);
      return;
    }
    if (pathname.startsWith('/api/')) {
      const abort = new AbortController();
      const disconnect = () =>
        abort.abort(new Error('probe_client_disconnected'));
      const responseClosed = () => {
        if (!response.writableFinished) disconnect();
      };
      request.once('aborted', disconnect);
      response.once('close', responseClosed);
      let requestFrames: HttpFrameReader | undefined;
      let responseFrames: HttpFrameReader | undefined;
      try {
        const headers = new Headers();
        for (const [key, value] of Object.entries(request.headers)) {
          if (value !== undefined)
            for (const item of Array.isArray(value) ? value : [value])
              headers.append(key, item);
        }
        headers.set('Cf-Access-Jwt-Assertion', token);
        headers.set('Origin', apiOrigin);
        // This controls only the loopback-to-workerd hop. Source headers remain
        // inside META and are preserved by the product bridge.
        headers.set('Accept-Encoding', 'identity');
        for (const name of [
          'host',
          'content-length',
          'connection',
          'transfer-encoding',
        ])
          headers.delete(name);
        const hasBody = !['GET', 'HEAD'].includes(request.method ?? 'GET');
        let body = hasBody ? byteStream(Readable.toWeb(request)) : undefined;
        let entry: NetworkEntry | undefined;
        const started = performance.now();
        if (
          pathname === '/api/bridge/http' &&
          headers.get('content-type') === HTTP_BRIDGE_MEDIA_TYPE
        ) {
          requestFrames = new HttpFrameReader(body!, HTTP_REQUEST_BODY_LIMIT);
          const descriptor = httpRequestMetaSchema.parse(
            await requestFrames.meta(),
          );
          const target = new URL(descriptor.url);
          entry = {
            method: descriptor.method,
            target: target.origin + target.pathname,
            elapsedMs: 0,
            bridgeStatus: 0,
            queryKeys: [...target.searchParams.keys()],
          };
          if (target.pathname === '/api/catalog/projects')
            entry.catalogQuery = Object.fromEntries(target.searchParams);
          body = relayFrames(requestFrames, descriptor);
        }
        const result = await mf.dispatchFetch(apiOrigin + request.url, {
          method: request.method ?? 'GET',
          headers: Object.fromEntries(headers),
          signal: abort.signal,
          ...(body ? { body: streamChunks(body), duplex: 'half' } : {}),
        });
        let outgoing = result.body ? byteStream(result.body) : null;
        if (entry) {
          entry.bridgeStatus = result.status;
          if (
            result.headers.get('content-type') === HTTP_BRIDGE_MEDIA_TYPE &&
            outgoing
          ) {
            responseFrames = new HttpFrameReader(
              outgoing,
              HTTP_RESPONSE_BODY_LIMIT,
            );
            const upstream = httpResponseMetaSchema.parse(
              await responseFrames.meta(),
            );
            entry.upstreamStatus = upstream.upstreamStatus;
            const contentType = upstream.headers.find(
              ([name]) => name.toLowerCase() === 'content-type',
            )?.[1];
            if (contentType !== undefined) entry.contentType = contentType;
            const hash = createHash('sha256');
            let size = 0;
            // A bounded HTML prefix is sufficient for diagnostic titles and
            // common challenge markers; no complete Source body is retained.
            const htmlPrefix = Buffer.alloc(8192);
            let prefixSize = 0;
            const current = entry;
            outgoing = relayFrames(
              responseFrames,
              upstream,
              (data) => {
                hash.update(data);
                size += data.byteLength;
                if (
                  current.contentType?.includes('text/html') &&
                  prefixSize < htmlPrefix.length
                ) {
                  const part = data.subarray(0, htmlPrefix.length - prefixSize);
                  htmlPrefix.set(part, prefixSize);
                  prefixSize += part.byteLength;
                }
              },
              async (error) => {
                current.elapsedMs = Math.round(performance.now() - started);
                current.bodyBytes = size;
                current.bodySha256 = hash.digest('hex');
                if (error)
                  current.bridgeError =
                    error instanceof HttpFrameError
                      ? error.code
                      : 'probe_stream_failed';
                if (prefixSize) {
                  const text = htmlPrefix.subarray(0, prefixSize).toString();
                  const title = /<title[^>]*>([^<]*)<\/title>/i
                    .exec(text)?.[1]
                    ?.slice(0, 120);
                  if (title !== undefined) current.htmlTitle = title;
                  current.challengeDetected =
                    /cf-chl-|challenge-platform|Just a moment|bot-verification|Human Verification/i.test(
                      text,
                    );
                }
                network.push(current);
                await persist();
                console.log(JSON.stringify(current));
              },
            );
          } else {
            entry.elapsedMs = Math.round(performance.now() - started);
            entry.bridgeError = 'bridge_rejected';
            network.push(entry);
            await persist();
            console.log(JSON.stringify(entry));
          }
        }
        const outgoingHeaders = new Headers(Array.from(result.headers));
        for (const name of [
          'content-length',
          'transfer-encoding',
          'connection',
        ])
          outgoingHeaders.delete(name);
        response.writeHead(result.status, Object.fromEntries(outgoingHeaders));
        if (outgoing)
          await pipeline(
            Readable.from(streamChunks(outgoing), {
              objectMode: false,
              highWaterMark: HTTP_FRAME_LIMIT,
            }),
            response,
            { signal: abort.signal },
          );
        else response.end();
      } finally {
        request.off('aborted', disconnect);
        response.off('close', responseClosed);
        await Promise.allSettled([
          requestFrames?.cancel(),
          responseFrames?.cancel(),
        ]);
      }
      return;
    }
    const materialSha256 = /^\/runtime\/materials\/([a-f0-9]{64})$/.exec(
      pathname,
    )?.[1];
    const material = materialSha256 ? materials.get(materialSha256) : undefined;
    if (request.method === 'GET' && material) {
      response
        .writeHead(200, {
          'Content-Type': material.contentType,
          'Cache-Control': 'no-store',
          'Content-Length': material.bytes.length,
        })
        .end(material.bytes);
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
    if (!response.headersSent) {
      response.writeHead(500, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: 'probe_failed' }));
    } else response.destroy();
  }
});
await new Promise<void>((resolve) =>
  server.listen(
    Number(process.env.SOURCE_PROBE_PORT ?? 8897),
    '127.0.0.1',
    () => resolve(),
  ),
);
const address = server.address();
assert(address && typeof address !== 'string', 'Missing Source probe address');
console.log(`Live Source metadata probe: http://127.0.0.1:${address.port}/`);
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
