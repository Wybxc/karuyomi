# HTTP bridge v2

The v2 transport carries HTTP metadata as bounded JSON and bodies as raw bytes.
Its media type is `application/vnd.karuyomi.http.v2`. It does not use Base64.
The current extension manifest requires `bridgeVersion: 2`. The prototype
maintains only this transport; older builds must be rebuilt with the current
host inputs.

## Wire format

Every message starts with exactly eight bytes: ASCII `KRYHTTP` followed by the
version byte `0x02`. Every subsequent frame starts with a five-byte header:
`type: u8`, then `payloadLength: u32` in big-endian order. Lengths exclude this
header. Transport chunk boundaries have no protocol meaning.

| Type  | Value | Payload                                                  | Maximum payload                      |
| ----- | ----- | -------------------------------------------------------- | ------------------------------------ |
| META  | 1     | UTF-8 JSON                                               | 65,536 bytes                         |
| DATA  | 2     | Nonempty raw bytes                                       | 65,536 bytes                         |
| END   | 3     | Total DATA bytes as a big-endian unsigned 64-bit integer | Exactly 8 bytes                      |
| ERROR | 4     | UTF-8 JSON `{code, message}`                             | 4,096 bytes, including JSON overhead |

The only successful sequence is `preamble → META → DATA* → END → EOF`.
An empty body still requires `END(0)`. The END count must equal the sum of all
DATA payload lengths. An ERROR may terminate a message after META, including
after some DATA, and must also be followed by EOF. ERROR does not indicate a
successful, complete body. Receivers reject a missing terminal frame, duplicate
META, unknown magic/version/type, invalid lengths, malformed UTF-8 or JSON, and
any bytes after END or ERROR. A UTF-8 BOM is rejected as invalid JSON.

## Metadata

The exported `httpRequestMetaSchema` validates these required fields:

```ts
{
  requestId: string;
  runtimeGeneration: string;
  url: string;
  method: 'GET' | 'HEAD' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'OPTIONS';
  headers: [string, string][];
  hasBody: boolean;
  bodyLength: number | null;
  timeoutMs: number;
}
```

The exported `httpResponseMetaSchema` validates these required fields:

```ts
{
  requestId: string;
  runtimeGeneration: string;
  upstreamStatus: number;
  message: string;
  url: string;
  headers: [string, string][];
  hasBody: boolean;
  bodyLength: number | null;
  decoded: boolean;
}
```

Both schemas reject unknown fields. URLs must be absolute HTTP(S) URLs; this
format check does not authorize an upstream host. Authentication, origin/host
binding, SSRF checks, header policy and redirect policy belong to the bridge.
The request timeout is a positive integer no greater than 300,000 milliseconds.
The response message may be empty. A missing Fetch response URL must be replaced
with the request URL before emitting metadata.

If the Source URL fails the registered build's network policy, the Worker returns
`422 {"error":"target_not_allowed"}` before making an upstream request. This is a
Source failure, so the client keeps the account session and the Source settings
entry. Outer 401 and 403 still indicate Access failures. A response from an
allowed upstream, including its 4xx status, is carried in the framed META.

Headers are ordered tuples. Preserve their order and repeated fields, especially
`Set-Cookie`; do not convert them into a map or combine them with commas.
`hasBody: false` requires `bodyLength: 0`. With `hasBody: true`, zero denotes an
empty entity and null denotes an unknown length. A known length must match the
DATA count when the consumer finishes. Request bodies are limited to 8 MiB and
response bodies to 64 MiB, independent of wire framing overhead.

`decoded` describes the response DATA bytes. If Fetch supplies a decoded body,
the bridge must not label it with the upstream compressed Content-Encoding or
Content-Length. Bodyless HEAD/204/304 responses emit no DATA and retain the
representation metadata appropriate to that response. Range responses retain
their Content-Range. These HTTP semantics are enforced by the bridge rather
than inferred by the generic frame reader.

## Encoding and consuming

The package exports `encodePreamble()`, `encodeMetaFrame(meta)`,
`encodeDataFrame(bytes)`, `encodeEndFrame(total)` and
`encodeErrorFrame({code, message})`. Each returns an owned
`Uint8Array<ArrayBuffer>`. Only `encodePreamble()` writes the preamble; the other
helpers encode one frame each. END accepts a nonnegative safe integer or a
bigint in the unsigned 64-bit range. Write each frame through a backpressured
sink rather than collecting an entire message before sending it.

```ts
const reader = new HttpFrameReader(response.body, HTTP_RESPONSE_BODY_LIMIT);
try {
  const meta = httpResponseMetaSchema.parse(await reader.meta());
  for (;;) {
    const bytes = await reader.read(HTTP_FRAME_LIMIT);
    if (bytes === null) break;
    await sink.write(bytes);
  }
  if (meta.bodyLength !== null && reader.bytesRead !== meta.bodyLength) {
    throw new Error('Response length mismatch');
  }
} finally {
  await reader.cancel();
}
```

`HttpFrameReader(stream, limit)` takes a DATA byte budget between zero and 64 MiB.
`meta(): Promise<unknown>` caches one META value; consumers explicitly apply the
request or response schema. `read(maxBytes)` accepts 1–65,536 and returns a
nonempty byte array or null. Reads are sequential. Calling `read` first also
loads META. Null is returned only after validating END and EOF, so a peer that
does not close the stream remains subject to the caller's deadline. `bytesRead`
counts only DATA bytes already returned to the consumer.

The reader validates a frame header before allocating its payload. It retains
at most one 64 KiB DATA payload and the remaining view of one input chunk, and
never reads a second DATA frame before the consumer requests it. A transport may
deliver a chunk larger than 64 KiB; the reader keeps a view rather than copying
or accumulating that entire chunk. Returned buffers can be transferred without
detaching a frame remainder. This is a parser bound, not a claim about the
network stack's chunk size or memory use.

The stream/port adapter must independently cap every enqueue at 64 KiB and its
pending queue at four chunks. Frame headers add five wire bytes, so an adapter
must also split a full-size encoded DATA frame when its wire enqueue limit is
64 KiB. The reader does not create a background pump or enforce the adapter's
queue. Cancellation, timeout and runtime-generation changes must also abort
the corresponding fetch and pending writes at that layer.

`cancel(reason): Promise<void>` is idempotent, forwards the first reason to the
source and discards retained bytes. It waits for the source's cancellation
cleanup. Parsing failures initiate cancellation and reject immediately even if
that cleanup stalls. `HttpFrameError` exposes `code` and `remote`: malformed
input uses `protocol_error`, budget violations use `limit_exceeded`, explicit
cancellation uses `cancelled`, and a valid terminal ERROR exposes its code and
message with `remote: true`. Other source exception messages are not reflected.

## Runtime and local adapter configuration

Host ABI v4 binds each Java entry to `requestId`, `generation` and a fresh opaque
operation token. Java HTTP metadata carries these three private owner fields;
the local transport validates and removes them before creating wire META. Old
owners cannot open a request or record a failure against a newer entry, even
when init/load share the same public request identity. Coroutine dispatch
explicitly propagates the owner.

`BrowserCall.enqueue` registers before scheduling its thread. After the main
Source result, the host waits up to 30 seconds for at most 64 concurrent callback
tasks, including nested enqueue calls and response cleanup. Handled `onFailure`
does not fail the parent operation. If drain expires or an abnormal return leaves
callbacks running, the host reports `runtime_lost` and the manager terminates the
Worker. Cancellation never replays a Source operation or its POST requests.

The Worker explicitly enables `enable_request_signal` with compatibility date
`2026-11-03`. Cloudflare only enables client-disconnection events by default at
[`2026-11-17`](https://developers.cloudflare.com/changelog/post/2026-11-02-request-signal-default/).
The bridge still passes its abort signal explicitly to upstream fetches. This
configuration is necessary for cancellation, but is not itself evidence that a
particular browser or Native request closes its upstream connection.

Current Workers tests use the Cloudflare official Vitest integration and real
D1 migrations. Their outbound requests use the official MSW integration. No
custom socket adapter is part of the current regression entry point. The frame
reader requires only the default reader's `read`, `cancel` and `releaseLock`
methods; it does not require platform-specific BYOB or pipe transforms.

## Regression checks

```sh
pnpm test
pnpm --filter @karuyomi/contracts typecheck
```

The root test command first builds runtime and test fixtures with Vite CLI, then
runs Node and official Workers Vitest projects. Frame tests cover byte-level
splitting, oversized transport chunks, partial-buffer transfer, UTF-8 budgets,
length validation, terminal forms, exact u64 counts, trailing data, malformed
input and pending-read cancellation. [Workers HTTP tests](../apps/api/test/http-worker.test.ts)
exercise the real route, RS256 verifier and D1 policy with controlled outbound
responses: status/body rules, cookies, Range, uploads, form data, truncation,
deadlines and consumer cancellation. Gzip uses actual compressed bytes; the
Brotli case checks an already decoded response boundary and does not establish
real network decompression.

MSW cancellation checks observe the simulated upstream signal. They do not
prove a remote origin's TCP connection closed, nor actual HTTP/2 or HTTP/3
cancellation. Source behavior, production Access and Native requests remain
separate acceptance gates; coverage is tracked in the [Vite plan](plan/vite-build-and-testing.md).

## Historical socket evidence

The custom HTTP/socket probes and their commands were retired on 2026-11-05.
Their original code remains available at the
[historical commit](https://github.com/Wybxc/karuyomi/tree/f623a8263c87ac198ff3882fd3eade1072e6abfc/apps/api/test).
Earlier loopback HTTP/1 runs used a user Worker socket, a controlled origin and
explicit TCP reset while the origin was idle. Those fixed-input results remain
in [Source cancellation](verification/source-cancellation-web.md) and
[Java Cache failures](verification/cache-http-failures.md), including the
untouched JVM/TeaVM comparison. They do not become current regression coverage
merely because the route now has official fixture tests. Ordinary local stream
destruction was not evidence of remote cancellation in those runs. Current
Source, production Access, Native and real connection-close behavior require
their own fresh evidence.
