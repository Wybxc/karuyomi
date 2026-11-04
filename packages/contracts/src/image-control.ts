import * as pb from '@karuyomi/protocol';
import {
  codec,
  plainMessage,
  plain,
  parseMessage,
  requireCondition,
  type PlainMessage,
} from './codec.ts';
import { validId, validSourceId } from './static-control.ts';
import { validatePageList } from './runtime-control.ts';

export const IMAGE_CHUNK_LIMIT = 64 * 1024;
export const IMAGE_BODY_LIMIT = 64 * 1024 * 1024;
export const IMAGE_RESOURCE_LIMIT = 6;

export type AcquireImage = PlainMessage<pb.AcquireImage>;
export type CancelImage = PlainMessage<pb.CancelImage>;
export type ReleaseImage = PlainMessage<pb.ReleaseImage>;
export type ClosePageSession = PlainMessage<pb.ClosePageSession>;
export type ProcessedImage = PlainMessage<pb.ProcessedImage>;
export type ImageResource = PlainMessage<pb.ImageResource>;
export type PageList = Omit<PlainMessage<pb.PageList>, 'pages'> & {
  pages: PlainMessage<pb.Page>[];
};
export type Released = PlainMessage<pb.Released>;
export type Closed = PlainMessage<pb.Closed>;
export type Completed = PlainMessage<pb.Completed>;

export const acquireImageSchema = codec<AcquireImage>((input) => {
  const value = plainMessage(pb.AcquireImageSchema, input);
  [
    value.requestId,
    value.pageSessionId,
    value.pageKey,
    value.generation,
  ].forEach(validId);
  validSourceId(value.sourceId);
  if (value.timeoutMs !== undefined)
    requireCondition(
      value.timeoutMs > 0 && value.timeoutMs <= 300_000,
      'Invalid image deadline',
    );
  return value;
});
export const cancelImageSchema = codec<CancelImage>((input) => {
  const value = plainMessage(pb.CancelImageSchema, input);
  [value.requestId, value.generation].forEach(validId);
  return value;
});
export const releaseImageSchema = codec<ReleaseImage>((input) => {
  const value = plainMessage(pb.ReleaseImageSchema, input);
  [value.resourceId, value.generation].forEach(validId);
  return value;
});
export const closePageSessionSchema = codec<ClosePageSession>((input) => {
  const value = plainMessage(pb.ClosePageSessionSchema, input);
  [value.pageSessionId, value.generation].forEach(validId);
  return value;
});
export const processedImageSchema = codec<ProcessedImage>((input) => {
  const value = plainMessage(pb.ProcessedImageSchema, input);
  [value.resourceId, value.generation].forEach(validId);
  requireCondition(
    value.byteLength > 0 && value.byteLength <= IMAGE_BODY_LIMIT,
    'Invalid image byte budget',
  );
  return value;
});
export const imageResourceSchema = codec<ImageResource>((input) => {
  const value = plainMessage(pb.ImageResourceSchema, input);
  const { url, ...processed } = value;
  const descriptor = processedImageSchema.parse(processed);
  requireCondition(
    url.startsWith('blob:'),
    'Images require a managed Blob resource',
  );
  return { ...descriptor, url };
});
export const pageListSchema = codec<PageList>((input) => {
  const value = parseMessage(pb.PageListSchema, input);
  validatePageList(value);
  return { ...plain(value), pages: value.pages.map(plain) };
});
export const releasedSchema = codec<Released>((input) => {
  const value = plainMessage(pb.ReleasedSchema, input);
  requireCondition(value.released, 'Image release was not acknowledged');
  return value;
});
export const closedSchema = codec<Closed>((input) => {
  const value = plainMessage(pb.ClosedSchema, input);
  requireCondition(value.closed, 'Page session close was not acknowledged');
  return value;
});
export const completedSchema = codec<Completed>((input) => {
  const value = plainMessage(pb.CompletedSchema, input);
  requireCondition(value.completed, 'Control operation was not acknowledged');
  return value;
});
