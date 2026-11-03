import { createServer, type ServerResponse } from 'node:http';
import { once } from 'node:events';

export interface CacheOriginEvent {
  path: string;
  mode: string;
  advertisedBytes: number;
  writtenBytes: number;
  closed: boolean;
  prefixAcknowledged: boolean;
}

/** Controlled HTTP, not a synthetic Java ResponseBody: both JVM and TeaVM consume its wire framing. */
export async function createCacheHttpOrigin() {
  const payload = Buffer.alloc(131079);
  for (let index = 0; index < payload.length; index++)
    payload[index] = index & 255;
  const events: CacheOriginEvent[] = [];
  const failures: { response: ServerResponse; event: CacheOriginEvent }[] = [];
  const pending = new Map<
    string,
    { response: ServerResponse; event: CacheOriginEvent }
  >();
  const server = createServer((request, response) => {
    const url = new URL(request.url ?? '/', 'http://fixture.example.org');
    if (url.pathname.startsWith('/fixture-control/truncate/')) {
      const name = url.pathname.slice('/fixture-control/truncate/'.length);
      const active = pending.get(name);
      if (!active || active.event.mode !== 'truncate') {
        response.writeHead(409).end();
        return;
      }
      active.event.prefixAcknowledged = true;
      active.response.destroy();
      response.writeHead(204, { 'Cache-Control': 'no-store' }).end();
      return;
    }
    const name = url.pathname.slice('/failure/'.length);
    const mode = request.headers['x-fixture-mode'];
    if (
      !url.pathname.startsWith('/failure/') ||
      !/^(truncate|cancel)-(empty|replacement)$/.test(name) ||
      (mode !== 'complete' && mode !== 'truncate' && mode !== 'cancel')
    ) {
      response.writeHead(404).end();
      return;
    }
    const event: CacheOriginEvent = {
      path: url.pathname,
      mode,
      advertisedBytes: payload.length,
      writtenBytes: mode === 'complete' ? payload.length : 8192,
      closed: false,
      prefixAcknowledged: false,
    };
    events.push(event);
    if (mode !== 'complete') failures.push({ response, event });
    response.writeHead(200, {
      'Cache-Control': 'max-age=600',
      'Content-Type': 'application/octet-stream',
      'Content-Length': payload.length,
    });
    response.once('close', () => {
      event.closed = true;
      if (pending.get(name)?.response === response) pending.delete(name);
    });
    if (mode === 'complete') response.end(payload);
    else {
      pending.set(name, { response, event });
      response.write(payload.subarray(0, 8192));
    }
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string')
    throw Error('Missing Cache origin address');
  return {
    port: address.port,
    origin: `http://127.0.0.1:${address.port}`,
    events,
    waitForFailureCloses: async (
      timeoutMs: number,
      interrupt?: AbortSignal,
    ) => {
      const signal = AbortSignal.any([
        AbortSignal.timeout(timeoutMs),
        ...(interrupt ? [interrupt] : []),
      ]);
      await Promise.all(
        failures.map(({ response, event }) =>
          event.closed
            ? Promise.resolve()
            : once(response, 'close', { signal }),
        ),
      );
    },
    close: async () => {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
