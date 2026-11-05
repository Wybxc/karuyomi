import { BusinessStateErrorCode as ErrorCode } from '@karuyomi/protocol';
import { BUSINESS_REQUEST_LIMIT } from '@karuyomi/contracts';
import { StateError } from './state-store.js';

export async function requestJson(request: Request): Promise<unknown> {
  if (!request.headers.get('Content-Type')?.startsWith('application/json')) {
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'JSON content type is required',
    );
  }
  const length = request.headers.get('Content-Length');
  if (length && Number(length) > BUSINESS_REQUEST_LIMIT)
    throw new StateError(
      ErrorCode.LIMIT_EXCEEDED,
      'Mutation body is too large',
      413,
    );
  const reader = request.body?.getReader();
  if (!reader)
    throw new StateError(ErrorCode.INVALID_INPUT, 'Mutation body is required');
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  let bytes = 0;
  let text = '';
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > BUSINESS_REQUEST_LIMIT) {
        await reader.cancel();
        throw new StateError(
          ErrorCode.LIMIT_EXCEEDED,
          'Mutation body is too large',
          413,
        );
      }
      text += decoder.decode(chunk.value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } finally {
    reader.releaseLock();
  }
}

export function stateFailure(error: unknown) {
  const failure =
    error instanceof StateError
      ? error
      : new StateError(
          ErrorCode.UNAVAILABLE,
          'State is unavailable; retry with the same mutation ID',
          503,
        );
  return {
    status: failure.status,
    error: {
      code: failure.code,
      message: failure.message,
      retryable: failure.status === 503,
    },
  };
}
