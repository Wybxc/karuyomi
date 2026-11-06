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

export function installRuntime(manager: SourceRuntimeManager): RuntimeHostApi {
  if (window.karuyomiRuntime) return window.karuyomiRuntime;
  const api = Object.freeze(createRuntimeApi(manager));
  window.karuyomiRuntime = api;
  window.addEventListener(
    'pagehide',
    () => {
      void manager.dispose();
    },
    { once: true },
  );
  return api;
}

export type RuntimeHostApi = ReturnType<typeof createRuntimeApi>;
function createRuntimeApi(manager: SourceRuntimeManager) {
  return {
    async control(input: unknown): Promise<pb.ControlResponseJson> {
      let requestId = 'invalid-control';
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
      let result: pb.ControlResponse['result'];
      try {
        const request = parseControlRequest(input);
        requestId = request.requestId;
        switch (request.command.case) {
          case 'ready':
            result = {
              case: 'hello',
              value: create(pb.RuntimeHelloSchema, await manager.ready),
            };
            break;
          case 'open':
            result = {
              case: 'session',
              value: create(
                pb.RuntimeSessionSchema,
                await manager.open({
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
                }),
              ),
            };
            break;
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
            await manager.dispose();
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
        result = {
          case: 'error',
          value: runtimeErrorMessage(runtimeFailure(failure).toJSON()),
        };
      }
      return encodeControlResponse(
        create(pb.ControlResponseSchema, { requestId, result }),
      );
    },
  };
}

declare global {
  interface Window {
    karuyomiRuntime?: RuntimeHostApi;
  }
}
