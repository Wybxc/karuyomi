import {
  parseControlRequest,
  encodeControlResponse,
  runtimeErrorMessage,
  plain,
  catalogReferenceSchema,
  messageJson,
} from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import type { SourceRuntimeManager } from './manager.js';

export function installRuntime(
  foreground: SourceRuntimeManager,
  createSearch: () => SourceRuntimeManager,
): RuntimeHostApi {
  if (window.karuyomiRuntime) return window.karuyomiRuntime;
  const api = Object.freeze(createRuntimeApi(foreground, createSearch));
  window.karuyomiRuntime = api;
  window.addEventListener(
    'pagehide',
    () => {
      void api.dispose();
    },
    { once: true },
  );
  return api;
}

export type RuntimeHostApi = ReturnType<typeof createRuntimeApi>;
function createRuntimeApi(
  foreground: SourceRuntimeManager,
  createSearch: () => SourceRuntimeManager,
) {
  let search: SourceRuntimeManager | undefined;
  let searchClosing: Promise<void> | undefined;
  let disposed = false;
  let disposing: Promise<void> | undefined;
  let rebuilding: Promise<void> | undefined;
  const existingManagers = () => (search ? [foreground, search] : [foreground]);
  const eachManager = async (
    action: (manager: SourceRuntimeManager) => Promise<void>,
  ) => {
    const results = await Promise.allSettled(existingManagers().map(action));
    for (const result of results)
      if (result.status === 'rejected') throw result.reason;
  };
  const closeSearch = (manager: SourceRuntimeManager) => {
    if (searchClosing) return searchClosing;
    const closing = manager.dispose().finally(() => {
      if (search === manager) search = undefined;
      if (searchClosing === closing) searchClosing = undefined;
    });
    searchClosing = closing;
    return closing;
  };
  return {
    rebuild(): Promise<void> {
      if (disposed)
        return Promise.reject(
          new RuntimeFailure('runtime_lost', 'Runtime container is disposed'),
        );
      if (rebuilding) return rebuilding;
      const operation = (async () => {
        await searchClosing;
        await eachManager((manager) => manager.rebuild());
      })().finally(() => {
        if (rebuilding === operation) rebuilding = undefined;
      });
      rebuilding = operation;
      return operation;
    },
    dispose(): Promise<void> {
      disposed = true;
      return (disposing ??= eachManager((manager) => manager.dispose()));
    },
    async control(input: unknown): Promise<pb.ControlResponseJson> {
      let requestId = 'invalid-control';
      let slotId = pb.RuntimeSlot.UNSPECIFIED;
      let command: pb.ControlRequest['command']['case'];
      let generation: string | undefined;
      let sourceRequestId: string | undefined;
      let sourceOperation: pb.SourceCall['request']['case'];
      // Correlate malformed requests when their transport identity is readable;
      // all command structure is still owned by the generated parser below.
      if (
        input !== null &&
        typeof input === 'object' &&
        'requestId' in input &&
        typeof input.requestId === 'string' &&
        input.requestId.length > 0 &&
        input.requestId.length <= 200
      )
        requestId = input.requestId;
      if (input !== null && typeof input === 'object' && 'slotId' in input) {
        if (
          input.slotId === pb.RuntimeSlot.FOREGROUND ||
          input.slotId === 'RUNTIME_SLOT_FOREGROUND'
        )
          slotId = pb.RuntimeSlot.FOREGROUND;
        else if (
          input.slotId === pb.RuntimeSlot.SEARCH ||
          input.slotId === 'RUNTIME_SLOT_SEARCH'
        )
          slotId = pb.RuntimeSlot.SEARCH;
      }
      let result: pb.ControlResponse['result'];
      try {
        const request = parseControlRequest(input);
        requestId = request.requestId;
        slotId = request.slotId;
        command = request.command.case;
        if (request.command.case === 'invoke') {
          sourceRequestId = request.command.value.requestId;
          sourceOperation = request.command.value.request.case;
        }
        if (
          request.command.value &&
          'generation' in request.command.value &&
          typeof request.command.value.generation === 'string'
        )
          generation = request.command.value.generation;
        if (disposed || rebuilding)
          throw new RuntimeFailure(
            'runtime_lost',
            'Runtime container is unavailable',
          );
        if (slotId === pb.RuntimeSlot.SEARCH) {
          // A concurrent dispose can publish its promise while this await yields.
          // Recheck before selecting the manager so an open never reuses it.
          do {
            await searchClosing;
          } while (searchClosing);
        }
        if (disposed || rebuilding)
          throw new RuntimeFailure(
            'runtime_lost',
            'Runtime container is unavailable',
          );
        const manager =
          slotId === pb.RuntimeSlot.FOREGROUND
            ? foreground
            : (search ??= createSearch());
        switch (request.command.case) {
          case 'ready':
            result = {
              case: 'hello',
              value: create(pb.RuntimeHelloSchema, await manager.ready),
            };
            break;
          case 'open': {
            const session = await manager.open({
              ...plain(request.command.value),
              catalog: catalogReferenceSchema.parse(
                messageJson(
                  pb.CatalogReferenceSchema,
                  create(
                    pb.CatalogReferenceSchema,
                    request.command.value.catalog,
                  ),
                ),
              ),
            });
            result = {
              case: 'session',
              value: create(pb.RuntimeSessionSchema, {
                ...session,
                capabilities:
                  slotId === pb.RuntimeSlot.SEARCH
                    ? session.capabilities.filter(
                        (capability) =>
                          capability !== 'source-preferences' &&
                          capability !== 'processed-image-resources',
                      )
                    : session.capabilities,
              }),
            };
            break;
          }
          case 'invoke':
            result = {
              case: 'source',
              value: await manager.invoke(request.command.value),
            };
            break;
          case 'cancel':
            await manager.cancel(
              request.command.value.requestId,
              request.command.value.generation,
            );
            result = {
              case: 'completed',
              value: create(pb.CompletedSchema, { completed: true }),
            };
            break;
          case 'acquireImage':
            result = {
              case: 'image',
              value: create(
                pb.ImageResourceSchema,
                await manager.acquireImage(plain(request.command.value)),
              ),
            };
            break;
          case 'cancelImage':
            result = {
              case: 'released',
              value: create(
                pb.ReleasedSchema,
                await manager.cancelImage(plain(request.command.value)),
              ),
            };
            break;
          case 'releaseImage':
            result = {
              case: 'released',
              value: create(
                pb.ReleasedSchema,
                await manager.releaseImage(plain(request.command.value)),
              ),
            };
            break;
          case 'closePageSession':
            result = {
              case: 'closed',
              value: create(
                pb.ClosedSchema,
                await manager.closePageSession(plain(request.command.value)),
              ),
            };
            break;
          case 'prepareBuild':
            result = {
              case: 'preparedBuild',
              value: await manager.prepareBuild(request.command.value),
            };
            break;
          case 'cancelPreparation':
            await manager.cancelPreparation(
              request.command.value.preparationId,
            );
            result = {
              case: 'completed',
              value: create(pb.CompletedSchema, { completed: true }),
            };
            break;
          case 'extensionCache':
            result = {
              case: 'extensionCache',
              value: await manager.extensionCache(),
            };
            break;
          case 'forgetExtensionArtifact':
            await manager.forgetExtensionArtifact(request.command.value.sha256);
            result = {
              case: 'completed',
              value: create(pb.CompletedSchema, { completed: true }),
            };
            break;
          case 'closeBuild':
            result = {
              case: 'closed',
              value: create(
                pb.ClosedSchema,
                await manager.closeBuild(request.command.value),
              ),
            };
            break;
          case 'rebuild':
            await manager.rebuild();
            result = {
              case: 'completed',
              value: create(pb.CompletedSchema, { completed: true }),
            };
            break;
          case 'fetchApi':
            result = {
              case: 'api',
              value: create(
                pb.ApiFetchResponseSchema,
                await manager.fetchApi(plain(request.command.value)),
              ),
            };
            break;
          case 'dispose':
            if (slotId === pb.RuntimeSlot.SEARCH) await closeSearch(manager);
            else await manager.dispose();
            result = {
              case: 'completed',
              value: create(pb.CompletedSchema, { completed: true }),
            };
            break;
          default:
            throw new RuntimeFailure(
              'protocol_error',
              'A control command must be selected',
            );
        }
      } catch (error) {
        const failure =
          error instanceof RuntimeFailure
            ? error
            : new RuntimeFailure(
                'protocol_error',
                'Invalid runtime control request',
              );
        if (
          import.meta.env.VITE_KARUYOMI_RUNTIME_DIAGNOSTICS === '1' &&
          ['runtime_lost', 'timeout', 'protocol_error'].includes(failure.code)
        )
          console.warn(
            'Karuyomi runtime control failed',
            JSON.stringify({
              requestId,
              slotId,
              command,
              generation,
              sourceRequestId,
              sourceOperation,
              code: failure.code,
              deadlineExceeded:
                failure.code === 'timeout' &&
                failure.message ===
                  'Source request deadline exceeded; the Worker was recycled',
            }),
          );
        if (slotId === pb.RuntimeSlot.UNSPECIFIED) throw failure;
        result = {
          case: 'error',
          value: runtimeErrorMessage(runtimeFailure(failure).toJSON()),
        };
      }
      return encodeControlResponse(
        create(pb.ControlResponseSchema, { requestId, slotId, result }),
      );
    },
  };
}

declare global {
  interface Window {
    karuyomiRuntime?: RuntimeHostApi;
  }
}
