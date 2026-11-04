import * as pb from '@karuyomi/protocol';
import { z } from 'zod';
import {
  codec,
  plainMessage,
  plain,
  parseMessage,
  requireCondition,
  requireFields,
  messageJson,
  type PlainMessage,
} from './codec.ts';
import { validId, validSourceId } from './static-control.ts';
import { runtimeErrorData, validatePageList } from './runtime-control.ts';

export const IMAGE_CHUNK_LIMIT = 64 * 1024;
export const IMAGE_BODY_LIMIT = 64 * 1024 * 1024;
export const IMAGE_PIXEL_LIMIT = 16 * 1024 * 1024;
export const IMAGE_RESIDENT_PIXEL_LIMIT = 32 * 1024 * 1024;
export const IMAGE_RESOURCE_LIMIT = 6;
export const IMAGE_HEADER_LIMIT = 1024 * 1024;
export const ENCODED_IMAGE_BODY_LIMIT = 8 * 1024 * 1024;
export const ENCODED_IMAGE_WIDTH_LIMIT = 4096;
export const ENCODED_IMAGE_HEIGHT_LIMIT = 100000;
export const ENCODED_JPEG_HEIGHT_LIMIT = 65500;
export const IMAGE_TILE_BODY_LIMIT = 8 * 1024 * 1024;
export const IMAGE_TILE_CACHE_BYTE_LIMIT = 16 * 1024 * 1024;
export const IMAGE_TILE_COUNT_LIMIT = 64;
export const IMAGE_TILE_PIXEL_LIMIT = 32 * 1024 * 1024;
export const IMAGE_WINDOW_WAIT_LIMIT_MS = 25000;

// MIME support is a business capability, not a duplicate message structure.
export const imageMimeTypeSchema = z.enum([
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
  'image/avif',
  'image/heic',
]);
export type ImageMimeType = z.infer<typeof imageMimeTypeSchema>;
export type AcquireImage = PlainMessage<pb.AcquireImage>;
export type CancelImage = PlainMessage<pb.CancelImage>;
export type ReleaseImage = PlainMessage<pb.ReleaseImage>;
export type ClosePageSession = PlainMessage<pb.ClosePageSession>;
export type ProcessedImage = Omit<
  PlainMessage<pb.ProcessedImage>,
  'mimeType'
> & { mimeType: ImageMimeType };
export type EncodedImage = Omit<PlainMessage<pb.EncodedImage>, 'mimeType'> & {
  mimeType: 'image/png' | 'image/jpeg';
};
export type ImageResource = Omit<PlainMessage<pb.ImageResource>, 'mimeType'> & {
  mimeType: ImageMimeType;
};
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
  const mimeType = imageMimeTypeSchema.parse(value.mimeType);
  requireCondition(
    value.byteLength > 0 &&
      value.byteLength <= IMAGE_BODY_LIMIT &&
      value.width > 0 &&
      value.height > 0 &&
      value.width * value.height <= IMAGE_PIXEL_LIMIT,
    'Invalid processed image budget',
  );
  return { ...value, mimeType };
});
export const encodedImageSchema = codec<EncodedImage>((input) => {
  const value = plainMessage(pb.EncodedImageSchema, input);
  [value.resourceId, value.generation].forEach(validId);
  requireCondition(
    value.mimeType === 'image/png' || value.mimeType === 'image/jpeg',
    'Unsupported encoded image format',
  );
  const heightLimit =
    value.mimeType === 'image/jpeg'
      ? ENCODED_JPEG_HEIGHT_LIMIT
      : ENCODED_IMAGE_HEIGHT_LIMIT;
  requireCondition(
    value.byteLength > 0 &&
      value.byteLength <= ENCODED_IMAGE_BODY_LIMIT &&
      value.rawWidth > 0 &&
      value.rawWidth <= ENCODED_IMAGE_WIDTH_LIMIT &&
      value.rawHeight > 0 &&
      value.rawHeight <= heightLimit &&
      value.orientation >= 1 &&
      value.orientation <= 8,
    'Invalid encoded image budget or orientation',
  );
  return { ...value, mimeType: value.mimeType };
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

export type OpenImagePage = PlainMessage<pb.OpenImagePage>;
export type CloseImagePage = PlainMessage<pb.CloseImagePage>;
export type ReleaseImageTile = PlainMessage<pb.ReleaseImageTile>;
export type WaitImageWindow = PlainMessage<pb.WaitImageWindow>;
export type ImageDenominator = 1 | 2 | 4;
export type RequestImageWindow = Omit<
  PlainMessage<pb.RequestImageWindow>,
  'denominator'
> & { denominator: ImageDenominator };
export type ImagePage = Omit<PlainMessage<pb.ImagePage>, 'encoded'> & {
  encoded: EncodedImage;
};
export type ImageTileHeader = Omit<
  PlainMessage<pb.ImageTileHeader>,
  'denominator'
> & {
  denominator: ImageDenominator;
};
export type ImageSourceRect = PlainMessage<pb.ImageSourceRect>;
export type ImageTile = Omit<
  PlainMessage<pb.ImageTile>,
  'denominator' | 'resource' | 'sourceRect'
> & {
  denominator: ImageDenominator;
  resource: ImageResource;
  sourceRect: ImageSourceRect;
};
export type ImageWindowSnapshot = Omit<
  PlainMessage<pb.ImageWindowSnapshot>,
  'header' | 'tiles' | 'state'
> & {
  state:
    | pb.ImageWindowState.PENDING
    | pb.ImageWindowState.COMPLETE
    | pb.ImageWindowState.FAILED;
  header?: ImageTileHeader;
  tiles: ImageTile[];
};

function validDenominator(value: number): asserts value is ImageDenominator {
  requireCondition(
    value === 1 || value === 2 || value === 4,
    'Invalid image denominator',
  );
}
export const openImagePageSchema = codec<OpenImagePage>((input) => {
  const value = plainMessage(pb.OpenImagePageSchema, input);
  [value.resourceId, value.generation].forEach(validId);
  return value;
});
export const closeImagePageSchema = codec<CloseImagePage>((input) => {
  const value = plainMessage(pb.CloseImagePageSchema, input);
  [value.pageId, value.generation].forEach(validId);
  return value;
});
export const releaseImageTileSchema = codec<ReleaseImageTile>((input) => {
  const value = plainMessage(pb.ReleaseImageTileSchema, input);
  [value.leaseId, value.generation].forEach(validId);
  return value;
});
export const requestImageWindowSchema = codec<RequestImageWindow>((input) => {
  const value = plainMessage(pb.RequestImageWindowSchema, input);
  [value.pageId, value.generation, value.windowId].forEach(validId);
  validDenominator(value.denominator);
  requireCondition(
    value.sourceY < value.sourceEndY &&
      value.sourceEndY <= ENCODED_IMAGE_HEIGHT_LIMIT,
    'Invalid raw image window',
  );
  return { ...value, denominator: value.denominator };
});
export const waitImageWindowSchema = codec<WaitImageWindow>((input) => {
  const value = plainMessage(pb.WaitImageWindowSchema, input);
  [value.pageId, value.generation, value.windowId].forEach(validId);
  requireCondition(
    value.timeoutMs === undefined ||
      (value.timeoutMs > 0 && value.timeoutMs <= IMAGE_WINDOW_WAIT_LIMIT_MS),
    'Invalid image window wait deadline',
  );
  return value;
});
export const imagePageSchema = codec<ImagePage>((input) => {
  const value = plainMessage(pb.ImagePageSchema, input);
  [value.pageId, value.generation].forEach(validId);
  requireFields(value, ['encoded']);
  const encoded = encodedImageSchema.parse(
    messageJson(pb.EncodedImageSchema, value.encoded),
  );
  requireCondition(
    encoded.generation === value.generation,
    'Encoded page generation mismatch',
  );
  return { ...value, encoded };
});
export const imageTileHeaderSchema = codec<ImageTileHeader>((input) => {
  const value = plainMessage(pb.ImageTileHeaderSchema, input);
  validDenominator(value.denominator);
  requireCondition(
    value.sourceWidth > 0 &&
      value.sourceWidth <= ENCODED_IMAGE_WIDTH_LIMIT &&
      value.sourceHeight > 0 &&
      value.sourceHeight <= ENCODED_IMAGE_HEIGHT_LIMIT &&
      value.width === Math.ceil(value.sourceWidth / value.denominator) &&
      value.height === Math.ceil(value.sourceHeight / value.denominator),
    'Invalid image tile header',
  );
  return { ...value, denominator: value.denominator };
});
export const imageTileSchema = codec<ImageTile>((input) => {
  const value = plainMessage(pb.ImageTileSchema, input);
  [value.leaseId, value.sessionId].forEach(validId);
  requireFields(value, ['resource', 'sourceRect']);
  validDenominator(value.denominator);
  const resource = imageResourceSchema.parse(
    messageJson(pb.ImageResourceSchema, value.resource),
  );
  const sourceRect = plain(value.sourceRect);
  requireCondition(
    resource.resourceId === value.leaseId &&
      resource.mimeType === 'image/png' &&
      resource.byteLength <= IMAGE_TILE_BODY_LIMIT &&
      resource.width <= ENCODED_IMAGE_WIDTH_LIMIT &&
      resource.height <= 256 &&
      sourceRect.x === 0 &&
      sourceRect.width > 0 &&
      sourceRect.width <= ENCODED_IMAGE_WIDTH_LIMIT &&
      sourceRect.height > 0 &&
      sourceRect.y + sourceRect.height <= ENCODED_IMAGE_HEIGHT_LIMIT &&
      resource.width === Math.ceil(sourceRect.width / value.denominator) &&
      resource.height === Math.ceil(sourceRect.height / value.denominator) &&
      sourceRect.y === value.index * 256 * value.denominator,
    'Invalid image tile resource or raw geometry',
  );
  return { ...value, denominator: value.denominator, resource, sourceRect };
});
export const imageWindowSnapshotSchema = codec<ImageWindowSnapshot>((input) => {
  const value = plainMessage(pb.ImageWindowSnapshotSchema, input);
  [value.pageId, value.generation, value.windowId].forEach(validId);
  requireCondition(
    value.state === pb.ImageWindowState.PENDING ||
      value.state === pb.ImageWindowState.COMPLETE ||
      value.state === pb.ImageWindowState.FAILED,
    'Invalid image window state',
  );
  const state = value.state;
  const header =
    value.header === undefined
      ? undefined
      : imageTileHeaderSchema.parse(
          messageJson(pb.ImageTileHeaderSchema, value.header),
        );
  const tiles = value.tiles.map((tile) =>
    imageTileSchema.parse(messageJson(pb.ImageTileSchema, tile)),
  );
  const ids = [
    ...tiles.map((tile) => tile.leaseId),
    ...value.invalidatedLeaseIds,
  ];
  ids.forEach(validId);
  requireCondition(
    ids.length <= IMAGE_TILE_COUNT_LIMIT &&
      new Set(ids).size === ids.length &&
      new Set(tiles.map((tile) => tile.index)).size === tiles.length &&
      tiles.reduce(
        (sum, tile) => sum + tile.resource.width * tile.resource.height,
        0,
      ) <= IMAGE_TILE_PIXEL_LIMIT &&
      tiles.reduce((sum, tile) => sum + tile.resource.byteLength, 0) <=
        IMAGE_TILE_CACHE_BYTE_LIMIT,
    'Invalid image window lease budget or identity',
  );
  requireCondition(
    tiles.length === 0 || header !== undefined,
    'Image tiles require a decoded header',
  );
  for (const tile of tiles) {
    requireCondition(
      header !== undefined &&
        tile.resource.generation === value.generation &&
        tile.denominator === header.denominator &&
        tile.sourceRect.width === header.sourceWidth &&
        tile.resource.width === header.width &&
        tile.sourceRect.y < header.sourceHeight &&
        tile.sourceRect.height ===
          Math.min(
            tile.resource.height * tile.denominator,
            header.sourceHeight - tile.sourceRect.y,
          ) &&
        tile.resource.height ===
          Math.min(256, header.height - tile.index * 256),
      'Image tile does not match its page header',
    );
  }
  if (value.error) runtimeErrorData(value.error);
  requireCondition(
    (state === pb.ImageWindowState.FAILED) === (value.error !== undefined),
    'Image window failure requires exactly its error',
  );
  requireCondition(
    state !== pb.ImageWindowState.COMPLETE ||
      (header !== undefined && tiles.every((tile) => !tile.provisional)),
    'Complete image windows require committed tiles',
  );
  const { header: _header, ...snapshot } = value;
  return {
    ...snapshot,
    state,
    ...(header === undefined ? {} : { header }),
    tiles,
  };
});
