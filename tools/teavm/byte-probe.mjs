#!/usr/bin/env node
/** Development-only byte oracle server, deliberately bound to loopback. */
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const probe = resolve(root, 'runtime/teavm/.local/probes');
const build = JSON.parse(
  await readFile(resolve(probe, 'byte-build.json'), 'utf8'),
);
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><title>TeaVM byte and fiber probe</title>
<style>body{font:14px/1.4 system-ui;max-width:1000px;margin:24px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}</style>
<h1>TeaVM 0.16.0 byte and fiber probe</h1><p>Independent development oracle. No Source, HTTP, Base64, filesystem, or product bridge.</p>
<button id="run">Run byte, fiber and ownership checks</button><pre id="output">Ready</pre>
<script type="module">
const output = document.querySelector('#output');
const report = { userAgent: navigator.userAgent, build: ${JSON.stringify(build)} };
const hash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2,'0')).join('');
document.querySelector('#run').onclick = async () => {
  document.querySelector('#run').disabled = true;
  output.textContent = 'Running in dedicated Worker...';
  const worker = new Worker('/worker.js');
  const bytes = crypto.getRandomValues(new Uint8Array(65536));
  const sha256 = await hash(bytes);
  let transferResult;
  worker.onmessage = async ({ data }) => {
    if (data.type === 'transfer') { transferResult = hash(data.bytes).then(value => ({ correct: value === sha256, bytes: data.bytes.length, sha256: value })); return; }
    if (data.type !== 'result') return;
    report.result = data.result;
    report.outputTransfer = await transferResult;
    report.passed = Boolean(data.result.passed && report.inputDetached && report.outputTransfer?.correct);
    output.textContent = JSON.stringify(report, null, 2);
    await fetch('/result', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(report) });
    worker.terminate();
  };
  worker.onerror = event => { output.textContent = event.message; worker.terminate(); };
  worker.postMessage({ type: 'run', bytes, sha256 }, [bytes.buffer]);
  report.inputDetached = bytes.byteLength === 0 && bytes.buffer.byteLength === 0;
};
</script></html>`;
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
      const report = JSON.parse(Buffer.concat(chunks).toString());
      await writeFile(
        resolve(probe, 'byte-browser.json'),
        JSON.stringify(report, null, 2) + '\n',
      );
      console.log(
        JSON.stringify({
          passed: report.passed,
          cancellation: report.result?.cancellation,
          timings: report.result?.timings,
        }),
      );
      response.writeHead(204).end();
      return;
    }
    if (request.method !== 'GET') {
      response.writeHead(405).end();
      return;
    }
    const files = {
      '/worker.js': resolve(root, 'tools/teavm/byte-probe-worker.js'),
      '/byte-probe.js': resolve(probe, 'byte-probe.js'),
    };
    if (request.url === '/') {
      response.setHeader('Content-Type', 'text/html; charset=utf-8');
      response.end(page);
    } else if (files[request.url]) {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(await readFile(files[request.url]));
    } else response.writeHead(404).end();
  } catch (error) {
    console.error(error);
    response.writeHead(500).end('Probe failed');
  }
});
server.listen(8899, '127.0.0.1', () =>
  console.log('Local byte probe: http://127.0.0.1:8899/'),
);
