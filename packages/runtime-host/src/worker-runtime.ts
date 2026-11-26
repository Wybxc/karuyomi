import {
  protocolVersion,
  workerCommandSchema,
  buildManifestSchema,
  messageJson,
  encodeWorkerResponse,
  runtimeErrorMessage,
  sourceResultFor,
  requireCondition,
  catalogReferenceSchema,
  type BuildManifest,
  type SourceInputFields,
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
  private preferenceEdit: { sourceId: string; snapshotId?: string } | undefined;
  private controller = new AbortController();
  private input:
    | { prompt: pb.SourceInputPrompt; resolve(text: string | null): void }
    | undefined;

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
    if (command.command.case === 'answerSourceInput') {
      for (const port of ports) port.close();
      const answer = command.command.value;
      const pending = this.input;
      if (
        pending &&
        pending.prompt.requestId === answer.requestId &&
        pending.prompt.promptId === answer.promptId &&
        !(pending.prompt.required && answer.text === '')
      ) {
        this.input = undefined;
        pending.resolve(answer.text ?? null);
      }
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
          const catalog = catalogReferenceSchema.parse(
            messageJson(
              pb.CatalogReferenceSchema,
              create(pb.CatalogReferenceSchema, opening.catalog),
            ),
          );
          requireCondition(
            manifest.repoId === catalog.repoId,
            'Worker catalog mismatch',
          );
          this.generation = envelope.generation;
          this.manifest = manifest;
          const sources = await this.driver.open(
            manifest,
            opening.userAgent,
            this.controller.signal,
            catalog,
            { requestId: envelope.requestId, generation: envelope.generation },
            opening.preferenceBootstrap,
          );
          this.reply(command, {
            case: 'session',
            value: create(pb.RuntimeSessionSchema, {
              protocolVersion,
              workerInstanceId: this.workerInstanceId,
              generation: envelope.generation,
              buildId: envelope.buildId,
              catalog,
              sources,
              capabilities: [
                'source-rpc',
                'explicit-references',
                'complete-dto',
                'source-preferences',
                'cancel-by-worker-recycle',
                ...(this.driver.acquireImage && this.driver.closePageSession
                  ? ['processed-image-resources']
                  : []),
                ...(this.driver.supportsCoverImages
                  ? ['cover-image-resources']
                  : []),
                ...(manifest.supportsSourceInput ? ['source-input'] : []),
              ],
            }),
          });
          break;
        }
        case 'invoke': {
          const call = command.command.value;
          this.requireConfirmedPreferences(call);
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
          if (call.request.case === 'editPreference')
            this.preferenceEdit = { sourceId: call.sourceId };
          const payload = await this.driver.invoke(
            call,
            {
              requestId: envelope.requestId,
              generation: envelope.generation,
            },
            call.allowInput && this.manifest.supportsSourceInput
              ? (fields) => this.requestInput(command, call.sourceId, fields)
              : undefined,
          );
          const value = sourceResultFor(call, envelope.buildId, payload);
          this.reply(command, { case: 'source', value });
          if (
            value.payload.case === 'preferenceEdit' &&
            value.payload.value.snapshot
          ) {
            this.preferenceEdit = {
              sourceId: call.sourceId,
              snapshotId: value.payload.value.snapshot.snapshotId,
            };
          }
          break;
        }
        case 'acquireImage': {
          this.requireConfirmedPreferences();
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
          if (ports.length !== 1 || !ports[0])
            throw new RuntimeFailure(
              'unsupported_capability',
              'Image channel is not available',
            );
          const context = {
            requestId: envelope.requestId,
            generation: envelope.generation,
          };
          if (!this.driver.acquireImage)
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
            context,
            request.thumbnailUrl,
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
      this.input?.resolve(null);
      this.input = undefined;
      for (const port of ports) port.close();
      this.busy = false;
    }
  }

  private async requestInput(
    command: WorkerCommand,
    sourceId: string,
    fields: SourceInputFields,
  ): Promise<string | null> {
    if (this.input)
      throw new RuntimeFailure(
        'protocol_error',
        'A Source input prompt is already active',
      );
    const { requestId, generation, buildId } = command.envelope;
    const prompt = create(pb.SourceInputPromptSchema, {
      ...fields,
      requestId,
      generation,
      buildId,
      sourceId,
      promptId: crypto.randomUUID(),
    });
    return new Promise((resolve, reject) => {
      this.input = { prompt, resolve };
      try {
        this.reply(command, { case: 'sourceInput', value: prompt });
      } catch (error) {
        this.input = undefined;
        reject(error);
      }
    });
  }

  private requireConfirmedPreferences(call?: pb.SourceCall): void {
    if (
      this.preferenceEdit &&
      (call?.request.case !== 'editPreference' ||
        call.sourceId !== this.preferenceEdit.sourceId ||
        call.request.value.snapshotId !== this.preferenceEdit.snapshotId)
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Confirm Source preferences and reopen the runtime before continuing',
      );
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
