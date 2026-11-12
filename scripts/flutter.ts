import { execa, ExecaError } from 'execa';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
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

const run = execa({
  cwd: root,
  stdin: 'ignore',
  stdout: 'inherit',
  stderr: 'inherit',
  buffer: false,
  shell: false,
  preferLocal: false,
  verbose: 'none',
});
async function generate(check = false): Promise<void> {
  const cwd = path.join(root, 'apps/reader');
  const snapshot = () => {
    const source = path.join(cwd, 'lib');
    return readdirSync(source, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.g.dart'))
      .map((entry) => {
        const file = path.join(entry.parentPath, entry.name);
        return `${path.relative(source, file)}:${createHash('sha256').update(readFileSync(file)).digest('hex')}`;
      })
      .sort()
      .join('\n');
  };
  const before = check ? snapshot() : '';
  await run(dart, ['run', 'build_runner', 'build', '--force-jit'], { cwd });
  if (check && snapshot() !== before) {
    throw new Error(
      'Riverpod generated files differ; run pnpm flutter:generate and commit the outputs',
    );
  }
}
async function main(): Promise<void> {
  const projects = [
    'packages/reader_core',
    'packages/source_runtime',
    'apps/reader',
  ];
  switch (process.argv[2]) {
    case 'generate':
      await generate(process.argv.includes('--check'));
      break;
    case 'setup':
      for (const project of projects) {
        await run(project === 'apps/reader' ? flutter : dart, ['pub', 'get'], {
          cwd: path.join(root, project),
        });
      }
      break;
    case 'check': {
      await generate(true);
      for (const project of projects) {
        const cwd = path.join(root, project);
        if (project === 'apps/reader') {
          await run(flutter, ['analyze', '--fatal-infos'], { cwd });
          await run(flutter, ['test', ...process.argv.slice(3)], { cwd });
        } else {
          await run(dart, ['analyze', '--fatal-infos'], { cwd });
          await run(dart, ['test', ...process.argv.slice(3)], { cwd });
        }
      }
      // Dart comes from the same pinned SDK as Flutter.
      await run(dart, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        ...projects.flatMap((project) =>
          ['lib', 'test', 'integration_test', 'tool'].flatMap((directory) => {
            const source = path.join(root, project, directory);
            return existsSync(source)
              ? readdirSync(source, { recursive: true, withFileTypes: true })
                  .filter(
                    (entry) => entry.isFile() && entry.name.endsWith('.dart'),
                  )
                  .map((entry) => path.join(entry.parentPath, entry.name))
                  .filter(
                    (file) =>
                      !file.includes(
                        `${path.sep}src${path.sep}pb${path.sep}`,
                      ) && !file.endsWith('.g.dart'),
                  )
                  .sort()
              : [];
          }),
        ),
      ]);
      break;
    }
    case 'build':
      await run(
        flutter,
        [
          'build',
          'web',
          '--release',
          '--no-web-resources-cdn',
          '--web-content-hash',
          '--no-deprecated-js-interop',
          ...process.argv.slice(3),
        ],
        { cwd: path.join(root, 'apps/reader') },
      );
      break;
    case 'run':
      await run(flutter, ['run', '-d', 'chrome', ...process.argv.slice(3)], {
        cwd: path.join(root, 'apps/reader'),
        stdin: 'inherit',
      });
      break;
    default:
      throw new Error('Use setup, generate, check, build or run');
  }
}
await main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = error instanceof ExecaError ? (error.exitCode ?? 1) : 1;
});
