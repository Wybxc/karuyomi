import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import {
  codec,
  messageJson,
  parseMessage,
  plain,
  requireCondition,
  type PlainMessage,
} from './codec.ts';
import {
  IMAGE_CHUNK_LIMIT,
  processedImageSchema,
  type ProcessedImage,
} from './image-control.ts';
import {
  runtimeErrorData,
  runtimeErrorMessage,
  type RuntimeErrorData,
} from './runtime-control.ts';

// The ArrayBuffer remains an out-of-band transferable. Only its bounded
// descriptor and ACK participate in the generated control protocol.
export type ImageFrame =
  | ({ type: 'meta' } & PlainMessage<pb.ImageMeta>)
  | ({ type: 'data'; buffer: ArrayBuffer } & Pick<
      PlainMessage<pb.ImageData>,
      'seq'
    >)
  | ({ type: 'end' } & PlainMessage<pb.ImageEnd>)
  | ({ type: 'ack'; resource?: ProcessedImage } & Pick<
      PlainMessage<pb.ImageAck>,
      'seq'
    >)
  | { type: 'abort'; error: RuntimeErrorData };
export type ImageFrameWire = {
  control: pb.ImageFrameControlJson;
  buffer?: ArrayBuffer;
};

export function encodeImageFrame(frame: ImageFrame): ImageFrameWire {
  let control: pb.ImageFrameControl;
  switch (frame.type) {
    case 'meta':
      control = create(pb.ImageFrameControlSchema, {
        frame: {
          case: 'meta',
          value: { seq: frame.seq, mimeType: frame.mimeType },
        },
      });
      break;
    case 'data':
      control = create(pb.ImageFrameControlSchema, {
        frame: {
          case: 'data',
          value: { seq: frame.seq, byteLength: frame.buffer.byteLength },
        },
      });
      return {
        control: messageJson(pb.ImageFrameControlSchema, control),
        buffer: frame.buffer,
      };
    case 'end':
      control = create(pb.ImageFrameControlSchema, {
        frame: {
          case: 'end',
          value: { seq: frame.seq, totalBytes: frame.totalBytes },
        },
      });
      break;
    case 'ack':
      control = create(pb.ImageFrameControlSchema, {
        frame: {
          case: 'ack',
          value: {
            seq: frame.seq,
            ...(frame.resource ? { resource: frame.resource } : {}),
          },
        },
      });
      break;
    case 'abort':
      control = create(pb.ImageFrameControlSchema, {
        frame: { case: 'abort', value: runtimeErrorMessage(frame.error) },
      });
      break;
  }
  return { control: messageJson(pb.ImageFrameControlSchema, control) };
}

export const imageFrameSchema = codec<ImageFrame>((input) => {
  requireCondition(
    input !== null && typeof input === 'object' && 'control' in input,
    'Image control descriptor is required',
  );
  requireCondition(
    Object.keys(input).every((key) => key === 'control' || key === 'buffer'),
    'Unknown image envelope field',
  );
  const control = parseMessage(
    pb.ImageFrameControlSchema,
    input.control,
    16 * 1024,
  );
  const buffer = 'buffer' in input ? input.buffer : undefined;
  if (control.frame.case !== 'data')
    requireCondition(buffer === undefined, 'Unexpected image transferable');
  switch (control.frame.case) {
    case 'meta':
      requireCondition(
        control.frame.value.seq === 0 &&
          control.frame.value.mimeType.length <= 128,
        'Invalid image META',
      );
      return { type: 'meta', ...plain(control.frame.value) };
    case 'data':
      requireCondition(
        buffer instanceof ArrayBuffer &&
          buffer.byteLength > 0 &&
          buffer.byteLength <= IMAGE_CHUNK_LIMIT &&
          buffer.byteLength === control.frame.value.byteLength,
        'Invalid image DATA',
      );
      return { type: 'data', seq: control.frame.value.seq, buffer };
    case 'end':
      return { type: 'end', ...plain(control.frame.value) };
    case 'ack': {
      const value = control.frame.value;
      return {
        type: 'ack',
        seq: value.seq,
        ...(value.resource
          ? {
              resource: processedImageSchema.parse(
                messageJson(pb.ProcessedImageSchema, value.resource),
              ),
            }
          : {}),
      };
    }
    case 'abort':
      return { type: 'abort', error: runtimeErrorData(control.frame.value) };
    default:
      throw new Error('Image frame must select a control descriptor');
  }
});
