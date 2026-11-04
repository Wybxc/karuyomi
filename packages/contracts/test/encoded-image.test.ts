import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { expect, test } from 'vitest';
import {
  encodedImageSchema,
  encodeControlResponse,
  encodeImageFrame,
  imageFrameSchema,
  parseControlRequest,
  parseControlResponse,
  workerResponseSchema,
  protocolVersion,
} from '../src/index.js';

const encoded = {
  resourceId: 'encoded-page',
  generation: 'generation',
  mimeType: 'image/png',
  byteLength: 8 * 1024 * 1024,
  rawWidth: 1080,
  rawHeight: 40000,
  orientation: 1,
};
const request = {
  requestId: 'acquire',
  generation: 'generation',
  sourceId: '1',
  pageSessionId: 'page-session',
  pageKey: 'page',
};

test('encoded page metadata preserves long raw geometry and every EXIF direction', () => {
  for (let orientation = 1; orientation <= 8; orientation++) {
    expect(encodedImageSchema.parse({ ...encoded, orientation })).toEqual({
      ...encoded,
      orientation,
    });
  }
  for (const patch of [
    { byteLength: 0 },
    { byteLength: encoded.byteLength + 1 },
    { rawWidth: 0 },
    { rawWidth: 4097 },
    { rawHeight: 0 },
    { rawHeight: 100001 },
    { orientation: 0 },
    { orientation: 9 },
    { orientation: 1.5 },
    { mimeType: 'image/webp' },
    { url: 'blob:unexpected' },
    { rawHeight: 65501, mimeType: 'image/jpeg' },
  ])
    expect(encodedImageSchema.safeParse({ ...encoded, ...patch }).success).toBe(
      false,
    );
  expect(
    encodedImageSchema.parse({
      ...encoded,
      mimeType: 'image/jpeg',
      rawHeight: 65500,
    }).rawHeight,
  ).toBe(65500);
});

test('generated control and worker responses select encoded pages without a display URL', () => {
  expect(
    parseControlRequest({ requestId: 'control', acquireEncodedImage: request })
      .command.case,
  ).toBe('acquireEncodedImage');
  expect(
    parseControlResponse({ requestId: 'control', encodedImage: encoded }).result
      .case,
  ).toBe('encodedImage');
  const envelope = {
    protocolVersion,
    workerInstanceId: 'worker',
    generation: 'generation',
    buildId: 'build',
    requestId: 'acquire',
  };
  expect(
    workerResponseSchema.parse({ envelope, encodedImage: encoded }).result.case,
  ).toBe('encodedImage');
  expect(() =>
    workerResponseSchema.parse({
      envelope,
      encodedImage: { ...encoded, generation: 'expired' },
    }),
  ).toThrow(/envelope/);
  expect(() =>
    parseControlResponse({ requestId: 'control', image: encoded }),
  ).toThrow();
});

test('END ACK descriptors are exclusive across both encoding directions', () => {
  const descriptor = encodedImageSchema.parse(encoded);
  expect(
    imageFrameSchema.parse(
      encodeImageFrame({ type: 'ack', seq: 3, encoded: descriptor }),
    ),
  ).toEqual({ type: 'ack', seq: 3, encoded: descriptor });
  const resource = {
    resourceId: 'small',
    generation: 'generation',
    mimeType: 'image/png' as const,
    byteLength: 1,
    width: 1,
    height: 1,
  };
  expect(() =>
    encodeImageFrame({ type: 'ack', seq: 3, encoded: descriptor, resource }),
  ).toThrow(/Ambiguous/);
  expect(() =>
    imageFrameSchema.parse({
      control: {
        ack: { seq: 3, encoded: descriptor, resource },
      },
    }),
  ).toThrow(/Ambiguous/);
  expect(
    imageFrameSchema.parse(encodeImageFrame({ type: 'ack', seq: 1 })),
  ).toEqual({ type: 'ack', seq: 1 });
  expect(() =>
    encodeImageFrame({
      type: 'ack',
      seq: 3,
      encoded: { ...descriptor, orientation: 9 },
    }),
  ).toThrow();
  // Generated messages do not bypass business validation at the wire boundary.
  const message = create(pb.ControlResponseSchema, {
    requestId: 'control',
    result: {
      case: 'encodedImage',
      value: create(pb.EncodedImageSchema, {
        ...descriptor,
        rawHeight: 100001,
      }),
    },
  });
  expect(() => encodeControlResponse(message)).toThrow();
});
