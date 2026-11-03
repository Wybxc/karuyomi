#!/usr/bin/env node
import { mkdir, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { verifyIntegrity, failure } from './verify-manifest.mjs';

function options(argv) {
  const values = { serve: false, timeoutMs: 90_000 };
  for (let index = 0; index < argv.length; index++) {
    const key = argv[index];
    if (key === '--serve') {
      values.serve = true;
      continue;
    }
    if (
      !['--directory', '--report', '--timeout-ms'].includes(key) ||
      !argv[index + 1]
    )
      throw Error('arguments');
    const value = argv[++index];
    if (key === '--timeout-ms') values.timeoutMs = Number(value);
    else values[key.slice(2)] = path.resolve(value);
  }
  if (
    !values.directory ||
    !values.report ||
    !Number.isInteger(values.timeoutMs) ||
    values.timeoutMs < 1000 ||
    values.timeoutMs > 300_000
  )
    throw Error('arguments');
  const artifactRelative = path.relative(
    path.join(values.directory, 'artifacts'),
    values.report,
  );
  if (
    values.report === path.join(values.directory, 'manifest.json') ||
    (!artifactRelative.startsWith('..') && !path.isAbsolute(artifactRelative))
  )
    throw Error('report_overwrites_input');
  return values;
}

let args;
try {
  args = options(process.argv.slice(2));
} catch {
  console.error(
    'Usage: node tools/extensions/verify-build.mjs --directory DIR --report DIR/validation.json [--serve] [--timeout-ms 90000]',
  );
  process.exit(64);
}
const inputs = await verifyIntegrity(args.directory);
let report = inputs.report;
if (args.serve && inputs.manifest) {
  try {
    const { verifyInBrowser } = await import('./verify-browser.mjs');
    report = await verifyInBrowser(inputs, {
      timeoutMs: args.timeoutMs,
      onListening: (value) => console.error(JSON.stringify(value)),
    });
  } catch (error) {
    report = {
      ...report,
      stages: { ...report.stages, browserLoad: 'failed' },
      failure: failure(error),
    };
  }
}
await mkdir(path.dirname(args.report), { recursive: true });
const temporary = args.report + '.' + randomUUID() + '.tmp';
await writeFile(temporary, JSON.stringify(report, null, 2) + '\n');
await rename(temporary, args.report);
console.log(JSON.stringify(report, null, 2));
process.exitCode = report.valid
  ? 0
  : report.failure?.code === 'browser_not_run'
    ? 2
    : 1;
