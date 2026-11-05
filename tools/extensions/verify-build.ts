#!/usr/bin/env node
import { mkdir, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { verifyIntegrity } from './verify-manifest.ts';

interface Options {
  directory: string;
  report: string;
}
function options(argv: string[]): Options {
  const values: Partial<Options> = {};
  for (let index = 0; index < argv.length; index++) {
    const key = argv[index];
    if (!key || !['--directory', '--report'].includes(key) || !argv[index + 1])
      throw Error('arguments');
    const value = argv[++index];
    if (value === undefined) throw Error('arguments');
    if (key === '--directory') values.directory = path.resolve(value);
    else values.report = path.resolve(value);
  }
  if (!values.directory || !values.report) throw Error('arguments');
  const artifactRelative = path.relative(
    path.join(values.directory, 'artifacts'),
    values.report,
  );
  if (
    values.report === path.join(values.directory, 'manifest.json') ||
    (!artifactRelative.startsWith('..') && !path.isAbsolute(artifactRelative))
  )
    throw Error('report_overwrites_input');
  return {
    directory: values.directory,
    report: values.report,
  };
}

let args: Options;
try {
  args = options(process.argv.slice(2));
} catch {
  console.error(
    'Usage: node tools/extensions/verify-build.ts --directory DIR --report DIR/validation.json',
  );
  process.exit(64);
}
const inputs = await verifyIntegrity(args.directory);
const report = inputs.report;
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
