import { describe, expect, it, vi } from 'vitest';
import { Readable, Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  HTTP_FRAME_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
} from '@karuyomi/contracts';
import { byteStream, relayFrames } from './http-probe-streams.ts';

describe('Source probe streaming adapters', () => {
  function fixture(end = true) {
    let pulls = 0;
    const cancel = vi.fn();
    const bytes = new Uint8Array(HTTP_FRAME_LIMIT).fill(255);
    const wire = [
      encodePreamble(),
      encodeMetaFrame({ fixture: true }),
      encodeDataFrame(bytes),
      encodeDataFrame(bytes),
    ];
    if (end) wire.push(encodeEndFrame(bytes.length * 2));
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          ++pulls;
          const chunk = wire.shift();
          if (chunk) controller.enqueue(chunk);
          else controller.close();
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    return { source, bytes, cancel, pulls: () => pulls };
  }

  it('converts Node/Web binary streams without pulling ahead', async () => {
    const upstream = fixture();
    const wrapped = byteStream(upstream.source);
    expect(upstream.pulls()).toBe(0);
    const reader = wrapped.getReader();
    expect((await reader.read()).value).toEqual(encodePreamble());
    await Promise.resolve();
    expect(upstream.pulls()).toBe(1);
    await reader.cancel();
    expect(upstream.cancel).toHaveBeenCalledOnce();
  });

  it('rejects a nonbinary Node/Web stream value at the boundary', async () => {
    const cancel = vi.fn();
    const source = new ReadableStream({
      start(controller) {
        controller.enqueue('not binary');
      },
      cancel,
    });
    await expect(byteStream(source).getReader().read()).rejects.toThrow(
      'Expected a binary stream',
    );
    expect(cancel).toHaveBeenCalledOnce();
    expect(source.locked).toBe(false);
  });

  it('releases the original reader after a read error even when cancel rejects', async () => {
    const cancel = vi.fn(async () => {
      throw new Error('cancel failed');
    });
    const releaseLock = vi.fn();
    const stream = byteStream({
      getReader: () => ({
        read: async () => {
          throw new Error('original read failed');
        },
        cancel,
        releaseLock,
      }),
    });
    const reader = stream.getReader();
    await expect(reader.read()).rejects.toThrow('original read failed');
    await reader.cancel().catch(() => {});
    expect(cancel).toHaveBeenCalledOnce();
    expect(releaseLock).toHaveBeenCalledOnce();
  });

  it('observes DATA only when the downstream consumer asks, preserving partial frames', async () => {
    const upstream = fixture();
    const input = new HttpFrameReader(upstream.source, HTTP_FRAME_LIMIT * 2);
    const meta = await input.meta();
    const data = vi.fn();
    const finish = vi.fn(async () => {});
    const output = new HttpFrameReader(
      relayFrames(input, meta, data, finish),
      HTTP_FRAME_LIMIT * 2,
    );
    expect(await output.meta()).toEqual(meta);
    expect(upstream.pulls()).toBe(2);
    expect(await output.read(1)).toEqual(new Uint8Array([255]));
    await Promise.resolve();
    expect(upstream.pulls()).toBe(3);
    expect(data).toHaveBeenCalledOnce();
    let total = 1;
    for (;;) {
      const chunk = await output.read(HTTP_FRAME_LIMIT);
      if (chunk === null) break;
      total += chunk.length;
    }
    expect(total).toBe(HTTP_FRAME_LIMIT * 2);
    expect(finish).toHaveBeenCalledOnce();
    expect(finish).toHaveBeenCalledWith(undefined);
  });

  it('relays missing END as terminal ERROR rather than fabricating success', async () => {
    const upstream = fixture(false);
    const input = new HttpFrameReader(upstream.source, HTTP_FRAME_LIMIT * 2);
    const finish = vi.fn(async (_error?: unknown) => {});
    const output = new HttpFrameReader(
      relayFrames(input, await input.meta(), () => {}, finish),
      HTTP_FRAME_LIMIT * 2,
    );
    await output.meta();
    expect((await output.read(HTTP_FRAME_LIMIT))?.length).toBe(
      HTTP_FRAME_LIMIT,
    );
    expect((await output.read(HTTP_FRAME_LIMIT))?.length).toBe(
      HTTP_FRAME_LIMIT,
    );
    await expect(output.read(1)).rejects.toMatchObject({
      code: 'protocol_error',
      remote: true,
    });
    expect(finish).toHaveBeenCalledOnce();
    expect(finish.mock.calls[0]?.[0]).toBeInstanceOf(Error);
  });

  it('aborting a backpressured Node pipeline cancels the same framed reader', async () => {
    const upstream = fixture();
    const input = new HttpFrameReader(upstream.source, HTTP_FRAME_LIMIT * 2);
    const relay = relayFrames(input, await input.meta());
    const abort = new AbortController();
    let written!: () => void;
    const firstWrite = new Promise<void>((resolve) => {
      written = resolve;
    });
    const destination = new Writable({
      highWaterMark: 1,
      write(_chunk, _encoding, _callback) {
        written();
      },
    });
    const pumping = pipeline(
      Readable.fromWeb(relay, {
        highWaterMark: HTTP_FRAME_LIMIT,
      }),
      destination,
      { signal: abort.signal },
    );
    const failed = expect(pumping).rejects.toMatchObject({
      name: 'AbortError',
    });
    await firstWrite;
    abort.abort();
    await failed;
    expect(upstream.cancel).toHaveBeenCalledOnce();
  });

  it.each(['response pipeline', 'upload body'])(
    'cancels a pending upstream read through the %s',
    async (direction) => {
      let reading!: () => void;
      const pendingRead = new Promise<void>((resolve) => {
        reading = resolve;
      });
      const cancel = vi.fn();
      const source = new ReadableStream<Uint8Array>(
        {
          start(controller) {
            controller.enqueue(encodePreamble());
            controller.enqueue(encodeMetaFrame({ fixture: 'pending body' }));
          },
          pull() {
            reading();
          },
          cancel,
        },
        { highWaterMark: 0 },
      );
      const input = new HttpFrameReader(source, HTTP_FRAME_LIMIT);
      const finish = vi.fn(async (_error?: unknown) => {});
      const relay = relayFrames(input, await input.meta(), () => {}, finish);
      const abort = new AbortController();
      const node = Readable.fromWeb(relay, {
        highWaterMark: HTTP_FRAME_LIMIT,
        ...(direction === 'upload body' ? { signal: abort.signal } : {}),
      });
      const pumping =
        direction === 'response pipeline'
          ? pipeline(
              node,
              new Writable({
                write(_chunk, _encoding, callback) {
                  callback();
                },
              }),
              { signal: abort.signal },
            )
          : (async () => {
              for await (const _chunk of node) {
                // Miniflare consumes request bodies as a Node async iterable.
              }
            })();
      const failed = expect(pumping).rejects.toMatchObject({
        name: 'AbortError',
      });
      await pendingRead;
      abort.abort();
      await failed;
      expect(cancel).toHaveBeenCalledOnce();
      expect(source.locked).toBe(false);
      expect(finish).toHaveBeenCalledOnce();
      expect(finish.mock.calls[0]?.[0]).toBeInstanceOf(Error);
    },
  );
});
