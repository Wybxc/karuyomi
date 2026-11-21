import {
  parseControlRequest,
  parseControlResponse,
  type ControlRequest,
} from '@karuyomi/contracts';
import type { ControlResponseJson } from '@karuyomi/protocol';

type Control = (input: unknown) => Promise<ControlResponseJson>;

export function readerBoundaryAcceptanceControl(control: Control): Control {
  let held = false;

  return async (input) => {
    let request: ControlRequest;
    try {
      request = parseControlRequest(input);
    } catch {
      return control(input);
    }
    const { command } = request;
    if (held || command.case !== 'invoke') return control(input);
    const { request: call, sourceId, requestId, generation } = command.value;
    const chapterUrl = call.case === 'pages' ? call.value.chapter?.url : null;
    if (sourceId !== '1538249443376436084' || chapterUrl !== '/3319/') {
      return control(input);
    }

    const response = await control(input);
    const { result } = parseControlResponse(response);
    const payload = result.case === 'source' ? result.value.payload : undefined;
    if (
      held ||
      payload?.case !== 'pageList' ||
      payload.value.pages.length === 0
    ) {
      return response;
    }
    held = true;
    const audit = (event: string) =>
      console.info(
        'ACCEPTANCE_RUNTIME_CONTROL',
        JSON.stringify({
          profile: 'reader-boundary',
          event,
          sourceId,
          chapterUrl,
          requestId,
          generation,
          pageSessionId: payload.value.pageSessionId,
          pages: payload.value.pages.length,
        }),
      );
    audit('pages-held');
    await new Promise<void>((resolve) => setTimeout(resolve, 18000));
    audit('pages-delivered');
    return response;
  };
}
