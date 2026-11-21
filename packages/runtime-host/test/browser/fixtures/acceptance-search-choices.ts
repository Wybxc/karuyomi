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

export function searchChoicesAcceptanceControl(control: Control): Control {
  const mangaDexEnglish = '2499283573021220255';
  const xkcdEnglish = '1538249443376436084';
  const held = new Set<string>();

  return async (input) => {
    let request: ControlRequest;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command, requestId: controlId, slotId } = request;
    if (command.case !== 'invoke') return control(input);
    const {
      sourceId,
      requestId,
      generation,
      request: sourceCall,
    } = command.value;
    if (
      (sourceId !== mangaDexEnglish && sourceId !== xkcdEnglish) ||
      sourceCall.case !== 'search' ||
      sourceCall.value.query !== 'one piece' ||
      sourceCall.value.page !== 1 ||
      !requestId.startsWith('search-') ||
      held.has(sourceId)
    ) {
      return control(input);
    }
    held.add(sourceId);
    const real = await control(input);
    const result = parseControlResponse(real).result;
    const audit = (stage: string) =>
      console.info(
        'ACCEPTANCE_RUNTIME_CONTROL',
        JSON.stringify({
          profile: 'search-choices',
          stage,
          sourceId,
          requestId,
          generation,
          real: result.case,
          items:
            result.case === 'source' &&
            result.value.payload.case === 'mangaPage'
              ? result.value.payload.value.mangas.length
              : 0,
        }),
      );
    if (result.case !== 'source' || result.value.payload.case !== 'mangaPage') {
      audit('actual-failure');
      return real;
    }
    audit('buffered');
    await new Promise<void>((resolve) =>
      setTimeout(resolve, sourceId === xkcdEnglish ? 9000 : 10500),
    );
    if (sourceId === mangaDexEnglish) {
      audit('delivered');
      return real;
    }
    audit('rejected');
    return encodeControlResponse(
      create(ControlResponseSchema, {
        requestId: controlId,
        slotId,
        result: {
          case: 'error',
          value: create(RuntimeErrorSchema, {
            code: RuntimeErrorCode.SOURCE_ERROR,
            message: 'Controlled language-page search failure',
          }),
        },
      }),
    );
  };
}
