import {
  protocolVersion,
  workerCommandSchema,
  buildManifestSchema,
  messageJson,
  encodeWorkerResponse,
  runtimeErrorMessage,
  sourceResultFor,
  requireCondition,
  type BuildManifest,
  type WorkerCommand,
} from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
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
    private readonly send: (message: pb.WorkerResponseJson) => void,
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
    const envelope = command.envelope;
    if (
      envelope.workerInstanceId !== this.workerInstanceId ||
      (this.generation !== undefined &&
        (envelope.generation !== this.generation ||
          envelope.buildId !== this.manifest?.buildId))
    ) {
      for (const port of ports) port.close();
      return;
    }
    if (this.busy) {
      for (const port of ports) port.close();
      this.reply(command, {
        case: 'error',
        value: runtimeErrorMessage(
          new RuntimeFailure(
            'protocol_error',
            'A Source operation is already active',
          ).toJSON(),
        ),
      });
      return;
    }
    this.busy = true;
    try {
      switch (command.command.case) {
        case 'open': {
          if (this.manifest)
            throw new RuntimeFailure(
              'protocol_error',
              'A Worker can only load one extension build',
            );
          const opening = command.command.value;
          requireCondition(
            opening.manifest !== undefined,
            'Worker manifest is required',
          );
          const manifest = buildManifestSchema.parse(
            messageJson(pb.BuildManifestSchema, opening.manifest),
          );
          this.generation = envelope.generation;
          this.manifest = manifest;
          const sources = await this.driver.open(
            manifest,
            opening.userAgent,
            this.controller.signal,
            { requestId: envelope.requestId, generation: envelope.generation },
          );
          this.reply(command, {
            case: 'session',
            value: create(pb.RuntimeSessionSchema, {
              protocolVersion,
              workerInstanceId: this.workerInstanceId,
              generation: envelope.generation,
              buildId: envelope.buildId,
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
            }),
          });
          break;
        }
        case 'invoke': {
          const call = command.command.value;
          if (!this.manifest)
            throw new RuntimeFailure(
              'runtime_lost',
              'Source runtime is not open',
            );
          if (!this.manifest.sourceIds.includes(call.sourceId))
            throw new RuntimeFailure(
              'protocol_error',
              'Source does not belong to the loaded build',
            );
          const payload = await this.driver.invoke(call, {
            requestId: envelope.requestId,
            generation: envelope.generation,
          });
          this.reply(command, {
            case: 'source',
            value: sourceResultFor(call, envelope.buildId, payload),
          });
          break;
        }
        case 'acquireImage': {
          const acquiring = command.command.value;
          requireCondition(
            acquiring.request !== undefined,
            'Image request is required',
          );
          const request = acquiring.request;
          if (
            !this.manifest ||
            !this.manifest.sourceIds.includes(request.sourceId)
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
            request.sourceId,
            request.pageSessionId,
            request.pageKey,
            ports[0],
            acquiring.resourceId,
            { requestId: envelope.requestId, generation: envelope.generation },
          );
          this.reply(command, {
            case: 'image',
            value: create(pb.ProcessedImageSchema, result),
          });
          break;
        }
        case 'closePageSession': {
          if (!this.manifest || !this.driver.closePageSession)
            throw new RuntimeFailure(
              'unsupported_capability',
              'Page session control is not available',
            );
          const result = await this.driver.closePageSession(
            command.command.value.pageSessionId,
            { requestId: envelope.requestId, generation: envelope.generation },
          );
          this.reply(command, {
            case: 'closed',
            value: create(pb.ClosedSchema, result),
          });
          break;
        }
        case 'shutdown':
          this.controller.abort();
          await this.driver.close();
          this.reply(command, {
            case: 'closed',
            value: create(pb.ClosedSchema, { closed: true }),
          });
          break;
        default:
          throw new RuntimeFailure(
            'protocol_error',
            'A Worker command must be selected',
          );
      }
    } catch (error) {
      this.reply(command, {
        case: 'error',
        value: runtimeErrorMessage(runtimeFailure(error).toJSON()),
      });
    } finally {
      for (const port of ports) port.close();
      this.busy = false;
    }
  }

  private reply(
    command: WorkerCommand,
    result: pb.WorkerResponse['result'],
  ): void {
    this.send(
      encodeWorkerResponse(
        create(pb.WorkerResponseSchema, { envelope: command.envelope, result }),
      ),
    );
  }
}
