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
} from '@karuyomi/protocol';

type Control = (input: unknown) => Promise<ControlResponseJson>;

export function migrationAcceptanceControl(
  control: Control,
  rejectBuild: string,
  listingSource: string,
): Control {
  let rejectedOpen = false;
  const rejectedPages = new Set<string>();
  const audit = (entry: Record<string, unknown>) =>
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({ profile: 'migration', ...entry }),
    );
  const reject = (request: ControlRequest) =>
    encodeControlResponse(
      create(ControlResponseSchema, {
        requestId: request.requestId,
        slotId: request.slotId,
        result: {
          case: 'error',
          value: create(RuntimeErrorSchema, {
            code: RuntimeErrorCode.SOURCE_ERROR,
            message: 'Acceptance withheld the migration target',
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
    const { command } = request;
    if (
      command.case === 'open' &&
      command.value.expectedBuildId === rejectBuild
    ) {
      const identity = {
        operation: 'open',
        requestId: request.requestId,
        buildId: rejectBuild,
      };
      if (!rejectedOpen) {
        rejectedOpen = true;
        audit({ ...identity, outcome: 'rejected' });
        return reject(request);
      }
      const response = await control(input);
      audit({
        ...identity,
        outcome: parseControlResponse(response).result.case,
      });
      return response;
    }
    if (command.case !== 'invoke' || command.value.sourceId !== listingSource) {
      return control(input);
    }
    const { request: call, generation, requestId, sourceId } = command.value;
    if (call.case !== 'search' && call.case !== 'popular')
      return control(input);

    const response = await control(input);
    const result = parseControlResponse(response).result;
    const page = call.value.page;
    const payload = result.case === 'source' ? result.value.payload : undefined;
    const items =
      payload?.case === 'mangaPage' ? payload.value.mangas.length : 0;
    const rejected = page === 2 && items > 0 && !rejectedPages.has(call.case);
    if (rejected) rejectedPages.add(call.case);
    audit({
      operation: call.case,
      requestId,
      generation,
      sourceId,
      page,
      query: call.case === 'search' ? call.value.query : undefined,
      items,
      hostResult: result.case,
      outcome: rejected ? 'rejected' : result.case,
    });
    return rejected ? reject(request) : response;
  };
}
