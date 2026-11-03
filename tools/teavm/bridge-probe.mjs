#!/usr/bin/env node
/** Loopback-only comparison of the original and product zstd callback bridges. */
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const local = resolve(root, 'runtime/teavm/.local');
const builds = JSON.parse(
  await readFile(resolve(local, 'probes/bridge-build.json'), 'utf8'),
);
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><title>Zstd Java callback regression</title>
<style>body{font:14px/1.4 system-ui;max-width:1000px;margin:24px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}</style>
<h1>Zstd Java callback regression</h1><p>Isolated browser comparison. Actual malformed WASM decode plus an injected rejected host Promise exercise Java fiber errors. Original JAR and release9 source stay unchanged.</p>
<button id="run">Compare frozen and product callbacks</button><pre id="output">Ready</pre>
<script type="module">
const report = { builds: ${JSON.stringify(builds)}, userAgent: navigator.userAgent, results: [] };
const output = document.querySelector('#output');
document.querySelector('#run').onclick = async () => {
  document.querySelector('#run').disabled = true;
  for (const mode of ['baseline', 'fixed']) {
    output.textContent = 'Running '+mode+'...';
    const result = await new Promise(resolve => { const worker = new Worker('/worker.js'); worker.onmessage = ({data}) => {worker.terminate();resolve(data)}; worker.onerror = event => {worker.terminate();resolve({mode,failed:event.message})};worker.postMessage({mode}); });
    report.results.push(result);
  }
  const [baseline, fixed] = report.results;
  report.passed = baseline.rejectedPromise?.kind === 'timeout' && fixed.rejectedPromise?.kind === 'javaError'
    && fixed.rejectedPromise.javaClass === 'java.lang.RuntimeException'
    && fixed.rejectedPromise.message.includes('Injected zstd Promise rejection')
    && baseline.malformed?.kind === 'complete' && fixed.malformed?.kind === 'complete'
    && JSON.parse(baseline.malformed.value).error === JSON.parse(fixed.malformed.value).error;
  output.textContent = JSON.stringify(report,null,2);
  await fetch('/result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(report)});
};
</script></html>`;
const paths = {
  '/worker.js': resolve(root, 'tools/teavm/bridge-probe-worker.js'),
  '/bridge-baseline.js': resolve(local, 'probes/bridge-baseline.js'),
  '/bridge-fixed.js': resolve(local, 'probes/bridge-fixed.js'),
  '/zstd-bridge.js': resolve(root, 'runtime/teavm/bridge/zstd-bridge.js'),
  '/zstd.wasm': resolve(local, 'materials/public/assets/zstd-CV7N7xSg.wasm'),
};
const server = createServer(async (request, response) => {
  try {
    response.setHeader('Cache-Control', 'no-store');
    if (request.method === 'POST' && request.url === '/result') {
      const chunks = [];
      let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 128 * 1024) throw new Error('Result limit');
        chunks.push(chunk);
      }
      const result = JSON.parse(Buffer.concat(chunks).toString());
      await writeFile(
        resolve(local, 'probes/bridge-browser.json'),
        JSON.stringify(result, null, 2) + '\n',
      );
      console.log(
        JSON.stringify({ passed: result.passed, results: result.results }),
      );
      response.writeHead(204).end();
      return;
    }
    if (request.method !== 'GET') {
      response.writeHead(405).end();
      return;
    }
    if (request.url === '/') {
      response.setHeader('Content-Type', 'text/html; charset=utf-8');
      response.end(page);
    } else if (paths[request.url]) {
      response.setHeader(
        'Content-Type',
        request.url.endsWith('.wasm')
          ? 'application/wasm'
          : 'application/javascript',
      );
      response.end(await readFile(paths[request.url]));
    } else response.writeHead(404).end();
  } catch (error) {
    console.error(error);
    response.writeHead(500).end('Probe failed');
  }
});
server.listen(8900, '127.0.0.1', () =>
  console.log('Local zstd probe: http://127.0.0.1:8900/'),
);
