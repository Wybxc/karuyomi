import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { isRecord } from './types.ts';
import type { VerifiedInputs, ValidationReport } from './types.ts';
import path from 'node:path';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import {
  completeBrowserValidation,
  digest,
  repositoryRoot,
} from './verify-manifest.ts';

/** Long-lived release validator, without a browser automation dependency.
 * The human/CI opens the URL. Agents controlling a local browser must use CUA.
 * Direct Source networking is blocked by CSP and a rejecting bridge endpoint.
 */
export async function verifyInBrowser(
  inputs: VerifiedInputs,
  {
    timeoutMs = 90_000,
    onListening = console.error,
  }: {
    timeoutMs?: number;
    onListening?: (value: {
      browserValidationUrl: string;
      buildId: string;
      timeoutMs: number;
    }) => void;
  } = {},
): Promise<ValidationReport> {
  const { manifest, manifestBytes, payloads } = inputs;
  const { data: staticMaterials } = await collectMaterials();
  const nonce = randomUUID();
  const runtimeFiles = new Map<string, Buffer>();
  for (const name of ['host.js', 'worker.js']) {
    runtimeFiles.set(
      '/runtime/' + name,
      await readFile(
        path.join(repositoryRoot, 'packages/runtime-host/dist', name),
      ),
    );
  }
  const base = structuredClone(inputs.report);
  base.runtimeHostSha256 = Object.fromEntries(
    [...runtimeFiles].map(([name, bytes]) => [
      path.basename(name),
      digest(bytes),
    ]),
  );
  const manifestPath = `/api/extensions/builds/${encodeURIComponent(manifest.buildId)}/manifest`;
  let networkAttempts = 0;
  let finished = false;
  let origin = '';
  let timer: NodeJS.Timeout | undefined;
  let resolveResult: (report: ValidationReport) => void = () => {
    throw new Error('Validator promise is not initialized');
  };
  const result = new Promise<ValidationReport>(
    (resolve) => (resolveResult = resolve),
  );
  const complete = (report: ValidationReport) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    server.close();
    server.closeAllConnections();
    resolveResult(report);
  };
  const runner = `import '/runtime/host.js';
const output=document.querySelector('pre');
const result={nonce:${JSON.stringify(nonce)},userAgent:navigator.userAgent,indexedDb:false};
async function indexedDbCheck(){
  const name='karuyomi-extension-validator-'+crypto.randomUUID();
  const db=await new Promise((resolve,reject)=>{
    const request=indexedDB.open(name,1);
    request.onupgradeneeded=()=>request.result.createObjectStore('bytes');
    request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
  });
  try{
    await new Promise((resolve,reject)=>{
      const tx=db.transaction('bytes','readwrite');
      tx.objectStore('bytes').put(new Uint8Array([0,255,37]),'sample');
      tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error);tx.onerror=()=>reject(tx.error);
    });
    const value=await new Promise((resolve,reject)=>{
      const request=db.transaction('bytes').objectStore('bytes').get('sample');
      request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);
    });
    if(!(value instanceof Uint8Array)||value.length!==3||value[0]!==0||value[1]!==255||value[2]!==37)throw Error('IndexedDB byte clone mismatch');
  }finally{
    db.close();
    await new Promise((resolve,reject)=>{const request=indexedDB.deleteDatabase(name);request.onsuccess=resolve;request.onerror=()=>reject(request.error);request.onblocked=()=>reject(Error('IndexedDB cleanup blocked'));});
  }
}
try{
  await indexedDbCheck();result.indexedDb=true;
  const manifestResponse=await fetch(${JSON.stringify(manifestPath)},{credentials:'same-origin',cache:'no-store',redirect:'error'});
  if(!manifestResponse.ok)throw Error('Manifest unavailable');
  const manifestBytes=await manifestResponse.arrayBuffer();
  result.manifestSha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',manifestBytes)),value=>value.toString(16).padStart(2,'0')).join('');
  result.buildId=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(manifestBytes)).buildId;
  if(result.manifestSha256!==${JSON.stringify(base.manifestSha256)}||result.buildId!==${JSON.stringify(manifest.buildId)})throw Error('Browser manifest identity mismatch');
  result.hello=await window.karuyomiRuntime.ready;
  result.session=await window.karuyomiRuntime.open({
    manifestPath:${JSON.stringify(manifestPath)},identity:${JSON.stringify('release-validator:' + nonce)},
    expectedBuildId:${JSON.stringify(manifest.buildId)},expectedBundleSha256:${JSON.stringify(manifest.bundle.sha256)},userAgent:navigator.userAgent
  });
}catch(error){result.failure={code:error.code??'browser_init_failed',message:String(error.message??error).slice(0,2000)};}
finally{
  try{await window.karuyomiRuntime?.dispose();}catch(error){result.failure??={code:'dispose_failed',message:String(error.message??error).slice(0,2000)};}
  output.textContent=JSON.stringify(result,null,2);
  const response=await fetch('/validation-result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(result)});
  document.title=response.ok?'Extension validation complete':'Extension validation report rejected';
}`;
  const server = createServer(async (request, response) => {
    try {
      response.setHeader('Cache-Control', 'no-store');
      response.setHeader('X-Content-Type-Options', 'nosniff');
      response.setHeader(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'self' blob: 'wasm-unsafe-eval'; worker-src 'self' blob:; connect-src 'self' blob:; base-uri 'none'; frame-ancestors 'none'",
      );
      const url = new URL(request.url ?? '/', origin);
      const pathname = url.pathname;
      const workerQuery =
        pathname === '/runtime/worker.js' &&
        [...url.searchParams].length === 2 &&
        /^[a-f0-9]{64}$/.test(url.searchParams.get('plugin') ?? '') &&
        url.searchParams.get('plugin') === url.searchParams.get('fsNamespace');
      if (url.origin !== origin || (url.search && !workerQuery) || url.hash) {
        response.writeHead(400).end();
        return;
      }
      if (request.method === 'POST' && pathname === '/validation-result') {
        if (request.headers.origin !== origin) {
          response.writeHead(403).end();
          return;
        }
        const chunks: Buffer[] = [];
        let size = 0;
        for await (const value of request) {
          const chunk = Buffer.isBuffer(value)
            ? value
            : Buffer.from(String(value));
          size += chunk.length;
          if (size > 64 * 1024) throw Error('report_limit');
          chunks.push(chunk);
        }
        const value: unknown = JSON.parse(
          Buffer.concat(chunks).toString('utf8'),
        );
        if (!isRecord(value) || value.nonce !== nonce) {
          response.writeHead(403).end();
          return;
        }
        const report = completeBrowserValidation(base, value, networkAttempts);
        // Install the listener before end(), including for synchronous completion.
        response.on('finish', () => complete(report));
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end(JSON.stringify({ received: true, valid: report.valid }));
        return;
      }
      if (pathname === '/api/bridge/http') {
        ++networkAttempts;
        response
          .writeHead(403, { 'Content-Type': 'application/json' })
          .end('{"error":"release_validation_network_not_allowed"}');
        return;
      }
      if (request.method !== 'GET') {
        response.writeHead(405).end();
        return;
      }
      if (pathname === '/') {
        response
          .writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
          .end(
            '<!doctype html><html><meta charset="utf-8"><title>Extension Worker validation</title><h1>Extension Worker initialization validation</h1><p>Offline release gate: actual verified bundle, real Worker and IndexedDB. Source networking is blocked. This does not test online compatibility.</p><pre>Running...</pre><script type="module" src="/verify-runner.js"></script></html>',
          );
        return;
      }
      if (pathname === '/verify-runner.js') {
        response
          .writeHead(200, { 'Content-Type': 'application/javascript' })
          .end(runner);
        return;
      }
      if (runtimeFiles.has(pathname)) {
        response
          .writeHead(200, { 'Content-Type': 'application/javascript' })
          .end(runtimeFiles.get(pathname));
        return;
      }
      if (pathname === manifestPath) {
        response
          .writeHead(200, { 'Content-Type': 'application/json' })
          .end(manifestBytes);
        return;
      }
      const sharedDigest = /^\/runtime\/materials\/([a-f0-9]{64})$/.exec(
        pathname,
      )?.[1];
      const shared = sharedDigest
        ? staticMaterials.get(sharedDigest)
        : undefined;
      if (shared) {
        response
          .writeHead(200, {
            'Content-Type': shared.contentType,
            'Content-Length': shared.bytes.length,
          })
          .end(shared.bytes);
        return;
      }
      const artifact = payloads.get(pathname);
      if (artifact) {
        response
          .writeHead(200, {
            'Content-Type': artifact.contentType ?? 'application/octet-stream',
            'Content-Length': artifact.size,
          })
          .end(artifact.bytes);
        return;
      }
      if (pathname.startsWith('/api/')) ++networkAttempts;
      response.writeHead(404).end();
    } catch {
      if (!response.headersSent)
        response.writeHead(400, { 'Content-Type': 'application/json' });
      response.end('{"error":"validation_request_failed"}');
    }
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve());
  });
  const address = server.address();
  if (!address || typeof address === 'string')
    throw new Error('Missing validator address');
  origin = `http://127.0.0.1:${address.port}`;
  onListening({
    browserValidationUrl: origin + '/',
    buildId: manifest.buildId,
    timeoutMs,
  });
  timer = setTimeout(
    () =>
      complete({
        ...base,
        stages: {
          ...base.stages,
          browserLoad: 'failed',
          workerInit: 'not_run',
        },
        failure: {
          code: 'browser_timeout',
          message:
            'No complete real-browser Worker validation arrived before the deadline',
        },
      }),
    timeoutMs,
  );
  return result;
}
