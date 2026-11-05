import { BusinessStateErrorCode as ErrorCode } from '@karuyomi/protocol';
import type { CustomCover } from '@karuyomi/protocol';
import { COVER_BYTE_LIMIT, COVER_DIMENSION_LIMIT } from '@karuyomi/contracts';
import { imageDimensionsFromData } from 'image-dimensions';
import { hashText, StateError } from './state-store.js';

export async function verifyCoverImage(image: File, cover: CustomCover) {
  if (image.size < 1 || image.size > COVER_BYTE_LIMIT)
    throw new StateError(
      ErrorCode.LIMIT_EXCEEDED,
      'Cover image exceeds the byte limit',
      413,
    );
  if (image.size !== cover.byteLength || image.type !== cover.contentType)
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Cover image does not match its descriptor',
    );
  const bytes = new Uint8Array(await image.arrayBuffer());
  const dimensions = imageDimensionsFromData(bytes);
  if (
    !dimensions ||
    !['jpeg', 'png'].includes(dimensions.type) ||
    `image/${dimensions.type}` !== cover.contentType ||
    !Number.isInteger(dimensions.width) ||
    !Number.isInteger(dimensions.height) ||
    dimensions.width < 1 ||
    dimensions.height < 1 ||
    dimensions.width > COVER_DIMENSION_LIMIT ||
    dimensions.height > COVER_DIMENSION_LIMIT
  )
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Cover must be a JPEG or PNG within the dimension limit',
    );
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const sha256 = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
  if (sha256 !== cover.sha256)
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Cover image hash does not match',
    );
  return bytes;
}

export async function uploadCover(
  bucket: R2Bucket,
  subject: string,
  cover: CustomCover,
  bytes: Uint8Array<ArrayBuffer>,
) {
  // Each actual attempt writes a fresh key. A failed attempt can never later
  // overwrite a current object; durable mutation retries do not call this.
  const key = `covers/${await hashText(subject)}/${cover.assetId}/${crypto.randomUUID()}`;
  await bucket.put(key, bytes, {
    httpMetadata: { contentType: cover.contentType },
  });
  return key;
}
