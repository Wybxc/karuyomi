import { spawn } from 'node:child_process';
import { closeSync, mkdirSync, openSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export function files(directory: string, suffix = ''): string[] {
  return readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name, 'en'))
    .flatMap((entry) => {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) return files(file, suffix);
      return entry.isFile() && file.endsWith(suffix) ? [file] : [];
    });
}

export function safeName(name: string): string {
  if (
    path.posix.isAbsolute(name) ||
    name.split('/').includes('..') ||
    name.includes('\\')
  ) {
    throw new Error(`Unsafe archive path: ${name}`);
  }
  return name;
}

export class CommandError extends Error {
  readonly command: string;
  readonly exitCode: number | null;
  constructor(command: string, exitCode: number | null) {
    super(`Command failed (${exitCode ?? 'signal'}): ${command}`);
    this.command = command;
    this.exitCode = exitCode;
  }
}

export interface RunOptions {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  log?: string;
  capture?: boolean;
}

export async function run(
  command: string,
  args: readonly string[],
  options: RunOptions = {},
): Promise<{ stdout: string; stderr: string }> {
  if (options.log && options.capture)
    throw new Error('Choose either a file log or captured output');
  if (options.log) mkdirSync(path.dirname(options.log), { recursive: true });
  const output = options.log ? openSync(options.log, 'w') : undefined;
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn(command, [...args], {
        cwd: options.cwd,
        env: options.env,
        stdio: [
          'ignore',
          output ?? (options.capture ? 'pipe' : 'inherit'),
          output ?? (options.capture ? 'pipe' : 'inherit'),
        ],
      });
      let stdout = '',
        stderr = '';
      child.stdout?.on('data', (data: Buffer) => {
        if (options.capture) stdout += data.toString();
      });
      child.stderr?.on('data', (data: Buffer) => {
        if (options.capture) stderr += data.toString();
      });
      child.once('error', reject);
      child.once('close', (code) => {
        if (code === 0) resolve({ stdout, stderr });
        else reject(new CommandError(command, code));
      });
    });
  } finally {
    if (output !== undefined) closeSync(output);
  }
}

export function fileSize(file: string): number {
  return statSync(file).size;
}
