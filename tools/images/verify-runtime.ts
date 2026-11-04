/** Real-WASM acceptance checks. Reference generation is outside codec memory accounting. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import sharp from 'sharp';
import writeFileAtomic from 'write-file-atomic';
import { loadImageCodec } from '../../runtime/image-codec/codec-api.ts';
import { decodeImage } from '../../runtime/image-codec/decoder.ts';
import {
  imageCodecBuildIdentity,
  imageCodecBuildManifestSchema,
} from './build.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const MAX_INPUT_BYTES = 8 * 1024 * 1024;
const MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;
const MAX_HEAP_BYTES = 32 * 1024 * 1024;
const MAX_CHUNK_BYTES = 64 * 1024;
type Format = 'png' | 'jpeg';
type Terminal = Awaited<ReturnType<typeof decodeImage>['completion']>;
interface Region {
  name: string;
  offset: number;
  length: number;
  sha256: string;
}
interface Reference {
  width: number;
  height: number;
  byteLength: number;
  sha256: string;
  regions: Region[];
}
interface Fixture {
  format: Format;
  bytes: Uint8Array<ArrayBuffer>;
  reference: Reference;
}
interface Fixtures {
  png: Fixture;
  jpeg: Fixture;
  pngTall: Fixture;
  jpegTall: Fixture;
  rgbPng: Uint8Array<ArrayBuffer>;
  interlacedPng: Uint8Array<ArrayBuffer>;
  progressiveJpeg: Uint8Array<ArrayBuffer>;
}
interface CaseResult {
  name: string;
  status: 'passed' | 'failed';
  evidence?: unknown;
  error?: string;
}
export interface ImageCodecVerificationOptions {
  buildDirectory: string;
  reportFile?: string;
  signal?: AbortSignal;
}

const sha256 = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');
const owned = (bytes: Uint8Array): Uint8Array<ArrayBuffer> =>
  new Uint8Array(bytes);

function pattern(width: number, height: number, alpha: boolean): Buffer {
  const result = Buffer.allocUnsafe(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const offset = (y * width + x) * 4;
      result[offset] = ((x >> 4) * 17 + (y >> 7) * 11) % 256;
      result[offset + 1] = ((x >> 5) * 31 + (y >> 6) * 13) % 256;
      result[offset + 2] = ((x >> 3) * 7 + (y >> 8) * 19) % 256;
      result[offset + 3] = alpha ? 64 + (((x >> 5) + (y >> 6)) % 192) : 255;
    }
  }
  return result;
}

function reference(
  bytes: Uint8Array,
  width: number,
  height: number,
): Reference {
  assert.equal(bytes.length, width * height * 4);
  const rows = Math.min(256, height);
  const regions = [
    { name: 'first', row: 0 },
    { name: 'middle', row: Math.floor((height - rows) / 2) },
    { name: 'last', row: height - rows },
  ].map(({ name, row }) => {
    const offset = row * width * 4;
    const length = rows * width * 4;
    return {
      name,
      offset,
      length,
      sha256: sha256(bytes.subarray(offset, offset + length)),
    };
  });
  return {
    width,
    height,
    byteLength: bytes.length,
    sha256: sha256(bytes),
    regions,
  };
}

async function pngFixture(
  height: number,
  signal?: AbortSignal,
): Promise<Fixture> {
  signal?.throwIfAborted();
  const width = 1080;
  const raw = pattern(width, height, true);
  const expected = reference(raw, width, height);
  const bytes = await sharp(raw, { raw: { width, height, channels: 4 } })
    .png({ palette: false, progressive: false, compressionLevel: 6 })
    .toBuffer();
  signal?.throwIfAborted();
  assert(
    bytes.length <= MAX_INPUT_BYTES,
    'PNG fixture exceeds the encoded input budget',
  );
  return { format: 'png', bytes: owned(bytes), reference: expected };
}

async function jpegFixture(
  height: number,
  signal?: AbortSignal,
): Promise<Fixture> {
  signal?.throwIfAborted();
  const width = 720;
  const raw = pattern(width, height, false);
  const bytes = await sharp(raw, { raw: { width, height, channels: 4 } })
    .removeAlpha()
    .jpeg({ quality: 90, chromaSubsampling: '4:4:4', progressive: false })
    .toBuffer();
  const decoded = await sharp(bytes)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  signal?.throwIfAborted();
  assert.equal(decoded.info.channels, 4);
  assert.equal(decoded.info.width, width);
  assert.equal(decoded.info.height, height);
  assert(
    bytes.length <= MAX_INPUT_BYTES,
    'JPEG fixture exceeds the encoded input budget',
  );
  return {
    format: 'jpeg',
    bytes: owned(bytes),
    reference: reference(decoded.data, width, height),
  };
}

async function fixtures(signal?: AbortSignal): Promise<Fixtures> {
  // Keep generation sequential: these full reference allocations are neither
  // the decoder's metered payload nor measurements of its WASM/JS/process peak.
  const png = await pngFixture(20000, signal);
  const jpeg = await jpegFixture(30000, signal);
  const pngTall = await pngFixture(40000, signal);
  const jpegTall = await jpegFixture(60000, signal);
  const raw = pattern(32, 32, true);
  const source = () =>
    sharp(raw, { raw: { width: 32, height: 32, channels: 4 } });
  const rgbPng = await source()
    .removeAlpha()
    .png({ palette: false, progressive: false })
    .toBuffer();
  const interlacedPng = await source()
    .png({ palette: false, progressive: true })
    .toBuffer();
  const progressiveJpeg = await source()
    .removeAlpha()
    .jpeg({ progressive: true })
    .toBuffer();
  signal?.throwIfAborted();
  return {
    png,
    jpeg,
    pngTall,
    jpegTall,
    rgbPng: owned(rgbPng),
    interlacedPng: owned(interlacedPng),
    progressiveJpeg: owned(progressiveJpeg),
  };
}

function assertReleased(terminal: Terminal): void {
  assert.equal(terminal.closeSucceeded, true, 'codec close must succeed');
  assert.equal(terminal.liveBytes, 0, 'close must release metered payload');
  assert.equal(
    terminal.allocations,
    0,
    'close must release every metered allocation',
  );
  assert(
    terminal.peakBytes !== null &&
      terminal.peakBytes > 0 &&
      terminal.peakBytes <= MAX_PAYLOAD_BYTES,
  );
  assert(terminal.heapBytes !== null && terminal.heapBytes <= MAX_HEAP_BYTES);
}

async function collect(
  fixture: Fixture,
  codecUrl: URL,
  options: { denominator?: 1 | 2 | 4; signal?: AbortSignal } = {},
) {
  const session = decodeImage({
    bytes: fixture.bytes,
    codecUrl,
    format: fixture.format,
    ...options,
  });
  const digest = createHash('sha256');
  const regionDigests = (
    options.denominator && options.denominator !== 1
      ? []
      : fixture.reference.regions
  ).map((region) => ({ ...region, digest: createHash('sha256'), received: 0 }));
  let byteLength = 0;
  let sequence = 0;
  let headers = 0;
  let terminals = 0;
  let width = 0;
  let height = 0;
  for await (const event of session) {
    if (event.kind === 'header') {
      headers++;
      assert.equal(event.sourceWidth, fixture.reference.width);
      assert.equal(event.sourceHeight, fixture.reference.height);
      assert.equal(event.rowBytes, event.width * 4);
      width = event.width;
      height = event.height;
    } else if (event.kind === 'chunk') {
      assert.equal(headers, 1);
      assert.equal(event.sequence, ++sequence);
      assert.equal(event.offset, byteLength);
      assert(
        event.bytes.byteLength > 0 && event.bytes.byteLength <= MAX_CHUNK_BYTES,
      );
      assert(event.stripRows > 0 && event.stripRows <= 256);
      assert(event.stripStart >= 0 && event.stripStart < height);
      assert.equal(event.bytes.buffer instanceof SharedArrayBuffer, false);
      digest.update(event.bytes);
      for (const region of regionDigests) {
        const start = Math.max(event.offset, region.offset);
        const end = Math.min(
          event.offset + event.bytes.length,
          region.offset + region.length,
        );
        if (end > start) {
          region.digest.update(
            event.bytes.subarray(start - event.offset, end - event.offset),
          );
          region.received += end - start;
        }
      }
      byteLength += event.bytes.byteLength;
    } else {
      terminals++;
    }
  }
  const terminal = await session.completion;
  assert.equal(headers, 1);
  assert.equal(terminals, 1);
  assert.equal(terminal.status, 'complete');
  assert.equal(terminal.deliveredBytes, byteLength);
  assert.equal(terminal.decodedRows, height);
  assert.equal(byteLength, width * height * 4);
  assertReleased(terminal);
  return {
    width,
    height,
    byteLength,
    chunks: sequence,
    sha256: digest.digest('hex'),
    terminal,
    regions: regionDigests.map(
      ({ name, length, received, digest: regionDigest }) => ({
        name,
        length,
        received,
        sha256: regionDigest.digest('hex'),
      }),
    ),
  };
}

async function complete(fixture: Fixture, codecUrl: URL, signal?: AbortSignal) {
  const actual = await collect(fixture, codecUrl, signal ? { signal } : {});
  assert.equal(actual.width, fixture.reference.width);
  assert.equal(actual.height, fixture.reference.height);
  assert.equal(actual.byteLength, fixture.reference.byteLength);
  assert.equal(actual.sha256, fixture.reference.sha256);
  for (const region of actual.regions) {
    const expected = fixture.reference.regions.find(
      (item) => item.name === region.name,
    );
    assert(expected);
    assert.equal(region.received, expected.length);
    assert.equal(region.sha256, expected.sha256);
  }
  return actual;
}

async function interrupted(
  fixture: Fixture,
  codecUrl: URL,
  mode: 'signal' | 'consumer-break',
  signal?: AbortSignal,
) {
  const controller = new AbortController();
  const decodeSignal = signal
    ? AbortSignal.any([signal, controller.signal])
    : controller.signal;
  const session = decodeImage({
    bytes: fixture.bytes,
    codecUrl,
    format: fixture.format,
    signal: decodeSignal,
  });
  let chunks = 0;
  for await (const event of session) {
    if (event.kind !== 'chunk') continue;
    chunks++;
    if (mode === 'consumer-break') break;
    controller.abort(new Error('Acceptance check: cancel after first chunk'));
  }
  const terminal = await session.completion;
  assert.equal(chunks, 1);
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.deliveredBytes, MAX_CHUNK_BYTES);
  assert.equal(terminal.decodedRows, 256);
  assertReleased(terminal);
  return terminal;
}

async function pullBackpressure(
  fixture: Fixture,
  codecUrl: URL,
  signal?: AbortSignal,
) {
  const codec = await loadImageCodec(codecUrl);
  const acquire = codec.acquire.bind(codec);
  let nextCalls = 0;
  // Only observe the public lease. Every counted operation still calls the
  // actual WASM export; no output or decoder behavior is simulated here.
  codec.acquire = () => {
    const lease = acquire();
    const next = lease.api.image_next;
    return {
      ...lease,
      api: {
        ...lease.api,
        image_next: () => {
          nextCalls++;
          return next();
        },
      },
    };
  };
  const session = decodeImage(
    {
      bytes: fixture.bytes,
      codecUrl,
      format: fixture.format,
      ...(signal ? { signal } : {}),
    },
    { loadCodec: async () => codec },
  );
  const iterator = session[Symbol.asyncIterator]();
  try {
    const callsBeforeHeader = nextCalls;
    assert.equal(callsBeforeHeader, 0);
    assert.equal((await iterator.next()).value?.kind, 'header');
    const callsAfterHeader = nextCalls;
    assert.equal(callsAfterHeader, 0);
    assert.equal((await iterator.next()).value?.kind, 'chunk');
    const callsAfterFirstChunk = nextCalls;
    assert.equal(callsAfterFirstChunk, 1);
    const requestedPauseMs = 80;
    const pauseStarted = performance.now();
    await delay(requestedPauseMs, undefined, signal ? { signal } : {});
    const elapsedPauseMs = performance.now() - pauseStarted;
    const callsAfterPause = nextCalls;
    assert.equal(
      callsAfterPause,
      1,
      'paused consumer must not advance the WASM decoder',
    );
    assert.equal((await iterator.next()).value?.kind, 'chunk');
    const callsAfterResume = nextCalls;
    assert.equal(
      callsAfterResume,
      1,
      'resuming the same strip must not decode another strip',
    );
    await session.cancel();
    const terminal = await session.completion;
    assert.equal(terminal.status, 'cancelled');
    assert.equal(terminal.deliveredBytes, MAX_CHUNK_BYTES * 2);
    assert.equal(terminal.decodedRows, 256);
    assert.equal(nextCalls, 1);
    assertReleased(terminal);
    return {
      validation:
        'Same-thread pull backpressure only; this does not exercise a Worker ACK protocol.',
      requestedPauseMs,
      elapsedPauseMs,
      callsBeforeHeader,
      callsAfterHeader,
      callsAfterFirstChunk,
      callsAfterPause,
      callsAfterResume,
      terminal,
    };
  } finally {
    await session.cancel();
  }
}

async function rejected(
  bytes: Uint8Array<ArrayBuffer>,
  format: Format,
  codecUrl: URL,
  phase: 'open' | 'tail',
  signal?: AbortSignal,
) {
  const session = decodeImage({
    bytes,
    format,
    codecUrl,
    ...(signal ? { signal } : {}),
  });
  for await (const _event of session) {
    /* Drain the actual decoder, including its tail operation. */
  }
  const terminal = await session.completion;
  assert.equal(terminal.status, 'failed');
  assert(terminal.decodeErrorCode !== null && terminal.decodeErrorCode !== 0);
  if (phase === 'open') {
    assert.equal(terminal.decodeErrorPhase, 1);
    assert.equal(terminal.deliveredBytes, 0);
  } else {
    assert(
      terminal.decodeErrorPhase !== null && terminal.decodeErrorPhase >= 2,
    );
    assert(terminal.deliveredBytes > 0);
    if (format === 'png') {
      assert.equal(terminal.decodeErrorPhase, 3);
      assert(terminal.header);
      assert.equal(
        terminal.decodedRows,
        terminal.header.height,
        'IEND failure must follow decoding all rows',
      );
    }
  }
  assertReleased(terminal);
  return terminal;
}

async function abi(codecUrl: URL) {
  const codec = await loadImageCodec(codecUrl);
  const lease = codec.acquire();
  const api = lease.api;
  try {
    assert.notEqual(api.image_input(32), 0);
    assert(
      api.image_open(31, 256, 1) < 0,
      'open must reject an allocation-length mismatch',
    );
    const mismatch = {
      code: api.image_error_code(),
      phase: api.image_error_phase(),
    };
    assert.notEqual(mismatch.code, 0);
    assert.equal(mismatch.phase, 1);
    api.image_close();
    assert.equal(api.image_live_bytes(), 0);
    assert.equal(api.image_allocations(), 0);
    assert.equal(api.image_input(MAX_INPUT_BYTES + 1), 0);
    assert.equal(api.image_live_bytes(), 0);
    assert.notEqual(api.image_input(1024 * 1024), 0);
    const largePeak = api.image_peak_bytes();
    assert.equal(largePeak, 1024 * 1024);
    api.image_close();
    assert.equal(api.image_live_bytes(), 0);
    assert.equal(api.image_allocations(), 0);
    assert.equal(
      api.image_peak_bytes(),
      largePeak,
      'close must preserve the completed request peak',
    );
    assert.notEqual(api.image_input(32), 0);
    const nextPeak = api.image_peak_bytes();
    assert.equal(
      nextPeak,
      32,
      'next input must reset the previous request peak',
    );
    api.image_close();
    assert.equal(api.image_live_bytes(), 0);
    assert.equal(api.image_allocations(), 0);
    assert.equal(api.image_peak_bytes(), nextPeak);
    return {
      mismatch,
      largePeak,
      nextPeak,
      liveBytes: api.image_live_bytes(),
      allocations: api.image_allocations(),
    };
  } finally {
    lease.close();
  }
}

export async function verifyImageCodecs(
  options: ImageCodecVerificationOptions,
) {
  const directory = path.resolve(options.buildDirectory);
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(directory, 'build-manifest.json'), 'utf8'),
    ),
  );
  assert.equal(
    manifest.identity,
    imageCodecBuildIdentity(manifest.inputs),
    'Build manifest identity does not match its inputs',
  );
  const reportFile = path.resolve(
    options.reportFile ??
      path.join(
        ROOT,
        'runtime/image-codec/.local/verification',
        manifest.identity,
        'result.json',
      ),
  );
  if (!reportFile.split(path.sep).includes('.local'))
    throw new Error(
      'Verification reports must be written inside an ignored .local directory',
    );
  const artifacts: Record<string, { size: number; sha256: string }> = {};
  for (const name of ['png.mjs', 'png.wasm', 'jpeg.mjs', 'jpeg.wasm']) {
    const bytes = await readFile(path.join(directory, name));
    const actual = { size: bytes.length, sha256: sha256(bytes) };
    assert.deepEqual(
      actual,
      manifest.artifacts[name],
      `${name} differs from its build manifest`,
    );
    artifacts[name] = actual;
  }
  const pngUrl = pathToFileURL(path.join(directory, 'png.mjs'));
  const jpegUrl = pathToFileURL(path.join(directory, 'jpeg.mjs'));
  const input = await fixtures(options.signal);
  const cases: CaseResult[] = [];
  const completeImages: {
    format: Format;
    width: number;
    height: number;
    decodedByteLength: number;
    payloadPeakBytes: number | null;
    heapBytes: number | null;
  }[] = [];
  const verifyComplete = async (fixture: Fixture, codecUrl: URL) => {
    const actual = await complete(fixture, codecUrl, options.signal);
    completeImages.push({
      format: fixture.format,
      width: actual.width,
      height: actual.height,
      decodedByteLength: actual.byteLength,
      payloadPeakBytes: actual.terminal.peakBytes,
      heapBytes: actual.terminal.heapBytes,
    });
    return actual;
  };
  const run = async (name: string, action: () => Promise<unknown>) => {
    options.signal?.throwIfAborted();
    try {
      cases.push({ name, status: 'passed', evidence: await action() });
    } catch (error) {
      cases.push({
        name,
        status: 'failed',
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };
  for (const fixture of [input.png, input.jpeg]) {
    const url = fixture.format === 'png' ? pngUrl : jpegUrl;
    await run(`${fixture.format}:complete-pixels`, () =>
      verifyComplete(fixture, url),
    );
    await run(`${fixture.format}:pull-backpressure-pause`, () =>
      pullBackpressure(fixture, url, options.signal),
    );
    await run(`${fixture.format}:cancel-after-first-chunk`, () =>
      interrupted(fixture, url, 'signal', options.signal),
    );
    await run(`${fixture.format}:consumer-break`, () =>
      interrupted(fixture, url, 'consumer-break', options.signal),
    );
    await run(`${fixture.format}:abi-lifecycle`, () => abi(url));
  }
  for (const fixture of [input.pngTall, input.jpegTall]) {
    const url = fixture.format === 'png' ? pngUrl : jpegUrl;
    await run(
      `${fixture.format}:complete-pixels-${fixture.reference.width}x${fixture.reference.height}`,
      () => verifyComplete(fixture, url),
    );
  }
  assert.equal(
    Buffer.from(input.png.bytes.subarray(-8, -4)).toString('ascii'),
    'IEND',
  );
  assert.equal(input.jpeg.bytes.at(-2), 0xff);
  assert.equal(input.jpeg.bytes.at(-1), 0xd9);
  await run('png:missing-iend', () =>
    rejected(
      input.png.bytes.subarray(0, -12),
      'png',
      pngUrl,
      'tail',
      options.signal,
    ),
  );
  await run('jpeg:missing-eoi', () =>
    rejected(
      input.jpeg.bytes.subarray(0, -2),
      'jpeg',
      jpegUrl,
      'tail',
      options.signal,
    ),
  );
  await run('png:non-rgba-rejected', () =>
    rejected(input.rgbPng, 'png', pngUrl, 'open', options.signal),
  );
  await run('png:interlaced-rejected', () =>
    rejected(input.interlacedPng, 'png', pngUrl, 'open', options.signal),
  );
  await run('jpeg:progressive-rejected', () =>
    rejected(input.progressiveJpeg, 'jpeg', jpegUrl, 'open', options.signal),
  );
  for (const denominator of [2, 4] as const) {
    await run(`jpeg:scale-1-${denominator}-dimensions`, async () => {
      const actual = await collect(input.jpeg, jpegUrl, {
        denominator,
        ...(options.signal ? { signal: options.signal } : {}),
      });
      assert.equal(
        actual.width,
        Math.ceil(input.jpeg.reference.width / denominator),
      );
      assert.equal(
        actual.height,
        Math.ceil(input.jpeg.reference.height / denominator),
      );
      return {
        ...actual,
        validation:
          'Dimensions, output bytes and lifecycle only; no scaled pixel oracle was run.',
      };
    });
  }
  const passed = cases.every((result) => result.status === 'passed');
  const report = {
    schemaVersion: 1,
    passed,
    buildIdentity: manifest.identity,
    buildDirectory: directory,
    artifacts,
    versions: { node: process.version, sharp: sharp.versions },
    scope: {
      environment:
        'Node real WASM; no browser, Flutter, Source or Native product claim',
      fixtures:
        'Four synthetic images above 16 Mi pixels: RGBA8 noninterlaced PNG 1080x20000 and 1080x40000; single-scan baseline JPEG 720x30000 and 720x60000',
      memory:
        'Reference fixture generation and Sharp full-image decoding allocate complete buffers outside codec accounting. No process RSS or JS/graphics peak is measured. WASM heap and metered payload are separate limits; allocator headers, realloc transients and runtime overhead are excluded from payload.',
      cancellation:
        'Cooperative after the first yielded 64 KiB chunk; up to 256 rows are already decoded. Not preemption inside synchronous C.',
      backpressure:
        'An 80 ms pause observes real image_next calls through the public lease. This proves same-thread pull behavior, not Worker ACK delivery.',
      scaling:
        'Fresh 1/2 and 1/4 JPEG checks verify dimensions and byte count only. Historical native djpeg oracle evidence is separate; Sharp.resize is not used as an IDCT oracle.',
    },
    completeImages,
    fixtures: [input.png, input.jpeg, input.pngTall, input.jpegTall].map(
      (fixture) => ({
        format: fixture.format,
        encodedBytes: fixture.bytes.length,
        encodedSha256: sha256(fixture.bytes),
        reference: fixture.reference,
      }),
    ),
    cases,
  };
  await mkdir(path.dirname(reportFile), { recursive: true });
  await writeFileAtomic(reportFile, JSON.stringify(report, null, 2) + '\n');
  return { passed, reportFile, cases };
}

export async function main(): Promise<void> {
  const { values } = parseArgs({
    options: { build: { type: 'string' }, report: { type: 'string' } },
  });
  if (!values.build)
    throw new Error(
      'Usage: check-image-codecs --build DIR [--report FILE inside .local]',
    );
  const controller = new AbortController();
  const cancel = () =>
    controller.abort(new Error('Image codec verification interrupted'));
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try {
    const result = await verifyImageCodecs({
      buildDirectory: values.build,
      ...(values.report ? { reportFile: values.report } : {}),
      signal: controller.signal,
    });
    console.log(
      JSON.stringify(
        {
          passed: result.passed,
          reportFile: result.reportFile,
          cases: result.cases.map(({ name, status, error }) => ({
            name,
            status,
            ...(error ? { error } : {}),
          })),
        },
        null,
        2,
      ),
    );
    if (!result.passed) process.exitCode = 1;
  } finally {
    process.off('SIGINT', cancel);
    process.off('SIGTERM', cancel);
  }
}
