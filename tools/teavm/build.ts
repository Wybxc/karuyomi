/** Compile unchanged extension inputs in an explicit disposable work directory. */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { ROOT, files, run } from '../lib/io.ts';
import { digest, writeJson } from '../lib/json.ts';
import { readZip, writeZip } from '../lib/archive.ts';

export interface AotInput {
  key: string;
  packageName: string;
  jar: string;
  convertedSha256: string;
  expectedSources: { id: string; name: string; lang: string }[];
}
export interface AotOptions {
  workRoot: string;
  entry: AotInput;
  maven: string;
  cache: string;
  env: NodeJS.ProcessEnv;
  sourceRoot?: string;
}
export interface AotResult {
  plugin: string;
  bundleKey: string;
  entryPoint: string;
  debug: boolean;
  extensionSha256: string;
  seconds: number;
  bytes: number;
  teavm: string;
  outputSha256?: string;
}

export function generateRegistries(
  workRoot: string,
  source: string,
  jar: string,
): void {
  const types = new Map<string, string>();
  const dependencies = files(path.join(workRoot, 'public/runtime'), '.jar');
  for (const dependency of [...dependencies, jar]) {
    for (const [name, bytes] of Object.entries(readZip(dependency))) {
      if (!name.endsWith('.class')) continue;
      const signature = Buffer.from(bytes)
        .toString('latin1')
        .match(
          /Luy\/kohesive\/injekt\/api\/FullTypeReference<L([^;]+);>;/,
        )?.[1];
      if (signature) {
        const reference = name.slice(0, -6).replaceAll('/', '.'),
          target = signature.replaceAll('/', '.');
        if (types.has(reference) && types.get(reference) !== target)
          throw new Error(`Conflicting AOT type reference: ${reference}`);
        types.set(reference, target);
      }
    }
  }
  const cases = [...types]
    .sort(([a], [b]) => a.localeCompare(b, 'en'))
    .map(
      ([name, target]) =>
        `case ${JSON.stringify(name)}:return ${target.replaceAll('$', '.')}.class;`,
    )
    .join('');
  writeFileSync(
    path.join(source, 'prototype/TypeMap.java'),
    'package prototype;public class TypeMap{public static java.lang.reflect.Type resolve(String n){switch(n){' +
      cases +
      'default:throw new IllegalArgumentException("Unregistered AOT type "+n);}}}',
  );
  const entries = readZip(jar),
    resources = Object.keys(entries).filter(
      (name) => name.startsWith('assets/') && !name.endsWith('/'),
    );
  const usesIcu = Object.entries(entries).some(
    ([name, data]) =>
      name.endsWith('.class') &&
      (Buffer.from(data).includes('android/icu/') ||
        Buffer.from(data).includes('com/ibm/icu/')),
  );
  if (usesIcu)
    resources.push(
      ...Object.keys(
        readZip(path.join(workRoot, 'public/runtime/icu4j-79.1.jar')),
      ).filter(
        (name) =>
          name.startsWith('com/ibm/icu/') &&
          !name.endsWith('.class') &&
          !name.endsWith('/'),
      ),
    );
  writeFileSync(
    path.join(source, 'prototype/ResourceConfig.java'),
    'package prototype;public class ResourceConfig implements org.teavm.extension.spi.resources.ResourcesPolicy{public String[] supplyResources(java.util.Collection<? extends String> names){return new String[]{' +
      [...new Set(resources)]
        .sort()
        .map((name) => JSON.stringify(name))
        .join(',') +
      '};}}',
  );
}

export function prepareLibraries(workRoot: string, source: string): void {
  const classes = files(source, '.java').map((file) =>
    path.relative(source, file).split(path.sep).join('/').slice(0, -5),
  );
  const libs = path.join(workRoot, 'java/libs');
  mkdirSync(libs, { recursive: true });
  for (const dependency of files(
    path.join(workRoot, 'public/runtime'),
    '.jar',
  )) {
    const entries = readZip(dependency),
      retained: Record<string, Uint8Array> = {};
    for (const [name, bytes] of Object.entries(entries))
      if (
        !classes.some(
          (className) =>
            name === className + '.class' || name.startsWith(className + '$'),
        )
      )
        retained[name] = bytes;
    writeZip(path.join(libs, path.basename(dependency)), retained);
  }
}

export async function compileExtension(
  options: AotOptions,
): Promise<AotResult> {
  const { workRoot, entry, cache, env } = options,
    sourceRoot = options.sourceRoot ?? ROOT,
    started = performance.now();
  const jar = path.join(workRoot, 'public/extensions', entry.jar),
    source = path.join(workRoot, 'java/src/main/java');
  if (digest(readFileSync(jar)) !== entry.convertedSha256)
    throw new Error(`Extension input checksum mismatch: ${entry.key}`);
  mkdirSync(cache, { recursive: true });
  generateRegistries(workRoot, source, jar);
  prepareLibraries(workRoot, source);
  const properties = [`-Dextension=${entry.jar}`, `-Dplugin=${entry.key}`];
  if (env['TEAVM_DEBUG']) properties.push('-Dminify=false', '-Ddebug=true');
  const mvn = async (...args: string[]) =>
    await run(
      options.maven,
      [
        '-q',
        '-f',
        'java/pom.xml',
        `-Dmaven.repo.local=${path.join(cache, 'm2')}`,
        ...properties,
        ...args,
      ],
      { cwd: workRoot, env },
    );
  const cpfile = path.join(cache, 'classpath.txt');
  await mvn('dependency:build-classpath', `-Dmdep.outputFile=${cpfile}`);
  let cp = readFileSync(cpfile, 'utf8').trim();
  const tools = path.join(cache, 'tools');
  mkdirSync(tools, { recursive: true });
  await run(
    'javac',
    [
      '-cp',
      cp,
      '-d',
      tools,
      path.join(sourceRoot, 'tools/teavm/PatchLibraries.java'),
    ],
    { cwd: workRoot, env },
  );
  await run(
    'java',
    [
      '-cp',
      tools + path.delimiter + cp,
      'PatchLibraries',
      ...files(path.join(workRoot, 'java/libs'), '.jar'),
    ],
    { cwd: workRoot, env },
  );
  const classes = path.join(workRoot, 'java/target/classes');
  mkdirSync(classes, { recursive: true });
  await run(
    'javac',
    [
      '-cp',
      cp,
      '-d',
      classes,
      ...['Bridge', 'Callbacks', 'JsonValues'].map((name) =>
        path.join(source, 'prototype', name + '.java'),
      ),
    ],
    { cwd: workRoot, env },
  );
  cp = classes + path.delimiter + cp;
  await run(
    'javac',
    [
      '--patch-module',
      `java.base=${path.join(workRoot, 'java/compat')}`,
      '--add-reads',
      'java.base=ALL-UNNAMED',
      '-cp',
      cp,
      '-d',
      classes,
      ...files(path.join(workRoot, 'java/compat'), '.java'),
    ],
    { cwd: workRoot, env },
  );
  await mvn('package');
  if (digest(readFileSync(jar)) !== entry.convertedSha256)
    throw new Error(`Build changed extension input: ${entry.key}`);
  const output = path.join(workRoot, 'public/teavm', entry.key, 'app.js');
  if (!existsSync(output))
    throw new Error('TeaVM did not produce a JavaScript bundle');
  if (!env['TEAVM_DEBUG']) rmSync(output + '.map', { force: true });
  const result: AotResult = {
    plugin: entry.key,
    bundleKey: entry.key,
    entryPoint: 'prototype.TeaHost',
    debug: Boolean(env['TEAVM_DEBUG']),
    extensionSha256: entry.convertedSha256,
    seconds: (performance.now() - started) / 1000,
    bytes: statSync(output).size,
    teavm: '0.16.0',
  };
  writeJson(path.join(workRoot, 'results', `build-${entry.key}.json`), result);
  return result;
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const { parseArgs } = await import('node:util');
  const { z } = await import('zod');
  const { readJson } = await import('../lib/json.ts');
  const { values } = parseArgs({
    args,
    options: {
      'work-root': { type: 'string' },
      key: { type: 'string' },
      cache: { type: 'string' },
      maven: { type: 'string' },
    },
  });
  if (!values['work-root'] || !values.key || !values.cache || !values.maven)
    throw new Error(
      'Usage: build.ts --work-root DIR --key KEY --cache DIR --maven PATH',
    );
  const schema = z.array(
    z.object({
      key: z.string(),
      packageName: z.string(),
      jar: z.string(),
      convertedSha256: z.string().regex(/^[a-f0-9]{64}$/),
      expectedSources: z.array(
        z.object({ id: z.string(), name: z.string(), lang: z.string() }),
      ),
    }),
  );
  const entries = schema
    .parse(readJson(path.join(values['work-root'], 'inputs.json')))
    .filter((entry) => entry.key === values.key);
  const entry = entries[0];
  if (entries.length !== 1 || !entry)
    throw new Error(
      `Expected exactly one input for package key: ${values.key}`,
    );
  console.log(
    JSON.stringify(
      await compileExtension({
        workRoot: path.resolve(values['work-root']),
        entry,
        maven: values.maven,
        cache: path.resolve(values.cache),
        env: process.env,
      }),
    ),
  );
}
if (import.meta.main) await main();
