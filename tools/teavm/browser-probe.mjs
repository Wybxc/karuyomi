#!/usr/bin/env node
/** Isolated loopback development harness; never mount this in the product API. */
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const local = resolve(root, 'runtime/teavm/.local');
const manifestFile = process.argv[2];
if (!manifestFile) {
  throw new Error(
    'Usage: node tools/teavm/browser-probe.mjs <local product manifest>',
  );
}
const manifest = JSON.parse(await readFile(resolve(manifestFile), 'utf8'));
const manifestPath = `/api/extensions/builds/${encodeURIComponent(manifest.buildId)}/manifest`;
const artifacts = new Map();
for (const artifact of [
  manifest.bundle,
  ...manifest.hostScripts,
  ...manifest.resources,
]) {
  if (
    !/^[a-f0-9]{64}$/.test(artifact.sha256) ||
    artifact.path !== `/api/extensions/artifacts/${artifact.sha256}`
  ) {
    throw new Error('Invalid artifact identity');
  }
  const data = await readFile(resolve(local, 'artifacts', artifact.sha256));
  if (
    data.byteLength !== artifact.size ||
    createHash('sha256').update(data).digest('hex') !== artifact.sha256
  ) {
    throw new Error('Artifact integrity check failed');
  }
  artifacts.set(artifact.path, { data, contentType: artifact.contentType });
}
const page = `<!doctype html><html lang="en"><meta charset="utf-8">
<title>Karuyomi local TeaVM initialization probe</title>
<style>body{font:14px/1.4 system-ui;max-width:900px;margin:24px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}button{margin-right:8px}</style>
<h1>Local TeaVM initialization probe</h1>
<p>Development only: loopback server, no Access session, no upstream HTTP relay.</p>
<button id="open" disabled>Open verified MangaDraft build</button>
<button id="references" disabled>Check explicit reference rejection</button>
<pre id="output">Loading runtime host...</pre>
<script type="module">
import '/runtime/host.js';
const output = document.querySelector('#output');
const report = { buildId: ${JSON.stringify(manifest.buildId)}, userAgent: navigator.userAgent, events: [] };
function record(event, value) {
  report.events.push({ event, value });
  output.textContent = JSON.stringify(report, null, 2);
  fetch('/probe-result', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(report) }).catch(() => {});
}
function failure(error) { return { code: error.code, message: error.message, name: error.name }; }
window.addEventListener('error', event => record('windowError', event.message));
window.addEventListener('unhandledrejection', event => record('unhandledRejection', failure(event.reason)));
const runtime = window.karuyomiRuntime;
record('hello', await runtime.ready);
document.querySelector('#open').disabled = false;
document.querySelector('#open').onclick = async () => {
  document.querySelector('#open').disabled = true;
  record('opening', ${JSON.stringify(manifest.buildId)});
  try {
    const session = await runtime.open({ manifestPath: ${JSON.stringify(manifestPath)}, identity: 'isolated-local-browser-probe', userAgent: navigator.userAgent });
    record('session', session);
    document.querySelector('#references').disabled = false;
    document.querySelector('#references').onclick = async () => {
      try {
        const value = await runtime.invoke({ requestId: crypto.randomUUID(), sourceId: session.sources[0].id, operation: 'pages', args: {}, timeoutMs: 15000 });
        record('unexpectedReferenceSuccess', value);
      } catch (error) {
        record('referenceRejection', failure(error));
      }
    };
  } catch (error) { record('openError', failure(error)); }
};
</script></html>`;
const server = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, 'http://localhost').pathname;
    response.setHeader('Cache-Control', 'no-store');
    if (request.method === 'POST' && path === '/probe-result') {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 128 * 1024) throw new Error('Probe report too large');
        chunks.push(chunk);
      }
      const report = JSON.parse(Buffer.concat(chunks).toString());
      await mkdir(resolve(local, 'probes'), { recursive: true });
      await writeFile(
        resolve(local, 'probes/browser-init.json'),
        JSON.stringify(report, null, 2) + '\n',
      );
      console.log(JSON.stringify(report.events.at(-1)));
      response.writeHead(204).end();
      return;
    }
    if (request.method !== 'GET') {
      response.writeHead(405).end();
      return;
    }
    if (path === '/') {
      response.setHeader('Content-Type', 'text/html; charset=utf-8');
      response.end(page);
    } else if (path === manifestPath) {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(manifest));
    } else if (artifacts.has(path)) {
      const artifact = artifacts.get(path);
      response.setHeader(
        'Content-Type',
        artifact.contentType ?? 'application/octet-stream',
      );
      response.end(artifact.data);
    } else if (path === '/runtime/host.js' || path === '/runtime/worker.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(
        await readFile(
          resolve(root, 'packages/runtime-host/dist', path.split('/').at(-1)),
        ),
      );
    } else {
      response.writeHead(404).end();
    }
  } catch (error) {
    console.error(error.message);
    response.writeHead(500).end('Probe failed');
  }
});
server.listen(Number(process.env.PROBE_PORT ?? 8898), '127.0.0.1', () => {
  console.log(
    `Local development probe: http://127.0.0.1:${server.address().port}/`,
  );
});
