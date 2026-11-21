import { create } from '@bufbuild/protobuf';
import {
  encodeControlResponse,
  parseControlRequest,
  parseControlResponse,
  type ControlRequest,
} from '@karuyomi/contracts';
import {
  ControlResponseSchema,
  RuntimeErrorCode,
  RuntimeErrorSchema,
  type ControlResponseJson,
  type RuntimeSlot,
} from '@karuyomi/protocol';

type Control = (input: unknown) => Promise<ControlResponseJson>;

export function searchRetirementAcceptanceControl(control: Control): Control {
  let old:
    | {
        requestId: string;
        generation: string;
        buildId: string;
        slot: RuntimeSlot;
      }
    | undefined;
  let closeHeld = false;
  let resets = 0;
  let released = false;
  const delay = (ms: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, ms));
  const audit = (event: string, fields: Record<string, unknown>) =>
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({ profile: 'retire-search', event, ...fields }),
    );
  const reject = (request: ControlRequest, code: RuntimeErrorCode) =>
    encodeControlResponse(
      create(ControlResponseSchema, {
        requestId: request.requestId,
        slotId: request.slotId,
        result: {
          case: 'error',
          value: create(RuntimeErrorSchema, {
            code,
            message: 'Acceptance withheld the previous search scope',
          }),
        },
      }),
    );

  return async (input) => {
    let request: ControlRequest;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command, slotId: slot } = request;
    if (
      command.case === 'invoke' &&
      command.value.sourceId === '792932060924485302' &&
      command.value.requestId.startsWith('search-') &&
      command.value.request.case === 'search' &&
      command.value.request.value.query === '航海王'
    ) {
      const response = await control(input);
      const result = parseControlResponse(response).result;
      if (
        result.case !== 'source' ||
        result.value.payload.case !== 'mangaPage' ||
        result.value.payload.value.mangas.length === 0
      )
        return response;
      const { requestId, generation, buildId } = result.value;
      const items = result.value.payload.value.mangas.length;
      if (!old) {
        old = { requestId, generation, buildId, slot };
        audit('access-required', { ...old, items });
        return reject(request, RuntimeErrorCode.ACCESS_REQUIRED);
      }
      audit('new-search', {
        requestId,
        generation,
        buildId,
        slot,
        items,
        released,
      });
      return response;
    }
    if (!old || slot !== old.slot || released) return control(input);
    const scope = old;
    if (
      command.case === 'closeBuild' &&
      command.value.generation === scope.generation &&
      command.value.buildId === scope.buildId &&
      !closeHeld
    ) {
      closeHeld = true;
      const response = await control(input);
      const result = parseControlResponse(response).result;
      if (result.case !== 'closed' || !result.value.closed) {
        throw new Error('Acceptance requires a real close acknowledgement');
      }
      audit('close-held', { ...scope, controlId: request.requestId });
      await delay(8000);
      audit('close-unconfirmed', { ...scope, controlId: request.requestId });
      return reject(request, RuntimeErrorCode.RUNTIME_LOST);
    }
    if (command.case === 'rebuild' && closeHeld) {
      const response = await control(input);
      const result = parseControlResponse(response).result;
      if (result.case !== 'completed' || !result.value.completed) {
        throw new Error('Acceptance requires a real reset acknowledgement');
      }
      const attempt = ++resets;
      if (attempt >= 3) {
        await delay(3000);
        released = true;
      }
      audit('reset', {
        ...scope,
        controlId: request.requestId,
        attempt,
        acknowledgementDelivered: released,
      });
      return released
        ? response
        : reject(request, RuntimeErrorCode.RUNTIME_LOST);
    }
    return control(input);
  };
}
