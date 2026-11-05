import * as pb from '@karuyomi/protocol';
import { z } from 'zod';
import {
  codec,
  jsonText,
  messageJson,
  parseMessage,
  requireCondition,
  requireFields,
  SOURCE_MEMO_LIMIT,
  validateJsonDepth,
} from './codec.ts';
import { validId, validSourceId } from './static-control.ts';

export const businessSchemaVersion = 1;
export const BUSINESS_REQUEST_LIMIT = 128 * 1024;
export const BUSINESS_RESPONSE_LIMIT = 2 * 1024 * 1024;
export const LIBRARY_METADATA_LIMIT = 96 * 1024;
export const LIBRARY_PAGE_SIZE = 8;
export const CHAPTER_PAGE_LIMIT = 2048;

const mutationId = z.uuid();
const mangaKey = z.string().regex(/^[a-f0-9]{64}$/);

function uint32(value: number): void {
  requireCondition(
    Number.isInteger(value) && value >= 0 && value <= 0xffff_ffff,
    'Business revision or epoch exceeds uint32',
  );
}

export function validateLibraryMetadata(value: pb.LibraryMetadata): void {
  validId(value.packageName);
  validSourceId(value.sourceId);
  requireCondition(
    value.sourceName.length > 0 &&
      value.sourceName.length <= 256 &&
      value.sourceLang.length > 0 &&
      value.sourceLang.length <= 64,
    'Invalid Source metadata',
  );
  requireFields(value, ['manga']);
  requireCondition(
    value.manga.url.length > 0 &&
      value.manga.url.length <= 16_384 &&
      value.manga.title.length > 0,
    'Explicit manga reference and title are required',
  );
  requireCondition(
    value.manga.updateStrategy === '' ||
      value.manga.updateStrategy === 'ALWAYS_UPDATE' ||
      value.manga.updateStrategy === 'ONLY_FETCH_ONCE',
    'Unknown manga update strategy',
  );
  const memo = value.manga.memoJson;
  if (memo !== undefined) {
    requireCondition(
      new TextEncoder().encode(memo).byteLength <= SOURCE_MEMO_LIMIT,
      'Source memo exceeds its byte budget',
    );
    const parsed: unknown = JSON.parse(memo);
    validateJsonDepth(parsed);
    requireCondition(
      parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed),
      'Source memo must be a JSON object',
    );
  }
  jsonText(
    messageJson(pb.LibraryMetadataSchema, value),
    LIBRARY_METADATA_LIMIT,
  );
}

export function validateReadingAnchor(value: pb.ReadingAnchor): void {
  validId(value.chapterKey);
  validId(value.pageKey);
  validId(value.manifestVersion);
  uint32(value.pageIndexHint);
  requireCondition(
    value.pageIndexHint < CHAPTER_PAGE_LIMIT &&
      Number.isFinite(value.normalizedOffset) &&
      value.normalizedOffset >= 0 &&
      value.normalizedOffset <= 1,
    'Invalid reading anchor',
  );
}

export function validateChapterProgress(value: pb.ChapterProgressState): void {
  validId(value.chapterKey);
  uint32(value.epoch);
  requireFields(value, ['current']);
  validateReadingAnchor(value.current);
  requireCondition(
    value.current.chapterKey === value.chapterKey,
    'Current anchor belongs to a different chapter',
  );
  if (value.furthest) {
    validateReadingAnchor(value.furthest);
    requireCondition(
      value.furthest.chapterKey === value.chapterKey,
      'Furthest anchor belongs to a different chapter',
    );
  }
}

export function validateChapterSnapshot(value: pb.ChapterSnapshot): void {
  validId(value.chapterKey);
  validId(value.manifestVersion);
  requireCondition(
    value.pageKeys.length > 0 &&
      value.pageKeys.length <= CHAPTER_PAGE_LIMIT &&
      new Set(value.pageKeys).size === value.pageKeys.length,
    'Chapter snapshot pages must be nonempty and unique',
  );
  value.pageKeys.forEach(validId);
}

export function validateMangaState(value: pb.MangaState): void {
  mangaKey.parse(value.mangaKey);
  uint32(value.revision);
  uint32(value.addedAtSeconds);
  if (value.metadata) validateLibraryMetadata(value.metadata);
  requireCondition(
    !value.favorite || value.metadata !== undefined,
    'Favorite manga requires Source metadata',
  );
  if (value.resume) validId(value.resume.chapterKey);
}

export const stateMutationSchema = codec<pb.StateMutation>((input) => {
  const value = parseMessage(
    pb.StateMutationSchema,
    input,
    BUSINESS_REQUEST_LIMIT,
  );
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  mutationId.parse(value.mutationId);
  mangaKey.parse(value.mangaKey);
  uint32(value.expectedRevision);
  switch (value.operation.case) {
    case 'setFavorite':
      requireFields(value.operation.value, ['metadata']);
      validateLibraryMetadata(value.operation.value.metadata);
      break;
    case 'updateMetadata':
      validateLibraryMetadata(value.operation.value);
      break;
    case 'saveProgress': {
      const operation = value.operation.value;
      requireFields(operation, ['snapshot', 'progress']);
      validateChapterSnapshot(operation.snapshot);
      validateChapterProgress(operation.progress);
      requireFields(operation.progress, ['current']);
      const current = operation.progress.current;
      requireCondition(
        operation.progress.chapterKey === operation.snapshot.chapterKey &&
          current.manifestVersion === operation.snapshot.manifestVersion &&
          operation.snapshot.pageKeys[current.pageIndexHint] ===
            current.pageKey,
        'Current progress does not match its chapter snapshot',
      );
      break;
    }
    case 'resetProgress':
      requireFields(value.operation.value, ['snapshot']);
      validateChapterSnapshot(value.operation.value.snapshot);
      break;
    default:
      throw new Error('A business state mutation operation is required');
  }
  return value;
});

function validateError(value: pb.BusinessStateError): void {
  requireCondition(
    Number.isInteger(value.code) &&
      value.code >= pb.BusinessStateErrorCode.INVALID_INPUT &&
      value.code <= pb.BusinessStateErrorCode.LIMIT_EXCEEDED &&
      value.message.length > 0 &&
      value.message.length <= 1024,
    'Invalid business state error',
  );
}

function validateResponse(value: {
  schemaVersion: number;
  accountRevision: number;
  manga?: pb.MangaState | undefined;
  progress?: pb.ChapterProgressState | undefined;
  error?: pb.BusinessStateError | undefined;
}): void {
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  uint32(value.accountRevision);
  if (value.error) validateError(value.error);
  else requireFields(value, ['manga']);
  if (value.manga) validateMangaState(value.manga);
  if (value.progress) validateChapterProgress(value.progress);
}

export const stateMutationResponseSchema = codec<pb.StateMutationResponse>(
  (input) => {
    const value = parseMessage(
      pb.StateMutationResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    if (!value.error || value.mutationId !== '')
      mutationId.parse(value.mutationId);
    validateResponse(value);
    return value;
  },
);

export const mangaStateResponseSchema = codec<pb.MangaStateResponse>(
  (input) => {
    const value = parseMessage(
      pb.MangaStateResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    validateResponse(value);
    return value;
  },
);

export const libraryPageResponseSchema = codec<pb.LibraryPageResponse>(
  (input) => {
    const value = parseMessage(
      pb.LibraryPageResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    requireCondition(
      value.schemaVersion === businessSchemaVersion,
      'Unsupported business state schema',
    );
    uint32(value.accountRevision);
    if (value.error) {
      validateError(value.error);
      requireCondition(
        value.entries.length === 0 && value.nextKey === '',
        'Failed library page cannot contain entries',
      );
    }
    requireCondition(
      value.entries.length <= LIBRARY_PAGE_SIZE &&
        new Set(value.entries.map((entry) => entry.mangaKey)).size ===
          value.entries.length,
      'Invalid library page',
    );
    let previousKey: string | undefined;
    for (const entry of value.entries) {
      validateMangaState(entry);
      requireCondition(entry.favorite, 'Library entries must be favorites');
      requireCondition(
        previousKey === undefined || previousKey < entry.mangaKey,
        'Library page keys must be unique and ordered',
      );
      previousKey = entry.mangaKey;
    }
    if (value.nextKey !== '') {
      mangaKey.parse(value.nextKey);
      requireCondition(
        value.nextKey === value.entries.at(-1)?.mangaKey,
        'Library cursor must identify its last entry',
      );
    }
    return value;
  },
);
