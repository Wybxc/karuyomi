/** Build an unchanged official extension JAR with the fixed project-owned host. */
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { z } from 'zod';
import { buildManifestSchema } from '../../packages/contracts/src/index.ts';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import { ROOT, files, run } from '../lib/io.ts';
import {
  canonical,
  digest,
  readJson,
  writeJson,
  isRecord,
} from '../lib/json.ts';
import { prepareRuntime, LOCK } from '../teavm/runtime.ts';
import { prepareSources } from '../teavm/upstream-sources.ts';
import {
  dependencies,
  git,
  hostFingerprint,
  treeHash,
  SHARED_PATHS,
} from './catalog.ts';
import { extensionDescriptorSchema } from './model.ts';
import type { ExtensionDescriptor } from './model.ts';
import { encodeBundle } from './assets.ts';

const sourceSchema = z.object({
  id: z
    .union([z.string().regex(/^-?\d+$/), z.number().int().safe()])
    .transform(String),
  name: z.string(),
  lang: z.string(),
});
const metadataSchema = z
  .object({
    packageName: z.string(),
    versionName: z.string(),
    versionCode: z.number().int().safe(),
    sources: z.array(sourceSchema).min(1),
  })
  .passthrough();
export type OfficialMetadata = z.infer<typeof metadataSchema>;
export function parseOfficialMetadata(text: string): OfficialMetadata {
  const value: unknown = JSON.parse(
    text,
    (_key: string, value: unknown, context?: { source: string }) => {
      if (
        typeof value === 'number' &&
        Number.isInteger(value) &&
        !Number.isSafeInteger(value)
      ) {
        if (!context || !/^-?\d+$/.test(context.source))
          throw new Error('Unsafe upstream integer without exact JSON source');
        return context.source;
      }
      return value;
    },
  );
  return metadataSchema.parse(value);
}

export function validateDescriptor(
  value: unknown,
  upstream: string,
): ExtensionDescriptor {
  const descriptor = extensionDescriptorSchema.parse(value);
  if (!/^src\/[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+$/.test(descriptor.sourcePath))
    throw new Error('Invalid sourcePath');
  if (git(upstream, 'rev-parse', 'HEAD') !== descriptor.upstreamCommit)
    throw new Error('Descriptor upstream commit differs from checkout');
  if (git(upstream, 'status', '--porcelain', '--untracked-files=no'))
    throw new Error('Upstream tracked files are dirty');
  if (hostFingerprint().fingerprint !== descriptor.hostFingerprint)
    throw new Error('Descriptor hostFingerprint differs; regenerate the plan');
  const tracked = new Set(
    git(upstream, 'ls-tree', '-r', '--name-only', 'HEAD').split('\n'),
  );
  for (const inputs of [descriptor.sourceInputs, descriptor.sharedInputs])
    for (const [name, expected] of Object.entries(inputs)) {
      if (path.isAbsolute(name) || name.split('/').includes('..'))
        throw new Error('Invalid fingerprint path');
      if (treeHash(upstream, name, tracked) !== expected)
        throw new Error(`Source input differs: ${name}`);
    }
  const equalNames = (a: string[], b: string[]) =>
    JSON.stringify(a.sort()) === JSON.stringify(b.sort());
  if (
    !equalNames(
      Object.keys(descriptor.sourceInputs),
      dependencies(upstream, descriptor.sourcePath),
    ) ||
    !equalNames(Object.keys(descriptor.sharedInputs), [...SHARED_PATHS])
  )
    throw new Error('Incomplete descriptor fingerprint input set');
  if (
    digest(
      canonical({
        modules: descriptor.sourceInputs,
        shared: descriptor.sharedInputs,
      }),
    ) !== descriptor.sourceFingerprint
  )
    throw new Error('Descriptor source fingerprint mismatch');
  const identity = {
    packageName: descriptor.packageName,
    versionCode: descriptor.versionCode,
    sourceFingerprint: descriptor.sourceFingerprint,
    hostFingerprint: descriptor.hostFingerprint,
  };
  if (digest(canonical(identity)) !== descriptor.inputFingerprint)
    throw new Error('Descriptor input fingerprint mismatch');
  const slug = descriptor.packageName
    .replace(/^eu\.kanade\.tachiyomi\.extension\./, '')
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .slice(0, 80);
  if (
    descriptor.buildId !==
    `ext-${slug}-${descriptor.inputFingerprint.slice(0, 32)}`
  )
    throw new Error('Descriptor buildId does not bind the input fingerprint');
  return descriptor;
}

export function put(
  output: string,
  file: string,
  contentType: 'application/javascript' | 'text/javascript',
) {
  const { encoded, reference } = encodeBundle(readFileSync(file), contentType);
  mkdirSync(path.join(output, 'artifacts'), { recursive: true });
  writeFileSync(
    path.join(output, 'artifacts', reference.sha256 + '.gz'),
    encoded,
  );
  return reference;
}

export async function materialCatalog() {
  const { catalog } = await collectMaterials({ includeWasmBytes: false });
  const bytes = Buffer.from(JSON.stringify(catalog, null, 2) + '\n');
  return { catalog, catalogSha256: digest(bytes) };
}

export interface BuildOptions {
  descriptor: string;
  output: string;
  upstream?: string;
  seed?: string;
  android?: boolean;
  androidSdk?: string;
  workers?: number;
}
export interface BuildResult {
  schemaVersion: 1;
  status: 'built' | 'failed';
  packageName?: string;
  buildId?: string;
  stage: string;
  seconds?: number;
  artifacts: {
    sha256: string;
    size: number;
    path: string;
    encoding: 'gzip';
    encodedSha256: string;
    encodedSize: number;
  }[];
  manifestPath?: string;
  provenancePath?: string;
  failure?: {
    stage: string;
    code: string;
    message: string;
    logPath: string | null;
  };
}

export async function build(options: BuildOptions): Promise<BuildResult> {
  const output = path.resolve(options.output);
  mkdirSync(output, { recursive: true });
  if (existsSync(path.join(output, 'manifest.json')))
    throw new Error(
      'Output already has an immutable manifest; choose a fresh directory',
    );
  const started = performance.now(),
    local = path.join(ROOT, 'runtime/teavm/.local');
  const result: BuildResult = {
    schemaVersion: 1,
    status: 'failed',
    stage: 'upstream',
    artifacts: [],
  };
  const logs = path.join(output, 'logs');
  mkdirSync(logs, { recursive: true });
  let stage = 'upstream',
    activeLog: string | undefined;
  try {
    const descriptor = validateDescriptor(
      readJson(options.descriptor),
      path.resolve(
        options.upstream ?? path.join(ROOT, 'vendor/extensions-source'),
      ),
    );
    result.packageName = descriptor.packageName;
    result.buildId = descriptor.buildId;
    const upstream = path.resolve(
      options.upstream ?? path.join(ROOT, 'vendor/extensions-source'),
    );
    const { catalog: materials, catalogSha256 } = await materialCatalog();
    const runtime = await prepareRuntime({
      ...(options.seed ? { seed: options.seed } : {}),
      android: options.android ?? false,
    });
    const javaVersion = await run(
      path.join(runtime.javaHome, 'bin/java'),
      ['-version'],
      { capture: true },
    );
    if (!javaVersion.stderr.match(/version "25(?:\.|\")/))
      throw new Error('JDK 25 required');
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      JAVA_HOME: runtime.javaHome,
      PATH:
        path.join(runtime.javaHome, 'bin') +
        path.delimiter +
        (process.env['PATH'] ?? ''),
      GRADLE_USER_HOME: path.join(local, 'gradle'),
      ANDROID_HOME: options.androidSdk
        ? path.resolve(options.androidSdk)
        : runtime.androidSdk,
      ANDROID_USER_HOME: path.join(local, 'android-home'),
    };
    env['ANDROID_SDK_ROOT'] = env['ANDROID_HOME'];
    const module = ':' + descriptor.sourcePath.replaceAll('/', ':');
    const wrapper = readFileSync(
      path.join(upstream, 'gradle/wrapper/gradle-wrapper.properties'),
      'utf8',
    );
    if (!wrapper.includes(`gradle-${LOCK.gradle.version}-bin.zip`))
      throw new Error(
        'Unsupported upstream Gradle wrapper; update the toolchain lock explicitly',
      );
    const launcher = path.join(local, 'gradle-launcher', descriptor.buildId);
    mkdirSync(launcher, { recursive: true });
    cpSync(
      path.join(upstream, 'gradle/wrapper/gradle-wrapper.jar'),
      path.join(launcher, 'gradle-wrapper.jar'),
    );
    writeFileSync(
      path.join(launcher, 'gradle-wrapper.properties'),
      wrapper + '\ndistributionSha256Sum=' + LOCK.gradle.sha256 + '\n',
    );
    activeLog = path.join(logs, 'upstream.log');
    console.log(JSON.stringify({ stage, module, logPath: activeLog }));
    await run(
      'java',
      [
        '-classpath',
        path.join(launcher, 'gradle-wrapper.jar'),
        'org.gradle.wrapper.GradleWrapperMain',
        '-p',
        upstream,
        module + ':assembleRelease',
        '--no-configuration-cache',
        '--no-watch-fs',
        `--max-workers=${options.workers ?? 3}`,
        '-Dorg.gradle.daemon=false',
        '-Dorg.gradle.parallel=false',
      ],
      { cwd: upstream, env, log: activeLog },
    );
    if (git(upstream, 'status', '--porcelain', '--untracked-files=no'))
      throw new Error(
        'Official Gradle changed tracked inputs; refusing changed business source',
      );
    const metadata = parseOfficialMetadata(
      readFileSync(
        path.join(
          upstream,
          descriptor.sourcePath,
          'build/keiyoushi-source-info.json',
        ),
        'utf8',
      ),
    );
    for (const [expected, actual] of [
      [descriptor.packageName, metadata.packageName],
      [descriptor.versionName, metadata.versionName],
      [descriptor.versionCode, metadata.versionCode],
    ])
      if (expected !== actual)
        throw new Error('Official metadata disagrees with descriptor');
    const jars = files(
      path.join(upstream, descriptor.sourcePath, 'build/outputs/jar/release'),
      '.jar',
    );
    if (jars.length !== 1)
      throw new Error('Expected exactly one official release JVM JAR');
    const original = jars[0];
    if (!original) throw new Error('Missing original JVM JAR');
    const originalHash = digest(readFileSync(original));
    stage = 'host';
    if (hostFingerprint().fingerprint !== descriptor.hostFingerprint)
      throw new Error(
        'Host changed during upstream compilation; regenerate descriptor and retry',
      );
    const work = path.join(local, 'extension-work', descriptor.buildId);
    rmSync(work, { recursive: true, force: true });
    mkdirSync(work, { recursive: true });
    cpSync(path.join(ROOT, 'runtime/teavm/java'), path.join(work, 'java'), {
      recursive: true,
    });
    const generated = prepareSources(path.join(work, 'java/src/main/java'));
    cpSync(
      path.join(runtime.materials, 'public/runtime'),
      path.join(work, 'public/runtime'),
      { recursive: true },
    );
    mkdirSync(path.join(work, 'public/extensions'), { recursive: true });
    cpSync(
      original,
      path.join(work, 'public/extensions', path.basename(original)),
    );
    const key = descriptor.packageName.split('.').at(-1);
    if (!key) throw new Error('Invalid package key');
    const entry = {
      key,
      packageName: descriptor.packageName,
      jar: path.basename(original),
      convertedSha256: originalHash,
      expectedSources: metadata.sources,
    };
    writeJson(path.join(work, 'inputs.json'), [entry]);
    const cache = path.join(local, 'extension-cache', descriptor.buildId),
      sharedM2 = path.join(local, 'build-cache/m2');
    mkdirSync(cache, { recursive: true });
    mkdirSync(sharedM2, { recursive: true });
    if (!existsSync(path.join(cache, 'm2')))
      symlinkSync(sharedM2, path.join(cache, 'm2'), 'dir');
    delete env['TEAVM_PROBE'];
    delete env['TEAVM_DEBUG'];
    stage = 'aot';
    activeLog = path.join(logs, 'aot.log');
    console.log(
      JSON.stringify({ stage, jarSha256: originalHash, logPath: activeLog }),
    );
    // This is the stable checkout implementation; work only holds sources/data.
    // runAot in a child retains process-group cancellation and a bounded log file.
    await run(
      process.execPath,
      [
        path.join(ROOT, 'tools/teavm/build.ts'),
        '--work-root',
        work,
        '--key',
        key,
        '--cache',
        cache,
        '--maven',
        runtime.maven,
      ],
      { cwd: ROOT, env, log: activeLog },
    );
    if (
      digest(readFileSync(original)) !== originalHash ||
      digest(
        readFileSync(
          path.join(work, 'public/extensions', path.basename(original)),
        ),
      ) !== originalHash
    )
      throw new Error('Build changed the official extension input JAR');
    if (hostFingerprint().fingerprint !== descriptor.hostFingerprint)
      throw new Error(
        'Host changed during AOT compilation; regenerate descriptor and retry',
      );
    const bundle = put(
      output,
      path.join(work, 'public/teavm', key, 'app.js'),
      'text/javascript',
    );
    const manifest = buildManifestSchema.parse({
      buildId: descriptor.buildId,
      repoId: 'keiyoushi',
      packageName: descriptor.packageName,
      version: metadata.versionName,
      sourceIds: metadata.sources.map((source) => source.id).sort(),
      protocolVersion: materials.protocolVersion,
      hostAbi: materials.hostAbi,
      runtimeBaseline: materials.runtimeBaseline,
      bridgeVersion: 2,
      storageSchema: 'release9-v1',
      bundle,
      hostScripts: materials.hostScripts,
      resources: materials.resources,
    });
    const summary = readJson(path.join(work, 'results', `build-${key}.json`));
    if (!isRecord(summary)) throw new Error('Invalid AOT build summary');
    const record = { ...summary, outputSha256: bundle.sha256 };
    writeJson(path.join(work, 'results', `build-${key}.json`), record);
    const provenance = {
      schemaVersion: 1,
      descriptor,
      upstream: {
        commit: descriptor.upstreamCommit,
        metadata,
        jar: path.basename(original),
        jarSha256: originalHash,
      },
      toolchain: {
        androidHome: env['ANDROID_HOME'],
        java: javaVersion.stderr.trim(),
        maven: LOCK.maven.version,
        teavm: LOCK.teavm,
        runtime,
      },
      sharedMaterials: {
        materialVersion: materials.materialVersion,
        catalogSha256,
        protocolABI: {
          protocolVersion: materials.protocolVersion,
          hostAbi: materials.hostAbi,
          runtimeBaseline: materials.runtimeBaseline,
        },
      },
      aot: record,
      generatedUpstreamAdapters: generated.map((file) => ({
        path: path.relative(work, file),
        sha256: digest(readFileSync(file)),
      })),
      manifestSha256: digest(
        Buffer.concat([canonical(manifest), Buffer.from('\n')]),
      ),
      compatibility: {
        browserInitialized: false,
        onlineMetadata: false,
        productImages: false,
      },
      boundary:
        'Compilation and immutable input/hash provenance only. Verify actual Worker initialization separately.',
    };
    writeJson(path.join(output, 'manifest.json'), manifest);
    writeJson(path.join(output, 'provenance.json'), provenance);
    result.status = 'built';
    result.stage = 'complete';
    result.manifestPath = 'manifest.json';
    result.provenancePath = 'provenance.json';
    result.artifacts = [
      {
        sha256: bundle.sha256,
        size: bundle.size,
        path: 'artifacts/' + bundle.sha256 + '.gz',
        encoding: 'gzip',
        encodedSha256: bundle.encodedSha256,
        encodedSize: bundle.encodedSize,
      },
    ];
  } catch (error) {
    rmSync(path.join(output, 'manifest.json'), { force: true });
    result.stage = stage;
    result.failure = {
      stage,
      code: error instanceof Error ? error.name : 'build_failed',
      message: error instanceof Error ? error.message : String(error),
      logPath: activeLog ? path.relative(output, activeLog) : null,
    };
  }
  result.seconds = Math.round((performance.now() - started) / 10) / 100;
  writeJson(path.join(output, 'build-result.json'), result);
  return result;
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const { values } = parseArgs({
    args,
    options: {
      descriptor: { type: 'string' },
      output: { type: 'string' },
      upstream: { type: 'string' },
      seed: { type: 'string' },
      android: { type: 'boolean' },
      'android-sdk': { type: 'string' },
      workers: { type: 'string' },
    },
  });
  if (!values.descriptor || !values.output)
    throw new Error('Usage: builder.ts --descriptor PATH --output DIR');
  const workers = Number(values.workers ?? 3);
  if (!Number.isInteger(workers) || workers < 1 || workers > 8)
    throw new Error('workers must be between 1 and 8');
  const result = await build({
    descriptor: values.descriptor,
    output: values.output,
    workers,
    ...(values.upstream ? { upstream: values.upstream } : {}),
    ...(values.seed ? { seed: values.seed } : {}),
    ...(values.android !== undefined ? { android: values.android } : {}),
    ...(values['android-sdk'] ? { androidSdk: values['android-sdk'] } : {}),
  });
  console.log(JSON.stringify(result, null, 2));
  if (result.status === 'failed') process.exitCode = 1;
}
if (import.meta.main) await main();
