#!/usr/bin/env node
// Loopback-only live-Source probe. Production entry points never import this.
// Real workerd, policy-only D1, RS256 verification and the product HTTP bridge.
import assert from 'node:assert/strict';
import { unstable_readConfig } from 'wrangler';
import { z } from 'zod';
import { parseManifest } from '../../../tools/extensions/verify-manifest.ts';
import { createHash } from 'node:crypto';
import { execa } from 'execa';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { IncomingMessage } from 'node:http';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { byteStream, relayFrames } from './http-probe-streams.ts';
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
import isRecord from 'is-plain-obj';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sirv from 'sirv';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const api = path.join(root, 'apps/api');
const manifestFile = process.argv[2];
assert(
  manifestFile,
  'Usage: node apps/api/test/source-metadata-probe.ts MANIFEST [ARTIFACT_FOLDER]',
);
const manifestPath = path.resolve(manifestFile);
const manifest = await parseManifest(await readFile(manifestPath));
const selectedSourceId = process.env.SOURCE_PROBE_SOURCE_ID;
assert(
  selectedSourceId === undefined ||
    manifest.sourceIds.includes(selectedSourceId),
  'SOURCE_PROBE_SOURCE_ID must identify a Source in the manifest',
);
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
const verifyImages = process.env.SOURCE_PROBE_IMAGES === '1';
const readerDirectory = process.env.SOURCE_PROBE_READER_DIR
  ? path.resolve(process.env.SOURCE_PROBE_READER_DIR)
  : undefined;
// Use the normal built Flutter app, while retaining this probe's controlled
// static catalog and authenticated HTTP hop. No test UI enters the product.
if (readerDirectory) await readFile(path.join(readerDirectory, 'index.html'));
const readerAssets = readerDirectory
  ? sirv(readerDirectory, { dev: true })
  : undefined;
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
  execa(
    'pnpm',
    ['exec', 'wrangler', ...args, '--local', '--persist-to', state],
    {
      cwd: api,
      env: environment,
      extendEnv: false,
      stdin: 'ignore',
      maxBuffer: 1024 * 1024,
      stripFinalNewline: false,
    },
  );

console.log(
  'Registering current static build network policy in isolated local D1',
);
for (const file of await migrationFiles(api)) {
  await wrangler('d1', 'execute', 'DB', '--file', file, '--yes');
}
await execa(
  process.execPath,
  [
    path.join(root, 'tools/extensions/registration.ts'),
    manifestPath,
    '--local',
    '--persist-to',
    state,
    '--static-root',
    staticRoot,
    ...allowedHosts.flatMap((host) => ['--allow-host', host]),
  ],
  {
    cwd: root,
    env: environment,
    extendEnv: false,
    stdin: 'ignore',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
  },
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
const config = unstable_readConfig(
  { config: path.join(api, 'wrangler.jsonc') },
  { hideWarnings: true },
);
assert(config.compatibility_date, 'Worker compatibility date is required');
const databaseId = z
  .array(z.object({ binding: z.string(), database_id: z.string().optional() }))
  .parse(config.d1_databases)
  .find((database) => database.binding === 'DB')?.database_id;
assert(databaseId, 'D1 database identity missing from Wrangler configuration');
const mf = new Miniflare(
  convertV4MiniflareOptions({
    modules: true,
    script: compiled.outputFiles[0]!.text,
    compatibilityDate: config.compatibility_date,
    compatibilityFlags: config.compatibility_flags,
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
  requestId: string;
  runtimeGeneration: string;
  method: string;
  target: string;
  elapsedMs: number;
  bridgeStatus: number;
  upstreamStatus?: number;
  queryKeys: string[];
  sourceHeaderNames?: string[];
  cookieNames?: string[];
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
const runnerSource = `import '/runtime/host.js';
import {create} from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import {encodeControlRequest,parseControlResponse,runtimeErrorData,messageJson,runtimeHelloSchema,runtimeSessionSchema,plain} from './packages/contracts/src/index.ts';
const runtime = window.karuyomiRuntime;
async function control(command,expected){
  const requestId=crypto.randomUUID();
  const request=create(pb.ControlRequestSchema,{requestId,command});
  const response=parseControlResponse(await runtime.control(encodeControlRequest(request)));
  if(response.requestId!==requestId)throw Error('Control response identity mismatch');
  if(response.result.case==='error'){
    const failure=runtimeErrorData(response.result.value);
    throw Object.assign(Error(failure.message),failure);
  }
  if(response.result.case!==expected)throw Error('Unexpected control result');
  return response.result.value;
}
const output = document.querySelector('#output');
const report = {userAgent:navigator.userAgent, events:[], operations:[], images:[], requiredImages:0, imageGate:${JSON.stringify(verifyImages ? 'pending' : 'not_requested')}, finished:false};
const record = async (event, value) => {
  report.events.push({event,value}); output.textContent = JSON.stringify(report,null,2);
  await fetch('/probe-result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(report)});
};
const failure = error => ({code:error.code ?? 'unknown',name:error.name,message:String(error.message ?? error).slice(0,1400),javaClass:error.javaClass});
const checkImages = async (session, sourceId, pages) => {
  const pageSessionId=pages.pageSessionId;
  const indices=[...new Set([0,Math.floor(pages.pages.length/2),pages.pages.length-1])];
  report.requiredImages=indices.length;
  try {
    if(!pages.pages.length)throw Error('Original Page session is empty');
    for(const index of indices){
      const started=performance.now();
      let resource;
      let image;
      try {
        resource=await control({case:'acquireImage',value:{requestId:crypto.randomUUID(),sourceId,pageSessionId,pageKey:pages.pages[index].pageKey,generation:session.generation,timeoutMs:60000}},'image');
        if(resource.generation!==session.generation||!resource.url.startsWith('blob:'))throw Error('Invalid resource ownership');
        image=new Image(); image.src=resource.url; image.alt='Processed page '+(index+1);
        await image.decode();document.querySelector('#images').append(image);
        if(image.naturalWidth!==resource.width||image.naturalHeight!==resource.height)throw Error('Image dimension descriptor mismatch');
        const summary={index,ok:true,byteLength:resource.byteLength,mimeType:resource.mimeType,width:resource.width,height:resource.height,elapsedMs:Math.round(performance.now()-started)};
        report.images.push(summary);await record('imageDecoded',summary);
      }catch(error){
        const summary={index,ok:false,error:failure(error)};report.images.push(summary);await record('imageFailed',summary);
      }finally{
        if(image){image.remove();image.removeAttribute('src');}
        if(resource){
          const release={resourceId:resource.resourceId,generation:resource.generation};
          await control({case:'releaseImage',value:release},'released');
          await control({case:'releaseImage',value:release},'released');
          let revoked=false;
          try{const response=await fetch(resource.url);revoked=!response.ok;}catch{revoked=true;}
          if(!revoked)throw Error('Released Blob URL remains readable');
          await record('imageReleased',{index,revoked});
        }
      }
    }
  }finally{
    await control({case:'closePageSession',value:{pageSessionId,generation:session.generation}},'closed');
    await record('pageSessionClosed',true);
  }
  if(report.images.length!==report.requiredImages||report.images.some(image=>!image.ok))throw Error('One or more required page images failed');
  report.imageGate='passed';
  await record('imageGatePassed',true);
};
window.addEventListener('unhandledrejection',event=>record('unhandledRejection',failure(event.reason)));
const button = document.querySelector('#run');
try{
  const hello=await control({case:'ready',value:{}},'hello');
  await record('hello',runtimeHelloSchema.parse(messageJson(pb.RuntimeHelloSchema,hello)));
  button.disabled=false;
}catch(error){await record('readyError',failure(error));}
button.onclick = async () => {
  button.disabled = true;
  try {
    const session = await control({case:'open',value:{
      manifestPath:${JSON.stringify(`/extensions/builds/${manifest.buildId}/manifest.json`)},
      identity:'probe-owner', userAgent:navigator.userAgent,
      expectedBuildId:${JSON.stringify(manifest.buildId)}, expectedBundleSha256:${JSON.stringify(manifest.bundle.sha256)}
    }},'session');
    await record('session',runtimeSessionSchema.parse(messageJson(pb.RuntimeSessionSchema,session)));
    const selectedSourceId=${JSON.stringify(selectedSourceId ?? null)};
    const selectedSource=selectedSourceId===null?session.sources[0]:session.sources.find(source=>source.id===selectedSourceId);
    if(!selectedSource)throw Error('Selected Source is not present in the runtime session');
    const sourceId=selectedSource.id;
    await record('selectedSource',{sourceId,name:selectedSource.name,lang:selectedSource.lang});
    const call=async(operation,args)=>{
      const started=performance.now();
      try {
        const requestId=crypto.randomUUID();
        const source=await control({case:'invoke',value:{requestId,sourceId,generation:session.generation,request:{case:operation,value:args},timeoutMs:60000}},'source');
        const expected=operation==='pages'?'pageList':operation==='details'?'manga':operation==='chapters'?'chapters':'mangaPage';
        if(source.requestId!==requestId||source.generation!==session.generation||source.buildId!==session.buildId||source.payload.case!==expected)throw Error('Source result identity or payload mismatch');
        const data=source.payload.value;
        const summary={operation,ok:true,elapsedMs:Math.round(performance.now()-started),keys:Object.keys(plain(data)),...(args.page?{page:args.page}:{}),...(operation==='search'?{query:args.query}:{})};
        if(Array.isArray(data.mangas)){summary.count=data.mangas.length;summary.hasNextPage=data.hasNextPage;summary.firstTitle=data.mangas[0]?.title;}
        if(Array.isArray(data.chapters)){summary.count=data.chapters.length;summary.firstName=data.chapters[0]?.name;}
        if(Array.isArray(data.pages)){
          summary.count=data.pages.length;summary.firstKeys=data.pages[0]?Object.keys(plain(data.pages[0])):[];
          const urls=data.pages.map(page=>page.imageUrl).filter(value=>typeof value==='string'&&URL.canParse(value)).map(value=>new URL(value));
          summary.processingReferences={drmPages:urls.filter(url=>url.hash.startsWith('#drm_data=')).length,tokenPages:urls.filter(url=>url.hash.includes('token')).length,scrambledReferences:urls.filter(url=>url.hash.startsWith('#1;')).length,imageHosts:[...new Set(urls.map(url=>url.hostname))]};
        }
        if(operation==='details'){summary.title=data.title;summary.descriptionLength=data.description?.length??0;summary.genreCount=data.genres.length;}
        report.operations.push(summary);await record('operation',summary);return data;
      }catch(error){const summary={operation,ok:false,elapsedMs:Math.round(performance.now()-started),error:failure(error)};report.operations.push(summary);await record('operation',summary);return null;}
    };
    const popular=await call('popular',{page:1});
    if(popular?.hasNextPage)await call('popular',{page:2});
    const searched=await call('search',{page:1,query:popular?.mangas?.[0]?.title??'a'});
    if(selectedSource.supportsLatest!==false)await call('latest',{page:1});
    else await record('operationSkipped',{operation:'latest',reason:'source_unsupported'});
    const manga=popular?.mangas?.[0]??searched?.mangas?.[0];
    if(manga){
      const details=await call('details',{manga});
      const chapters=await call('chapters',{manga:details??manga});
      if(chapters?.chapters?.[0]){
        const pages=await call('pages',{chapter:chapters.chapters[0]});
        if(${verifyImages}&&pages)await checkImages(session,sourceId,pages);
      }
      else await record('pagesBlocked','No real chapter reference was returned');
    }else await record('referenceOperationsBlocked','No real manga reference was returned; details/chapters/pages were not fabricated');
  }catch(error){await record('openError',failure(error));}
  finally{
    if(report.imageGate==='pending')report.imageGate='failed';
    try{await control({case:'dispose',value:{}},'completed');}
    catch(error){await record('disposeError',failure(error));}
    report.finished=true;await record('finished',true);
  }
};`;
const compiledRunner = await build({
  stdin: { contents: runnerSource, resolveDir: root, loader: 'js' },
  external: ['/runtime/host.js'],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  write: false,
});
const runner = compiledRunner.outputFiles[0]?.text;
assert(runner, 'Expected one compiled browser probe module');
const html = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Karuyomi live Source probe</title>
<style>body{font:14px system-ui;margin:24px;max-width:1000px}pre{white-space:pre-wrap;overflow-wrap:anywhere}button{padding:12px}#images{display:flex;gap:12px;align-items:start}#images img{width:30%;max-height:480px;object-fit:contain;object-position:top}</style>
<h1>Live Source metadata probe</h1>
<p>Loopback only: verified real TeaVM product, direct static gzip assets, policy-only local D1, signed test Access identity and real workerd HTTP bridge. ${verifyImages ? 'First, middle and last page images are acquired through the original Source and the product binary image channel.' : 'No image bytes are requested.'}</p>
<button id="run" disabled>Run real metadata operations</button><div id="images"></div><pre id="output">Loading...</pre>
<script type="module" src="/probe-runner.js"></script></html>`;

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
    if (request.method === 'GET' && pathname === '/probe-runner.js') {
      response
        .writeHead(200, {
          'Content-Type': 'application/javascript',
          'Cache-Control': 'no-store',
        })
        .end(runner);
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
            requestId: descriptor.requestId,
            runtimeGeneration: descriptor.runtimeGeneration,
            method: descriptor.method,
            target: target.origin + target.pathname,
            elapsedMs: 0,
            bridgeStatus: 0,
            queryKeys: [...target.searchParams.keys()],
            sourceHeaderNames: descriptor.headers.map(([name]) =>
              name.toLowerCase(),
            ),
            cookieNames: descriptor.headers
              .filter(([name]) => name.toLowerCase() === 'cookie')
              .flatMap(([, value]) =>
                value
                  .split(';')
                  .map((cookie) => cookie.trim().split('=')[0] ?? ''),
              ),
          };
          if (target.pathname === '/api/catalog/projects')
            entry.catalogQuery = Object.fromEntries(target.searchParams);
          body = relayFrames(requestFrames, descriptor);
        }
        const result = await mf.dispatchFetch(apiOrigin + request.url, {
          method: request.method ?? 'GET',
          headers: Object.fromEntries(headers),
          signal: abort.signal,
          ...(body
            ? {
                body: Readable.fromWeb(body, {
                  highWaterMark: HTTP_FRAME_LIMIT,
                  signal: abort.signal,
                }),
                duplex: 'half',
              }
            : {}),
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
            assert.equal(upstream.requestId, entry.requestId);
            assert.equal(upstream.runtimeGeneration, entry.runtimeGeneration);
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
            Readable.fromWeb(outgoing, {
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
    if (
      request.method === 'GET' &&
      pathname === (readerAssets ? '/probe' : '/')
    ) {
      response
        .writeHead(200, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        })
        .end(html);
      return;
    }
    // Never let a missing runtime/extension/API asset fall through to Flutter.
    if (
      readerAssets &&
      (request.method === 'GET' || request.method === 'HEAD') &&
      !/^\/(?:runtime|extensions|api)(?:\/|$)/.test(pathname)
    ) {
      readerAssets(request, response, () => {
        response.writeHead(404).end();
      });
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
if (readerAssets) {
  console.log(`Flutter reader: http://127.0.0.1:${address.port}/`);
  console.log(`Metadata/image gate: http://127.0.0.1:${address.port}/probe`);
}
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
