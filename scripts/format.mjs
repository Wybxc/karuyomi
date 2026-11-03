import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { format as formatSql } from 'sql-formatter';

const root = fileURLToPath(new URL('../', import.meta.url));
const write = process.argv.includes('--write');
const portable = process.argv.includes('--portable');
if (
  write === process.argv.includes('--check') ||
  process.argv.some(
    (arg, index) =>
      index > 1 && !['--write', '--check', '--portable'].includes(arg),
  )
) {
  throw Error('Usage: node scripts/format.mjs --write|--check [--portable]');
}
function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit',
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw Error(`${command} failed (${result.status})`);
  return result;
}
const files = [
  ...new Set(
    run(
      'git',
      ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
      { encoding: 'utf8', stdio: 'pipe' },
    ).stdout.split('\0'),
  ),
].filter(
  (name) =>
    name &&
    !name.startsWith('vendor/') &&
    !name.startsWith('docs/design/') &&
    !name.startsWith('runtime/teavm/bridge/compat/') &&
    existsSync(path.join(root, name)),
);
const matching = (pattern) => files.filter((name) => pattern.test(name));
const formatterDirectory = path.join(root, '.local/formatters');
mkdirSync(formatterDirectory, { recursive: true });
const hash = (file) =>
  createHash('sha256').update(readFileSync(file)).digest('hex');
function jar(name, url, expected) {
  const destination = path.join(formatterDirectory, name);
  if (!existsSync(destination) || hash(destination) !== expected) {
    const temporary = destination + '.download';
    run('curl', [
      '--fail',
      '--location',
      '--silent',
      '--show-error',
      '--retry',
      '2',
      '--max-filesize',
      '134217728',
      '--output',
      temporary,
      url,
    ]);
    if (hash(temporary) !== expected) {
      rmSync(temporary);
      throw Error('Formatter checksum mismatch: ' + name);
    }
    renameSync(temporary, destination);
  }
  return destination;
}
const javaCandidates = [
  process.env.JAVA_HOME && path.join(process.env.JAVA_HOME, 'bin/java'),
  path.join(
    root,
    'runtime/teavm/.local/jdks/jdk-25.0.5+8/Contents/Home/bin/java',
  ),
];
const java =
  javaCandidates.find((value) => value && existsSync(value)) ?? 'java';
const javaVersion = run(java, ['-version'], {
  encoding: 'utf8',
  stdio: 'pipe',
});
const major = Number(
  /version "(\d+)/.exec(javaVersion.stderr + javaVersion.stdout)?.[1],
);
if (!(major >= 21))
  throw Error(
    'Formatting requires a full JDK 21+ (JAVA_HOME or PATH); no private runtime seed is needed',
  );

console.log('[format] Java');
const gjf = jar(
  'google-java-format-2.0.0-all-deps.jar',
  'https://github.com/google/google-java-format/releases/download/v2.0.0/google-java-format-2.0.0-all-deps.jar',
  'c78feb48c549fa7114b7ea11db3b456808f7b371ffe84e6643a44dd2f9588639',
);
const javaFlags = [
  '-jar',
  gjf,
  '--cleanup=false',
  '--skip-sorting-imports',
  '--skip-removing-unused-imports',
  '--skip-reordering-modifiers',
  '--skip-reflowing-long-strings',
  '--skip-javadoc-formatting',
];
const javaFiles = matching(/\.java$/);
if (write) {
  // GJF 2.0.0 occasionally needs a second layout pass to reach a fixed point.
  run(java, [...javaFlags, '--replace', ...javaFiles]);
  run(java, [...javaFlags, '--replace', ...javaFiles]);
}
run(java, [...javaFlags, '--dry-run', '--set-exit-if-changed', ...javaFiles]);

console.log('[format] Kotlin / Gradle Kotlin DSL');
const ktfmt = jar(
  'ktfmt-0.63-with-dependencies.jar',
  'https://repo.maven.apache.org/maven2/com/facebook/ktfmt/0.63/ktfmt-0.63-with-dependencies.jar',
  'a015521ddb1c7a80c41edb56b91b4a231439592ffd2e85ac866ff8134c37c112',
);
run(java, [
  '-jar',
  ktfmt,
  '--google-style',
  '--do-not-remove-unused-imports',
  ...(write ? [] : ['--dry-run', '--set-exit-if-changed']),
  ...matching(/\.kts?$/),
]);

console.log('[format] Python');
const uv = spawnSync('uv', ['--version'], { stdio: 'ignore' }).status === 0;
if (uv) {
  run(
    'uvx',
    [
      '--default-index',
      'https://pypi.org/simple',
      '--no-python-downloads',
      'ruff@0.17.3',
      'format',
      ...(write ? [] : ['--check']),
      'scripts',
      'tools',
    ],
    {
      env: {
        ...process.env,
        UV_CACHE_DIR: path.join(root, '.tools/uv-cache'),
        UV_TOOL_DIR: path.join(root, '.tools/uv-tools'),
      },
    },
  );
} else {
  const environment = path.join(root, '.tools/format-python');
  const ruff = path.join(environment, 'bin/ruff');
  if (!existsSync(ruff)) {
    run('python3', ['-m', 'venv', environment]);
    run(path.join(environment, 'bin/python'), [
      '-m',
      'pip',
      'install',
      '--disable-pip-version-check',
      'ruff==0.17.3',
    ]);
  }
  run(ruff, ['format', ...(write ? [] : ['--check']), 'scripts', 'tools']);
}

console.log('[format] Dart');
const dart = process.env.FLUTTER_ROOT
  ? path.join(process.env.FLUTTER_ROOT, 'bin/dart')
  : existsSync(path.join(root, '.fvm/flutter_sdk/bin/dart'))
    ? path.join(root, '.fvm/flutter_sdk/bin/dart')
    : 'dart';
const dartVersion = run(dart, ['--version'], {
  encoding: 'utf8',
  stdio: 'pipe',
});
if (!(dartVersion.stdout + dartVersion.stderr).includes('3.13.4'))
  throw Error('Use Dart 3.13.4 from Flutter 3.47.5 for stable formatting');
run(dart, [
  'format',
  ...(write ? [] : ['--output=none', '--set-exit-if-changed']),
  ...matching(/\.dart$/),
]);

console.log('[format] JavaScript / TypeScript / data / markup');
const xml = matching(
  /\.(?:xml|plist|storyboard|xcscheme|xcworkspacedata|xcsettings)$/,
);
run('pnpm', [
  'exec',
  'prettier',
  write ? '--write' : '--check',
  '--ignore-unknown',
  '--log-level',
  'warn',
  ...files.filter((name) => !xml.includes(name) && !name.endsWith('.sql')),
]);
run('pnpm', [
  'exec',
  'prettier',
  '--plugin',
  '@prettier/plugin-xml',
  '--parser',
  'xml',
  write ? '--write' : '--check',
  '--log-level',
  'warn',
  ...xml,
]);
for (const name of matching(/\.sql$/)) {
  const file = path.join(root, name);
  const before = readFileSync(file, 'utf8');
  const after =
    formatSql(before, { language: 'sqlite', keywordCase: 'upper' }).trimEnd() +
    '\n';
  if (before !== after) {
    if (!write) throw Error('SQL needs formatting: ' + name);
    writeFileSync(file, after);
  }
}

console.log('[format] Ruby');
const rufoGem = jar(
  'rufo-0.13.0.gem',
  'https://rubygems.org/downloads/rufo-0.13.0.gem',
  '16266d7da8e024b04d296eefd433077d9003a657797a59d7ed153db3e631ed53',
);
const rufoDirectory = path.join(formatterDirectory, 'rufo-0.13.0');
if (!existsSync(path.join(rufoDirectory, 'exe/rufo'))) {
  run('ruby', [
    '-rrubygems/package',
    '-e',
    'Gem::Package.new(ARGV[0]).extract_files(ARGV[1])',
    rufoGem,
    rufoDirectory,
  ]);
}
run('ruby', [
  '-I',
  path.join(rufoDirectory, 'lib'),
  path.join(rufoDirectory, 'exe/rufo'),
  '--simple-exit',
  ...(write ? [] : ['--check']),
  ...matching(/(?:\.rb$|(?:^|\/)Podfile$)/),
]);

if (!portable) {
  if (process.platform !== 'darwin')
    throw Error(
      'Full native formatting requires macOS / Xcode; CI can explicitly use --portable',
    );
  console.log('[format] Swift / Objective-C (Xcode)');
  for (const [tool, version] of [
    ['swift-format', '6.4.4'],
    ['clang-format', '21.0.0'],
  ]) {
    const result = run('xcrun', [tool, '--version'], {
      encoding: 'utf8',
      stdio: 'pipe',
    });
    if (!(result.stdout + result.stderr).includes(version))
      throw Error(`Use the Xcode formatter ${tool} ${version}`);
  }
  run('xcrun', [
    'swift-format',
    write ? 'format' : 'lint',
    write ? '--in-place' : '--strict',
    ...matching(/\.swift$/),
  ]);
  run('xcrun', [
    'clang-format',
    '--style=Google',
    ...(write ? ['-i'] : ['--dry-run', '--Werror']),
    ...matching(/\.(?:h|m|mm|c|cc|cpp)$/),
  ]);
} else
  console.log(
    '[format] Explicit portable mode: Swift / Objective-C checked on macOS before commit',
  );
