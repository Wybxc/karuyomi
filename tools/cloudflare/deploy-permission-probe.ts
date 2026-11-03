import { execa } from 'execa';
import { getStreamAsBuffer, MaxBufferError } from 'get-stream';
import path from 'node:path';

const MAX_DEPLOYMENT_OUTPUT = 512 * 1024;

/** Only messages already stripped of deployment credentials may leave this boundary. */
export class PermissionDeploymentFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PermissionDeploymentFailure';
  }
}

export interface PermissionDeploymentOptions {
  wranglerCli: string;
  configuration: string;
  temporaryDirectory: string;
  token: string;
  restoringBaseline: boolean;
  signal?: AbortSignal;
}

/** Deploy the isolated permission-check Worker; never expose Wrangler's raw output. */
export async function deployPermissionProbe(
  options: PermissionDeploymentOptions,
): Promise<void> {
  const controller = new AbortController();
  const signal =
    options.signal && !options.restoringBaseline
      ? AbortSignal.any([options.signal, controller.signal])
      : controller.signal;
  const child = execa(
    process.execPath,
    [options.wranglerCli, 'deploy', '--config', options.configuration],
    {
      cwd: options.temporaryDirectory,
      stdin: 'ignore',
      stdout: 'pipe',
      stderr: 'pipe',
      shell: false,
      preferLocal: false,
      stripFinalNewline: false,
      verbose: 'none',
      env: {
        ...process.env,
        CLOUDFLARE_API_TOKEN: options.token,
        CI: 'true',
        CLOUDFLARE_SEND_METRICS: 'false',
        WRANGLER_LOG_PATH: path.join(
          options.temporaryDirectory,
          'wrangler.log',
        ),
        NO_COLOR: '1',
      },
      extendEnv: false,
      all: true,
      buffer: false,
      timeout: 180_000,
      cancelSignal: signal,
      killDescendants: true,
      forceKillAfterDelay: 3000,
      reject: false,
    },
  );
  // A CLI may exit while a helper still owns its output pipes. Stop that tree
  // before awaiting Execa's final stream completion, including on success.
  child.nodeChildProcess.once('exit', () => child.kill());
  try {
    const output = (
      await getStreamAsBuffer(child.all, { maxBuffer: MAX_DEPLOYMENT_OUTPUT })
    ).toString('utf8');
    const result = await child;
    if (result.failed) {
      if (signal.aborted)
        throw new PermissionDeploymentFailure('Wrangler deployment cancelled');
      const codes = [...output.matchAll(/\[code:\s*(\d+)\]/g)].map(
        (match) => match[1],
      );
      const redacted = output.replaceAll(options.token, '[redacted]');
      throw new PermissionDeploymentFailure(
        `Wrangler deployment failed (exit ${result.exitCode ?? 'signal'}); Cloudflare API codes: ${codes.join(',') || 'unavailable'}. ${redacted.slice(-5000)}`,
      );
    }
    if (
      !options.restoringBaseline &&
      !/Success! Uploaded 1 file(?:\s|$)/.test(output)
    )
      throw new PermissionDeploymentFailure(
        'Wrangler did not confirm uploading the unique static file',
      );
  } catch (error) {
    // Stream overflow/error must stop the producer before the caller removes
    // its temporary logs or begins restoring remote resources.
    controller.abort();
    await child;
    if (error instanceof PermissionDeploymentFailure) throw error;
    if (error instanceof MaxBufferError)
      throw new PermissionDeploymentFailure(
        'Wrangler deployment exceeded the 512 KiB merged output budget',
      );
    throw new PermissionDeploymentFailure(
      signal.aborted && options.signal?.aborted && !options.restoringBaseline
        ? 'Wrangler deployment cancelled'
        : 'Wrangler deployment output failed; raw error output withheld',
    );
  } finally {
    // Execa's escalation timer stops when its result settles. Helpers without
    // inherited pipes can outlive that result, so finish their group as well.
    child.kill('SIGKILL');
  }
}
