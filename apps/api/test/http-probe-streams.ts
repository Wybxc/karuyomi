import assert from 'node:assert/strict';
import { ReadableStream } from 'node:stream/web';
import {
  HTTP_FRAME_LIMIT,
  HttpFrameReader,
  HttpFrameError,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  encodeErrorFrame,
} from '../../../packages/contracts/src/http-frames.ts';

// Re-encode one demanded DATA frame at a time. Using the shared strict reader
// keeps observation on the same pull path: no tee, detached reader or full-body
// aggregation can consume ahead of the browser/workerd consumer.
export function byteStream(source: {
  getReader(): {
    read(): Promise<{ done?: boolean; value?: unknown }>;
    cancel(reason?: unknown): Promise<void>;
    releaseLock(): void;
  };
}): ReadableStream<Uint8Array> {
  const reader = source.getReader();
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    reader.releaseLock();
  };
  const stop = async (reason?: unknown) => {
    if (released) return;
    try {
      await reader.cancel(reason);
    } catch {
      /* original read error is retained */
    } finally {
      release();
    }
  };
  return new ReadableStream<Uint8Array>(
    {
      async pull(controller) {
        try {
          const result = await reader.read();
          if (result.done) {
            release();
            controller.close();
          } else {
            assert(
              result.value instanceof Uint8Array,
              'Expected a binary stream',
            );
            controller.enqueue(result.value);
          }
        } catch (error) {
          await stop(error);
          controller.error(error);
        }
      },
      async cancel(reason) {
        await stop(reason);
      },
    },
    { highWaterMark: 0 },
  );
}

export function relayFrames(
  reader: HttpFrameReader,
  meta: unknown,
  onData: (data: Uint8Array) => void = () => {},
  finish: (error?: unknown) => Promise<void> = async () => {},
): ReadableStream<Uint8Array> {
  const prefix = [encodePreamble(), encodeMetaFrame(meta)];
  let remainder: Uint8Array | undefined;
  let completed = false;
  const complete = async (error?: unknown) => {
    if (completed) return;
    completed = true;
    await finish(error);
  };
  return new ReadableStream<Uint8Array>(
    {
      async pull(controller) {
        try {
          let frame = remainder ?? prefix.shift();
          if (!frame) {
            const data = await reader.read(HTTP_FRAME_LIMIT);
            if (data === null) {
              await complete();
              controller.enqueue(encodeEndFrame(reader.bytesRead));
              controller.close();
              return;
            }
            onData(data);
            frame = encodeDataFrame(data);
          }
          remainder =
            frame.byteLength > HTTP_FRAME_LIMIT
              ? frame.subarray(HTTP_FRAME_LIMIT)
              : undefined;
          controller.enqueue(frame.subarray(0, HTTP_FRAME_LIMIT));
        } catch (error) {
          void reader.cancel(error).catch(() => {});
          await complete(error);
          controller.enqueue(
            encodeErrorFrame({
              code:
                error instanceof HttpFrameError
                  ? error.code
                  : 'probe_stream_failed',
              message:
                error instanceof HttpFrameError && error.remote
                  ? error.message
                  : 'Framed probe stream failed',
            }),
          );
          controller.close();
        }
      },
      async cancel(reason) {
        void reader.cancel(reason).catch(() => {});
        await complete(new Error('cancelled'));
      },
    },
    { highWaterMark: 0 },
  );
}
