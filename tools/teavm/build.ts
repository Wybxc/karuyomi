/** Compile unchanged extension inputs in an explicit disposable work directory. */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execa } from 'execa';
import { unzipSync, zipSync } from 'fflate';
import { sync as writeFileAtomicSync } from 'write-file-atomic';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

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
  const dependencies = readdirSync(path.join(workRoot, 'public/runtime'), {
    recursive: true,
    withFileTypes: true,
  })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
    .map((entry) => path.join(entry.parentPath, entry.name))
    .sort();
  for (const dependency of [...dependencies, jar]) {
    for (const [name, bytes] of Object.entries(
      unzipSync(readFileSync(dependency)),
    )) {
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
  const entries = unzipSync(readFileSync(jar)),
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
        unzipSync(
          readFileSync(path.join(workRoot, 'public/runtime/icu4j-79.1.jar')),
        ),
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
  const classes = readdirSync(source, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.java'))
    .map((entry) =>
      path
        .relative(source, path.join(entry.parentPath, entry.name))
        .split(path.sep)
        .join('/')
        .slice(0, -5),
    );
  const libs = path.join(workRoot, 'java/libs');
  mkdirSync(libs, { recursive: true });
  const dependencies = readdirSync(path.join(workRoot, 'public/runtime'), {
    recursive: true,
    withFileTypes: true,
  })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
    .map((entry) => path.join(entry.parentPath, entry.name))
    .sort();
  for (const dependency of dependencies) {
    const entries = unzipSync(readFileSync(dependency)),
      retained: Record<string, Uint8Array> = {};
    for (const [name, bytes] of Object.entries(entries))
      if (
        !classes.some(
          (className) =>
            name === className + '.class' || name.startsWith(className + '$'),
        )
      )
        retained[name] = bytes;
    writeFileSync(
      path.join(libs, path.basename(dependency)),
      zipSync(retained, { level: 6, mtime: new Date(1980, 0, 1) }),
    );
  }
}

/** Compile bridge classes needed before the java.base compatibility patch. */
export async function compileBridgeBootstrap(
  workRoot: string,
  classpath: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<string> {
  const source = path.join(workRoot, 'java/src/main/java/prototype'),
    classes = path.join(workRoot, 'java/target/classes');
  mkdirSync(classes, { recursive: true });
  await execa(
    'javac',
    [
      '-cp',
      classpath,
      '-d',
      classes,
      ...['Bridge', 'Callbacks', 'JsonValues', 'HttpBodySource'].map((name) =>
        path.join(source, name + '.java'),
      ),
    ],
    {
      cwd: workRoot,
      env,
      extendEnv: false,
      shell: false,
      stdin: 'ignore',
      stdout: 'inherit',
      stderr: 'inherit',
      buffer: false,
      preferLocal: false,
      verbose: 'none',
    },
  );
  return classes;
}

export async function compileExtension(
  options: AotOptions,
): Promise<AotResult> {
  const { workRoot, entry, cache, env } = options,
    sourceRoot = options.sourceRoot ?? ROOT,
    started = performance.now();
  const jar = path.join(workRoot, 'public/extensions', entry.jar),
    source = path.join(workRoot, 'java/src/main/java');
  if (
    createHash('sha256').update(readFileSync(jar)).digest('hex') !==
    entry.convertedSha256
  )
    throw new Error(`Extension input checksum mismatch: ${entry.key}`);
  mkdirSync(cache, { recursive: true });
  generateRegistries(workRoot, source, jar);
  prepareLibraries(workRoot, source);
  const properties = [`-Dextension=${entry.jar}`, `-Dplugin=${entry.key}`];
  if (env['TEAVM_DEBUG']) properties.push('-Dminify=false', '-Ddebug=true');
  const compiler = execa({
    cwd: workRoot,
    env,
    extendEnv: false,
    shell: false,
    stdin: 'ignore',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
    preferLocal: false,
    verbose: 'none',
  });
  const mavenArguments = [
    '-q',
    '-f',
    'java/pom.xml',
    `-Dmaven.repo.local=${path.join(cache, 'm2')}`,
    ...properties,
  ];
  const cpfile = path.join(cache, 'classpath.txt');
  await compiler(options.maven, [
    ...mavenArguments,
    'dependency:build-classpath',
    `-Dmdep.outputFile=${cpfile}`,
  ]);
  let cp = readFileSync(cpfile, 'utf8').trim();
  const tools = path.join(cache, 'tools');
  mkdirSync(tools, { recursive: true });
  await compiler('javac', [
    '-cp',
    cp,
    '-d',
    tools,
    path.join(sourceRoot, 'tools/teavm/PatchLibraries.java'),
  ]);
  await compiler('java', [
    '-cp',
    tools + path.delimiter + cp,
    'PatchLibraries',
    ...readdirSync(path.join(workRoot, 'java/libs'), {
      recursive: true,
      withFileTypes: true,
    })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
      .map((entry) => path.join(entry.parentPath, entry.name))
      .sort(),
  ]);
  const classes = await compileBridgeBootstrap(workRoot, cp, env);
  cp = classes + path.delimiter + cp;
  await compiler('javac', [
    '--patch-module',
    `java.base=${path.join(workRoot, 'java/compat')}`,
    '--add-reads',
    'java.base=ALL-UNNAMED',
    '-cp',
    cp,
    '-d',
    classes,
    ...readdirSync(path.join(workRoot, 'java/compat'), {
      recursive: true,
      withFileTypes: true,
    })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.java'))
      .map((entry) => path.join(entry.parentPath, entry.name))
      .sort(),
  ]);
  await compiler(options.maven, [...mavenArguments, 'package']);
  if (
    createHash('sha256').update(readFileSync(jar)).digest('hex') !==
    entry.convertedSha256
  )
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
  mkdirSync(path.join(workRoot, 'results'), { recursive: true });
  writeFileAtomicSync(
    path.join(workRoot, 'results', `build-${entry.key}.json`),
    JSON.stringify(result, null, 2) + '\n',
  );
  return result;
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const { parseArgs } = await import('node:util');
  const { z } = await import('zod');
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
    .parse(
      JSON.parse(
        readFileSync(path.join(values['work-root'], 'inputs.json'), 'utf8'),
      ),
    )
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
