import { create } from '@bufbuild/protobuf';
import {
  encodeControlRequest,
  encodeControlResponse,
  parseControlRequest,
  parseControlResponse,
} from '@karuyomi/contracts';
import {
  ControlRequestSchema,
  ControlResponseSchema,
  EmptySchema,
  RuntimeErrorCode,
  RuntimeErrorSchema,
  type ControlResponseJson,
} from '@karuyomi/protocol';

type Control = (input: unknown) => Promise<ControlResponseJson>;

export function filterAcceptanceControl(
  control: Control,
  outcome: string | null,
): Control {
  let reads = 0;
  let applications = 0;
  const pending = new Set<string>();
  const identity = (slot: number, generation: string, requestId: string) =>
    JSON.stringify([slot, generation, requestId]);
  const audit = (event: string, fields: Record<string, unknown>) =>
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({ profile: 'filters', event, ...fields }),
    );

  return async (input) => {
    let request: ReturnType<typeof parseControlRequest>;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command, slotId } = request;
    if (command.case === 'cancel') {
      const { requestId, generation } = command.value;
      const observed = pending.has(identity(slotId, generation, requestId));
      const response = await control(input);
      if (observed) {
        audit('cancel', {
          requestId,
          generation,
          hostResult: parseControlResponse(response).result.case,
        });
      }
      return response;
    }
    if (command.case !== 'invoke') return control(input);
    const { requestId, generation, request: source } = command.value;
    const read = source.case === 'getFilters';
    const apply =
      source.case === 'search' && source.value.filters !== undefined;
    if (!read && !apply) return control(input);

    const operation = read ? 'getFilters' : 'apply';
    const attempt = read ? ++reads : ++applications;
    const key = identity(slotId, generation, requestId);
    pending.add(key);
    try {
      const response = await control(input);
      const result = parseControlResponse(response).result;
      const payload =
        result.case === 'source' ? result.value.payload : undefined;
      audit('held', {
        operation,
        attempt,
        requestId,
        generation,
        hostResult: result.case,
        nodes:
          payload?.case === 'filters' ? payload.value.nodes.length : undefined,
        items:
          payload?.case === 'mangaPage'
            ? payload.value.mangas.length
            : undefined,
        retainedSnapshotId:
          source.case === 'getFilters'
            ? source.value.retainedSnapshotId
            : undefined,
        selectedSnapshotId:
          source.case === 'search'
            ? source.value.filters?.snapshotId
            : undefined,
      });
      await new Promise<void>((resolve) => setTimeout(resolve, 8000));
      const loseDescription =
        read &&
        ((outcome === 'read-error' && attempt === 1) ||
          (outcome === 'reset-error' && attempt === 2));
      const retire = read && outcome === 'retire' && attempt === 2;
      if (retire) {
        const reset = await control(
          encodeControlRequest(
            create(ControlRequestSchema, {
              requestId: 'acceptance-retire-' + requestId,
              slotId,
              command: { case: 'rebuild', value: create(EmptySchema) },
            }),
          ),
        );
        const released = parseControlResponse(reset).result;
        if (released.case !== 'completed' || !released.value.completed) {
          throw new Error(
            'Acceptance fixture did not retire the Source runtime',
          );
        }
      }
      audit('delivered', {
        operation,
        attempt,
        requestId,
        generation,
        outcome: retire
          ? 'retired'
          : loseDescription
            ? 'rejected'
            : result.case,
      });
      if (!retire && !loseDescription) return response;
      return encodeControlResponse(
        create(ControlResponseSchema, {
          requestId: request.requestId,
          slotId,
          result: {
            case: 'error',
            value: create(RuntimeErrorSchema, {
              code: retire
                ? RuntimeErrorCode.RUNTIME_LOST
                : RuntimeErrorCode.SOURCE_ERROR,
              message: retire
                ? 'Acceptance retired the Source generation'
                : 'Acceptance could not deliver the Source filter description',
            }),
          },
        }),
      );
    } finally {
      pending.delete(key);
    }
  };
}
