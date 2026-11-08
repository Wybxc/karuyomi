import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  httpRequestMetaSchema,
  httpResponseMetaSchema,
  type HttpRequestMeta,
  type HttpResponseMeta,
  HttpFrameError,
} from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';
import {
  reportRuntimeDiagnostic,
  type HttpDiagnosticStage,
} from './runtime-diagnostics.js';

export interface HttpCallContext {
  requestId: string;
  generation: string;
}

/** An expired Java owner must never record a failure against a later entry. */
export class HttpOwnerFailure extends RuntimeFailure {
  constructor() {
    super('cancelled', 'HTTP operation owner expired or was cancelled');
  }
}

interface HttpSession {
  owner: HttpCallContext;
  operationToken: string;
  meta: HttpRequestMeta;
  chunks: Uint8Array<ArrayBuffer>[];
  size: number;
  controller: AbortController;
  timer: ReturnType<typeof setTimeout>;
  phase: 'upload' | 'opening' | 'response' | 'eof';
  reader?: HttpFrameReader;
  response?: HttpResponseMeta;
  reading: boolean;
  failure?: RuntimeFailure;
  diagnostics: { startedAt: number; readCount: number } | undefined;
}

const HTTP_HANDLE_LIMIT = 4;
const HTTP_TERMINAL_LIMIT = 16;
const HTTP_HARD_DEADLINE_MS = 300_000;

/** One operation owns its handles. No reads run ahead of the Java consumer. */
export class BinaryHttpTransport {
  private context: HttpCallContext | undefined;
  private token: string | undefined;
  private readonly sessions = new Map<string, HttpSession>();
  // Keep only small failure causes until the owning operation ends, never bodies.
  private readonly terminalFailures = new Map<string, RuntimeFailure>();
  private closed = false;

  constructor(
    private readonly origin: string,
    private readonly fetcher: typeof fetch = (...args) => fetch(...args),
  ) {}

  get operationToken(): string | undefined {
    return this.token;
  }

  begin(context: HttpCallContext): string {
    if (this.closed)
      throw new RuntimeFailure('runtime_lost', 'HTTP transport was closed');
    this.end();
    this.context = { ...context };
    this.token = crypto.randomUUID();
    return this.token;
  }

  end(): void {
    for (const handle of this.sessions.keys()) this.close(handle);
    this.terminalFailures.clear();
    this.context = undefined;
    this.token = undefined;
  }

  dispose(): void {
    this.end();
    this.closed = true;
  }

  open(json: string): string {
    if (this.closed || !this.context || !this.token)
      throw new HttpOwnerFailure();
    // Reject oversized control input before parsing. Body bytes never enter JSON.
    if (json.length > HTTP_FRAME_LIMIT)
      throw new RuntimeFailure('limit_exceeded', 'HTTP metadata is too large');
    let input: unknown;
    try {
      input = JSON.parse(json);
    } catch {
      throw new RuntimeFailure('protocol_error', 'Invalid HTTP metadata');
    }
    if (!input || typeof input !== 'object' || Array.isArray(input))
      throw new RuntimeFailure('protocol_error', 'Invalid HTTP metadata');
    if (
      !('operationRequestId' in input) ||
      input.operationRequestId !== this.context.requestId ||
      !('operationGeneration' in input) ||
      input.operationGeneration !== this.context.generation ||
      !('operationToken' in input) ||
      input.operationToken !== this.token
    )
      throw new HttpOwnerFailure();
    if (this.sessions.size >= HTTP_HANDLE_LIMIT)
      throw new RuntimeFailure('limit_exceeded', 'Too many open HTTP bodies');
    const {
      operationRequestId,
      operationGeneration,
      operationToken,
      ...metadata
    } = input;
    const parsed = httpRequestMetaSchema.safeParse({
      ...metadata,
      requestId: crypto.randomUUID(),
      runtimeGeneration: this.context.generation,
    });
    if (!parsed.success)
      throw new RuntimeFailure('protocol_error', 'Invalid HTTP metadata');
    // Encoding performs the UTF-8 byte limit check, before accepting upload data.
    encodeMetaFrame(parsed.data);
    const handle = crypto.randomUUID();
    const controller = new AbortController();
    // META timeoutMs is the Source's upstream read idle budget, enforced by
    // the API. Independently bound the local handle through upload and EOF.
    const timer = setTimeout(
      () => this.close(handle, cancelledFailure(true)),
      HTTP_HARD_DEADLINE_MS,
    );
    this.sessions.set(handle, {
      owner: this.context,
      operationToken: this.token,
      meta: parsed.data,
      chunks: [],
      size: 0,
      controller,
      timer,
      phase: 'upload',
      reading: false,
      diagnostics:
        import.meta.env.VITE_KARUYOMI_RUNTIME_DIAGNOSTICS === '1'
          ? { startedAt: performance.now(), readCount: 0 }
          : undefined,
    });
    return handle;
  }

  write(handle: string, bytes: Uint8Array): void {
    const session = this.get(handle);
    if (session.phase !== 'upload')
      throw new RuntimeFailure('protocol_error', 'HTTP upload already ended');
    if (
      !(bytes instanceof Uint8Array) ||
      bytes.byteLength === 0 ||
      bytes.byteLength > HTTP_FRAME_LIMIT ||
      !session.meta.hasBody
    )
      throw new RuntimeFailure('protocol_error', 'Invalid HTTP upload chunk');
    const size = session.size + bytes.byteLength;
    if (
      size > HTTP_REQUEST_BODY_LIMIT ||
      (session.meta.bodyLength !== null && size > session.meta.bodyLength)
    ) {
      this.close(handle);
      throw new RuntimeFailure('limit_exceeded', 'HTTP upload is too large');
    }
    session.chunks.push(new Uint8Array(bytes));
    session.size = size;
  }

  async finish(handle: string): Promise<string> {
    const session = this.get(handle);
    if (session.phase !== 'upload')
      throw new RuntimeFailure('protocol_error', 'HTTP upload already ended');
    if (
      session.meta.bodyLength !== null &&
      session.size !== session.meta.bodyLength
    ) {
      this.close(handle);
      throw new RuntimeFailure('protocol_error', 'HTTP upload length mismatch');
    }
    session.phase = 'opening';
    const parts: BlobPart[] = [encodePreamble(), encodeMetaFrame(session.meta)];
    for (const chunk of session.chunks) parts.push(encodeDataFrame(chunk));
    parts.push(encodeEndFrame(session.size));
    const body = new Blob(parts, { type: HTTP_BRIDGE_MEDIA_TYPE });
    session.chunks = [];
    this.diagnose(handle, session, 'finish-fetch');
    try {
      let response: Response;
      try {
        response = await responseUntilAbort(
          this.fetcher(new URL('/api/bridge/http', this.origin), {
            method: 'POST',
            headers: {
              'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
              Accept: HTTP_BRIDGE_MEDIA_TYPE,
              'X-App-Request': '1',
            },
            body,
            credentials: 'same-origin',
            redirect: 'manual',
            cache: 'no-store',
            signal: session.controller.signal,
          }),
          session.controller.signal,
        );
        this.diagnose(handle, session, 'response');
      } catch (error) {
        if (session.failure) throw session.failure;
        // The endpoint and fetch options are host-controlled. A native TypeError
        // before Response is a connection failure, never a partial-body retry.
        if (error instanceof TypeError && !session.controller.signal.aborted)
          throw new RuntimeFailure(
            'source_error',
            'Source bridge connection failed',
            true,
          );
        throw error;
      }
      if (session.failure) {
        void response.body?.cancel().catch(() => {});
        throw session.failure;
      }
      this.get(handle);
      try {
        if (
          response.status === 502 &&
          (await preResponseNetworkFailure(response, session.controller.signal))
        )
          throw new RuntimeFailure(
            'source_error',
            'Source bridge connection failed',
            true,
          );
        assertBridgeResponse(response);
      } catch (error) {
        void response.body?.cancel().catch(() => {});
        throw error;
      }
      if (
        response.headers
          .get('content-type')
          ?.split(';')[0]
          ?.trim()
          .toLowerCase() !== HTTP_BRIDGE_MEDIA_TYPE
      ) {
        void response.body?.cancel().catch(() => {});
        throw new RuntimeFailure(
          'protocol_error',
          'Invalid HTTP frame media type',
        );
      }
      if (!response.body)
        throw new RuntimeFailure('protocol_error', 'Missing HTTP frame body');
      session.reader = new HttpFrameReader(
        response.body,
        HTTP_RESPONSE_BODY_LIMIT,
      );
      const parsed = httpResponseMetaSchema.safeParse(
        await session.reader.meta(),
      );
      if (
        !parsed.success ||
        parsed.data.requestId !== session.meta.requestId ||
        parsed.data.runtimeGeneration !== session.meta.runtimeGeneration
      )
        throw new RuntimeFailure(
          'protocol_error',
          'HTTP response identity mismatch',
        );
      this.get(handle);
      session.response = parsed.data;
      session.phase = 'response';
      this.diagnose(handle, session, 'meta');
      return JSON.stringify({ ...parsed.data, handle });
    } catch (error) {
      const failure = session.failure ?? transportFailure(error);
      this.diagnose(handle, session, 'error');
      this.close(handle, failure);
      throw failure;
    }
  }

  async read(handle: string, maxBytes: number): Promise<Uint8Array | null> {
    const session = this.get(handle);
    if (
      !Number.isInteger(maxBytes) ||
      maxBytes < 1 ||
      maxBytes > HTTP_FRAME_LIMIT ||
      session.reading ||
      !session.reader ||
      !session.response ||
      !['response', 'eof'].includes(session.phase)
    )
      throw new RuntimeFailure('protocol_error', 'Invalid HTTP body read');
    if (session.phase === 'eof') return null;
    session.reading = true;
    const firstRead = session.diagnostics?.readCount === 0;
    if (session.diagnostics) session.diagnostics.readCount++;
    if (firstRead) this.diagnose(handle, session, 'first-read');
    try {
      const chunk = await session.reader.read(maxBytes);
      this.get(handle);
      if (
        (chunk !== null && !session.response.hasBody) ||
        (session.response.bodyLength !== null &&
          (session.reader.bytesRead > session.response.bodyLength ||
            (chunk === null &&
              session.reader.bytesRead !== session.response.bodyLength)))
      )
        throw new RuntimeFailure(
          'protocol_error',
          'HTTP response length mismatch',
        );
      if (chunk === null) {
        session.phase = 'eof';
        clearTimeout(session.timer);
        this.diagnose(handle, session, 'eof');
      } else if (firstRead) this.diagnose(handle, session, 'first-read-result');
      return chunk;
    } catch (error) {
      const failure = session.failure ?? transportFailure(error);
      this.diagnose(handle, session, 'error');
      this.close(handle, failure);
      throw failure;
    } finally {
      session.reading = false;
    }
  }

  /** Closing or cancelling a partially read body aborts the upstream fetch. */
  close(handle: string, reason = cancelledFailure(false)): void {
    const session = this.sessions.get(handle);
    if (!session) return;
    this.diagnose(handle, session, 'close');
    this.sessions.delete(handle);
    session.failure = reason;
    if (reason.code !== 'cancelled') {
      this.terminalFailures.set(handle, reason);
      while (this.terminalFailures.size > HTTP_TERMINAL_LIMIT) {
        const oldest = this.terminalFailures.keys().next().value;
        if (oldest !== undefined) this.terminalFailures.delete(oldest);
      }
    }
    clearTimeout(session.timer);
    session.chunks = [];
    session.controller.abort(reason);
    void session.reader?.cancel().catch(() => {});
  }

  private diagnose(
    handle: string,
    session: HttpSession,
    stage: HttpDiagnosticStage,
  ): void {
    if (!session.diagnostics) return;
    reportRuntimeDiagnostic({
      component: 'http',
      requestId: session.owner.requestId,
      generation: session.owner.generation,
      handle,
      stage,
      phase: session.phase,
      elapsedMs: Math.round(performance.now() - session.diagnostics.startedAt),
      readCount: session.diagnostics.readCount,
      bytesRead: session.reader?.bytesRead ?? 0,
    });
  }

  private get(handle: string): HttpSession {
    if (this.closed || !this.context || !this.token)
      throw new HttpOwnerFailure();
    const failure = this.terminalFailures.get(handle);
    if (failure) throw failure;
    const session = this.sessions.get(handle);
    if (
      !session ||
      session.operationToken !== this.token ||
      session.owner.requestId !== this.context.requestId ||
      session.owner.generation !== this.context.generation
    )
      throw new HttpOwnerFailure();
    return session;
  }
}

/** Settle the handle on abort even if fetch resolves late with an unused body. */
function responseUntilAbort(
  fetching: Promise<Response>,
  signal: AbortSignal,
): Promise<Response> {
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(signal.reason);
    if (signal.aborted) onAbort();
    else signal.addEventListener('abort', onAbort, { once: true });
    void fetching.then(
      (response) => {
        signal.removeEventListener('abort', onAbort);
        if (signal.aborted) void response.body?.cancel().catch(() => {});
        else resolve(response);
      },
      (error: unknown) => {
        signal.removeEventListener('abort', onAbort);
        reject(error);
      },
    );
  });
}

/** Only the API's small, fixed pre-header error can authorize a connection retry. */
async function preResponseNetworkFailure(
  response: Response,
  signal: AbortSignal,
): Promise<boolean> {
  if (
    response.headers
      .get('content-type')
      ?.split(';')[0]
      ?.trim()
      .toLowerCase() !== 'application/json' ||
    !response.body
  )
    return false;
  const reader = response.body.getReader();
  const abort = () => {
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener('abort', abort, { once: true });
  const bytes = new Uint8Array(4096);
  let size = 0;
  try {
    if (signal.aborted) return false;
    for (;;) {
      const chunk = await reader.read();
      if (signal.aborted) return false;
      if (chunk.done) break;
      if (size + chunk.value.byteLength > bytes.byteLength) return false;
      bytes.set(chunk.value, size);
      size += chunk.value.byteLength;
    }
    const error: unknown = JSON.parse(
      new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, size)),
    );
    return (
      !!error &&
      typeof error === 'object' &&
      !Array.isArray(error) &&
      Object.keys(error).length === 1 &&
      'error' in error &&
      error.error === 'upstream_network_error'
    );
  } catch {
    return false;
  } finally {
    signal.removeEventListener('abort', abort);
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function cancelledFailure(timeout: boolean): RuntimeFailure {
  const error = new RuntimeFailure(
    timeout ? 'timeout' : 'cancelled',
    timeout ? 'HTTP request timed out' : 'HTTP handle expired or was cancelled',
  );
  error.name = timeout ? 'TimeoutError' : 'AbortError';
  return error;
}

function transportFailure(error: unknown): RuntimeFailure {
  if (error instanceof RuntimeFailure) return error;
  if (error instanceof HttpFrameError) {
    const code =
      error.code === 'limit_exceeded' ||
      error.code === 'timeout' ||
      error.code === 'cancelled'
        ? error.code
        : 'protocol_error';
    return new RuntimeFailure(code, error.message);
  }
  return new RuntimeFailure('source_error', 'Source HTTP transport failed');
}

export function assertBridgeResponse(response: Response): void {
  if (
    response.type === 'opaqueredirect' ||
    response.status === 401 ||
    (response.status >= 300 && response.status < 400)
  )
    throw new RuntimeFailure(
      'access_required',
      'Access session expired during a Source request',
    );
  if (response.status === 403)
    throw new RuntimeFailure(
      'access_denied',
      'Access denied the Source bridge',
    );
  if (response.headers.get('content-type')?.includes('text/html'))
    throw new RuntimeFailure(
      'access_required',
      'Access returned a login page to the Source bridge',
    );
  if (response.status === 504) throw cancelledFailure(true);
  if (!response.ok)
    throw new RuntimeFailure(
      'source_error',
      `Source bridge returned HTTP ${response.status}`,
    );
}
