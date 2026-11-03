import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
  workerCommandSchema,
  type BuildManifest,
  type WorkerCommand,
  type WorkerResponse,
} from '@karuyomi/contracts';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import type { RuntimeDriver } from './teavm-driver.js';

export class WorkerRuntime {
  readonly workerInstanceId: string;
  private generation: string | undefined;
  private manifest: BuildManifest | undefined;
  private busy = false;
  private controller = new AbortController();

  constructor(
    private readonly driver: RuntimeDriver,
    private readonly send: (message: WorkerResponse) => void,
    id = crypto.randomUUID(),
  ) {
    this.workerInstanceId = id;
  }

  async receive(
    input: unknown,
    ports: readonly MessagePort[] = [],
  ): Promise<void> {
    const parsed = workerCommandSchema.safeParse(input);
    if (!parsed.success) {
      for (const port of ports) port.close();
      return;
    }
    const command = parsed.data;
    if (command.workerInstanceId !== this.workerInstanceId) {
      for (const port of ports) port.close();
      return;
    }
    if (
      this.generation !== undefined &&
      (command.generation !== this.generation ||
        command.buildId !== this.manifest?.buildId)
    ) {
      for (const port of ports) port.close();
      return;
    }
    if (this.busy) {
      for (const port of ports) port.close();
      this.reply(
        command,
        undefined,
        new RuntimeFailure(
          'protocol_error',
          'A Source operation is already active',
        ),
      );
      return;
    }
    this.busy = true;
    try {
      if (command.type === 'open') {
        if (this.manifest)
          throw new RuntimeFailure(
            'protocol_error',
            'A Worker can only load one extension build',
          );
        if (command.buildId !== command.manifest.buildId)
          throw new RuntimeFailure(
            'integrity_error',
            'Envelope build does not match the manifest',
          );
        this.generation = command.generation;
        this.manifest = command.manifest;
        const sources = await this.driver.open(
          command.manifest,
          command.userAgent,
          this.controller.signal,
          { requestId: command.requestId, generation: command.generation },
        );
        this.reply(command, {
          protocolVersion,
          workerInstanceId: this.workerInstanceId,
          generation: command.generation,
          buildId: command.buildId,
          sources,
          capabilities: [
            'source-rpc',
            'explicit-references',
            'complete-dto',
            'cancel-by-worker-recycle',
            ...(this.driver.acquireImage && this.driver.closePageSession
              ? ['processed-image-resources']
              : []),
          ],
          hostAbi,
          runtimeBaseline,
        });
      } else if (command.type === 'invoke') {
        if (!this.manifest)
          throw new RuntimeFailure(
            'runtime_lost',
            'Source runtime is not open',
          );
        if (!this.manifest.sourceIds.includes(command.sourceId))
          throw new RuntimeFailure(
            'protocol_error',
            'Source does not belong to the loaded build',
          );
        if (JSON.stringify(command.args).length > 128 * 1024)
          throw new RuntimeFailure(
            'limit_exceeded',
            'Source control arguments are too large',
          );
        const data = await this.driver.invoke(
          command.sourceId,
          command.operation,
          command.args,
          { requestId: command.requestId, generation: command.generation },
        );
        this.reply(command, {
          requestId: command.requestId,
          generation: command.generation,
          buildId: command.buildId,
          data,
        });
      } else if (command.type === 'acquire-image') {
        if (
          !this.manifest ||
          !this.manifest.sourceIds.includes(command.sourceId)
        )
          throw new RuntimeFailure(
            'runtime_lost',
            'Image Source does not belong to this runtime',
          );
        if (!this.driver.acquireImage || ports.length !== 1 || !ports[0])
          throw new RuntimeFailure(
            'unsupported_capability',
            'Image channel is not available',
          );
        const result = await this.driver.acquireImage(
          command.sourceId,
          command.pageSessionId,
          command.pageKey,
          ports[0],
          command.resourceId,
          { requestId: command.requestId, generation: command.generation },
        );
        this.reply(command, result);
      } else if (command.type === 'close-page-session') {
        if (!this.manifest || !this.driver.closePageSession)
          throw new RuntimeFailure(
            'unsupported_capability',
            'Page session control is not available',
          );
        this.reply(
          command,
          await this.driver.closePageSession(command.pageSessionId, {
            requestId: command.requestId,
            generation: command.generation,
          }),
        );
      } else {
        this.controller.abort();
        await this.driver.close();
        this.reply(command, { closed: true });
      }
    } catch (error) {
      this.reply(command, undefined, runtimeFailure(error));
    } finally {
      for (const port of ports) port.close();
      this.busy = false;
    }
  }

  private reply(
    command: WorkerCommand,
    result?: unknown,
    error?: RuntimeFailure,
  ): void {
    this.send({
      type: 'response',
      protocolVersion,
      workerInstanceId: this.workerInstanceId,
      generation: command.generation,
      buildId: command.buildId,
      requestId: command.requestId,
      ...(error ? { error: error.toJSON() } : { result }),
    });
  }
}
