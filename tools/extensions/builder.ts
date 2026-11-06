/** Build an unchanged official extension JAR with the fixed project-owned host. */
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { createHash } from 'node:crypto';
import { execa } from 'execa';
import stableStringify from 'json-stable-stringify';
import writeFileAtomic from 'write-file-atomic';
import isRecord from 'is-plain-obj';
import { z } from 'zod';
import { buildManifestSchema } from '../../packages/contracts/src/index.ts';
import { runtimeMaterialCatalogSchema } from '@karuyomi/contracts';
import { prepareRuntime, LOCK } from '../teavm/runtime.ts';
import type { PreparedRuntime } from '../teavm/runtime.ts';
import { prepareSources } from '../teavm/upstream-sources.ts';
import {
  dependencies,
  git,
  hostFingerprint,
  treeHash,
  SHARED_PATHS,
  ROOT,
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
  const sourceIdentity = stableStringify({
    modules: descriptor.sourceInputs,
    shared: descriptor.sharedInputs,
  });
  if (sourceIdentity === undefined)
    throw new Error('Source identity is not JSON');
  if (
    createHash('sha256').update(sourceIdentity).digest('hex') !==
    descriptor.sourceFingerprint
  )
    throw new Error('Descriptor source fingerprint mismatch');
  const identity = {
    packageName: descriptor.packageName,
    versionCode: descriptor.versionCode,
    sourceFingerprint: descriptor.sourceFingerprint,
    hostFingerprint: descriptor.hostFingerprint,
  };
  const encodedIdentity = stableStringify(identity);
  if (encodedIdentity === undefined)
    throw new Error('Input identity is not JSON');
  if (
    createHash('sha256').update(encodedIdentity).digest('hex') !==
    descriptor.inputFingerprint
  )
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
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      readFileSync(
        new URL(
          '../../packages/runtime-host/dist/materials.json',
          import.meta.url,
        ),
        'utf8',
      ),
    ),
  );
  const bytes = Buffer.from(JSON.stringify(catalog, null, 2) + '\n');
  return {
    catalog,
    catalogSha256: createHash('sha256').update(bytes).digest('hex'),
  };
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

/** Upstream Gradle and AOT execute without deployment or release credentials. */
export function buildEnvironment(
  runtime: Pick<PreparedRuntime, 'javaHome' | 'androidSdk'>,
  options: Pick<BuildOptions, 'androidSdk'>,
  parentEnvironment: Readonly<NodeJS.ProcessEnv> = process.env,
): NodeJS.ProcessEnv {
  const local = path.join(ROOT, 'runtime/teavm/.local');
  const androidHome = options.androidSdk
    ? path.resolve(options.androidSdk)
    : runtime.androidSdk;
  return {
    ...parentEnvironment,
    JAVA_HOME: runtime.javaHome,
    PATH:
      path.join(runtime.javaHome, 'bin') +
      path.delimiter +
      (parentEnvironment['PATH'] ?? ''),
    GRADLE_USER_HOME: path.join(local, 'gradle'),
    ANDROID_HOME: androidHome,
    ANDROID_SDK_ROOT: androidHome,
    ANDROID_USER_HOME: path.join(local, 'android-home'),
    GH_TOKEN: undefined,
    GITHUB_TOKEN: undefined,
    CLOUDFLARE_API_TOKEN: undefined,
  };
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
    if (statSync(options.descriptor).size > 2 * 1024 * 1024)
      throw new Error('Oversized build descriptor');
    const descriptorBytes = readFileSync(options.descriptor);
    if (descriptorBytes.length > 2 * 1024 * 1024)
      throw new Error('Oversized build descriptor');
    const descriptor = validateDescriptor(
      JSON.parse(descriptorBytes.toString('utf8')),
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
    const javaVersion = await execa(
      path.join(runtime.javaHome, 'bin/java'),
      ['-version'],
      {
        shell: false,
        stdin: 'ignore',
        preferLocal: false,
        stripFinalNewline: false,
        verbose: 'none',
        maxBuffer: 2 * 1024 * 1024,
      },
    );
    if (!javaVersion.stderr.match(/version "25(?:\.|\")/))
      throw new Error('JDK 25 required');
    const env = buildEnvironment(runtime, options);
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
    await execa(
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
      {
        shell: false,
        stdin: 'ignore',
        preferLocal: false,
        stripFinalNewline: false,
        verbose: 'none',
        cwd: upstream,
        env,
        extendEnv: false,
        stdout: { file: activeLog },
        stderr: { file: activeLog },
        buffer: false,
      },
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
    const jarDirectory = path.join(
      upstream,
      descriptor.sourcePath,
      'build/outputs/jar/release',
    );
    const jars = readdirSync(jarDirectory, {
      recursive: true,
      withFileTypes: true,
    })
      .filter((file) => file.isFile() && file.name.endsWith('.jar'))
      .map((file) => path.join(file.parentPath, file.name))
      .sort();
    if (jars.length !== 1)
      throw new Error('Expected exactly one official release JVM JAR');
    const original = jars[0];
    if (!original) throw new Error('Missing original JVM JAR');
    const originalHash = createHash('sha256')
      .update(readFileSync(original))
      .digest('hex');
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
    const serializedInputs = stableStringify([entry]);
    if (serializedInputs === undefined)
      throw new Error('Build inputs are not JSON');
    writeFileAtomic.sync(
      path.join(work, 'inputs.json'),
      serializedInputs + '\n',
    );
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
    await execa(
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
      {
        shell: false,
        stdin: 'ignore',
        preferLocal: false,
        stripFinalNewline: false,
        verbose: 'none',
        cwd: ROOT,
        env,
        extendEnv: false,
        stdout: { file: activeLog },
        stderr: { file: activeLog },
        buffer: false,
      },
    );
    if (
      createHash('sha256').update(readFileSync(original)).digest('hex') !==
        originalHash ||
      createHash('sha256')
        .update(
          readFileSync(
            path.join(work, 'public/extensions', path.basename(original)),
          ),
        )
        .digest('hex') !== originalHash
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
      sources: [...metadata.sources].sort((a, b) =>
        a.id < b.id ? -1 : a.id > b.id ? 1 : 0,
      ),
      protocolVersion: materials.protocolVersion,
      hostAbi: materials.hostAbi,
      runtimeBaseline: materials.runtimeBaseline,
      bridgeVersion: 2,
      storageSchema: 'release9-v1',
      bundle,
      hostScripts: materials.hostScripts,
      resources: materials.resources,
    });
    const summaryFile = path.join(work, 'results', `build-${key}.json`);
    if (statSync(summaryFile).size > 2 * 1024 * 1024)
      throw new Error('Oversized AOT summary');
    const summary: unknown = JSON.parse(readFileSync(summaryFile, 'utf8'));
    if (!isRecord(summary)) throw new Error('Invalid AOT build summary');
    const record = { ...summary, outputSha256: bundle.sha256 };
    const serializedSummary = stableStringify(record);
    if (serializedSummary === undefined)
      throw new Error('AOT summary is not JSON');
    writeFileAtomic.sync(summaryFile, serializedSummary + '\n');
    const serializedManifest = stableStringify(manifest);
    if (serializedManifest === undefined)
      throw new Error('Build manifest is not JSON');
    const manifestBytes = Buffer.from(serializedManifest + '\n');
    if (manifestBytes.length > 64 * 1024)
      throw new Error('Build manifest exceeds 64 KiB');
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
        sha256: createHash('sha256').update(readFileSync(file)).digest('hex'),
      })),
      manifestSha256: createHash('sha256').update(manifestBytes).digest('hex'),
      compatibility: {
        browserInitialized: false,
        onlineMetadata: false,
        productImages: false,
      },
      boundary:
        'Compilation and immutable input/hash provenance only. Verify actual Worker initialization separately.',
    };
    const serializedProvenance = stableStringify(provenance);
    if (serializedProvenance === undefined)
      throw new Error('Build provenance is not JSON');
    writeFileAtomic.sync(path.join(output, 'manifest.json'), manifestBytes);
    writeFileAtomic.sync(
      path.join(output, 'provenance.json'),
      serializedProvenance + '\n',
    );
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
  const serializedResult = stableStringify(result);
  if (serializedResult === undefined)
    throw new Error('Build result is not JSON');
  writeFileAtomic.sync(
    path.join(output, 'build-result.json'),
    serializedResult + '\n',
  );
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
