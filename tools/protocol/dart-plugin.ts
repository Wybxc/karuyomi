import { execa as exec } from 'execa';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { z } from 'zod';

const root = fileURLToPath(new URL('../../', import.meta.url));
export function dartExecutable(): string {
  const bin = process.platform === 'win32' ? 'dart.bat' : 'dart';
  if (process.env.FLUTTER_ROOT) {
    return path.join(process.env.FLUTTER_ROOT, 'bin', bin);
  }
  const local = path.join(root, '.fvm/flutter_sdk/bin', bin);
  return existsSync(local) ? local : bin;
}

/** Launch the official plugin using its locked package config and inherited
 * protoc stdin/stdout. This is a launcher, not a code generator. */
export async function runDartPlugin(): Promise<number> {
  const config = path.join(
    root,
    'tools/protocol/generator/.dart_tool/package_config.json',
  );
  const packages = z
    .object({
      packages: z.array(
        z.object({
          name: z.string(),
          rootUri: z.string(),
        }),
      ),
    })
    .parse(JSON.parse(readFileSync(config, 'utf8')));
  const plugin = packages.packages.find(
    (entry) => entry.name === 'protoc_plugin',
  );
  if (!plugin)
    throw new Error('Run pnpm protocol:setup before generating Dart');
  const packageRoot = fileURLToPath(
    new URL(plugin.rootUri, pathToFileURL(config)),
  );
  const entry = path.join(packageRoot, 'bin/protoc_plugin.dart');
  const result = await exec(dartExecutable(), [`--packages=${config}`, entry], {
    cwd: root,
    shell: false,
    preferLocal: false,
    verbose: 'none',
    stdin: 'inherit',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
  });
  return result.exitCode ?? 1;
}
