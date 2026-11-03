import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const bin = process.platform === 'win32' ? 'flutter.bat' : 'flutter';
const flutter = process.env.FLUTTER_ROOT
  ? path.join(process.env.FLUTTER_ROOT, 'bin', bin)
  : existsSync(path.join(root, '.fvm/flutter_sdk/bin', bin))
    ? path.join(root, '.fvm/flutter_sdk/bin', bin)
    : bin;
const dart = path.join(
  path.dirname(flutter),
  process.platform === 'win32' ? 'dart.bat' : 'dart',
);

function run(command, args, cwd = root) {
  const result = spawnSync(command, args, { cwd, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

const projects = [
  'packages/reader_core',
  'packages/source_runtime',
  'apps/reader',
];
switch (process.argv[2]) {
  case 'setup':
    for (const project of projects) {
      run(
        project === 'apps/reader' ? flutter : dart,
        ['pub', 'get'],
        path.join(root, project),
      );
    }
    break;
  case 'check':
    for (const project of projects) {
      const cwd = path.join(root, project);
      if (project === 'apps/reader') {
        run(flutter, ['analyze', '--fatal-infos'], cwd);
        run(flutter, ['test'], cwd);
      } else {
        run(dart, ['analyze', '--fatal-infos'], cwd);
        run(dart, ['test'], cwd);
      }
    }
    // Dart comes from the same pinned SDK as Flutter.
    run(dart, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ...projects.map((p) => `${p}/lib`),
      ...projects.map((p) => `${p}/test`),
    ]);
    break;
  case 'build':
    run(
      flutter,
      ['build', 'web', '--release', '--no-web-resources-cdn'],
      path.join(root, 'apps/reader'),
    );
    break;
  case 'run':
    run(
      flutter,
      ['run', '-d', 'chrome', ...process.argv.slice(3)],
      path.join(root, 'apps/reader'),
    );
    break;
  default:
    throw new Error('Use setup, check, build or run');
}
