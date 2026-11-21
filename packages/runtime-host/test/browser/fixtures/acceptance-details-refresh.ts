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
type DetailRead = 'details' | 'chapters';

export function detailsRefreshAcceptanceControl(
  control: Control,
  refusedRead: DetailRead,
): Control {
  const initialReads = new Set<DetailRead>();
  let initialGeneration: string | undefined;
  let refused = false;

  return async (input) => {
    let request: ControlRequest;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command } = request;
    if (command.case !== 'invoke') return control(input);
    const { request: call, sourceId, generation, requestId } = command.value;
    if (
      sourceId !== '1538249443376436084' ||
      (call.case !== 'details' && call.case !== 'chapters') ||
      call.value.manga?.url !== 'SINGLE'
    ) {
      return control(input);
    }

    const response = await control(input);
    const { result } = parseControlResponse(response);
    const payload = result.case === 'source' ? result.value.payload : undefined;
    const ready =
      payload?.case === (call.case === 'details' ? 'manga' : 'chapters');
    let reject = false;
    if (ready) {
      initialGeneration ??= generation;
      if (generation === initialGeneration) {
        // Let the initial detail view finish both real reads.
        reject =
          !refused && initialReads.size === 2 && call.case === refusedRead;
        initialReads.add(call.case);
        refused ||= reject;
      }
    }
    if (reject) {
      // Keep the real in-progress UI visible in the isolated acceptance build.
      await new Promise<void>((resolve) => setTimeout(resolve, 2400));
    }
    console.info(
      'ACCEPTANCE_RUNTIME_CONTROL',
      JSON.stringify({
        profile: 'details-refresh',
        operation: call.case,
        requestId,
        sourceId,
        generation,
        mangaUrl: call.value.manga.url,
        items:
          payload?.case === 'chapters'
            ? payload.value.chapters.length
            : undefined,
        hostResult: result.case,
        outcome: reject ? 'rejected' : result.case,
      }),
    );
    return reject
      ? encodeControlResponse(
          create(ControlResponseSchema, {
            requestId: request.requestId,
            slotId: request.slotId,
            result: {
              case: 'error',
              value: create(RuntimeErrorSchema, {
                code: RuntimeErrorCode.SOURCE_ERROR,
                message: 'Acceptance withheld the refreshed xkcd result',
              }),
            },
          }),
        )
      : response;
  };
}
