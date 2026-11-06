import { create, enumToJson } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import {
  codec,
  type PlainMessage,
  jsonText,
  messageJson,
  plainMessage,
  parseMessage,
  requireCondition,
  requireFields,
  SOURCE_ARGUMENT_LIMIT,
  SOURCE_MEMO_LIMIT,
  PAGE_LIST_JSON_LIMIT,
  validateJsonDepth,
} from './codec.ts';
import { hostAbi, protocolVersion, runtimeBaseline } from './generated.ts';
import { validId, validSourceId } from './static-control.ts';

export type RuntimeHello = Required<PlainMessage<pb.RuntimeHello>>;
export type SourceInfo = PlainMessage<pb.SourceInfo> &
  Required<Pick<PlainMessage<pb.SourceInfo>, 'id' | 'name' | 'lang'>>;
export type RuntimeSession = Omit<
  Required<PlainMessage<pb.RuntimeSession>>,
  'sources'
> & { sources: SourceInfo[] };
export type RpcEnvelope = Required<PlainMessage<pb.RpcEnvelope>>;
export type SourceCall = pb.SourceCall;
export type SourceResult = pb.SourceResult;
export type SourcePayload = pb.SourceResult['payload'];
type ErrorName<T> = T extends `RUNTIME_ERROR_CODE_${infer N}`
  ? Lowercase<N>
  : never;
export type RuntimeErrorCode = Exclude<
  ErrorName<NonNullable<pb.RuntimeErrorJson['code']>>,
  'unspecified'
>;
export type RuntimeErrorData = Omit<
  Required<pb.RuntimeErrorJson>,
  'code' | 'javaClass'
> & {
  code: RuntimeErrorCode;
  javaClass?: string;
};
const errorCodes = new Set(
  pb.RuntimeErrorCodeSchema.values
    .filter((value) => value.number !== 0)
    .map((value) =>
      value.name.replace(/^RUNTIME_ERROR_CODE_/, '').toLowerCase(),
    ),
);
function isErrorCode(value: unknown): value is RuntimeErrorCode {
  return typeof value === 'string' && errorCodes.has(value);
}
export const runtimeErrorCodeSchema = codec<RuntimeErrorCode>((input) => {
  requireCondition(isErrorCode(input), 'Unknown runtime error code');
  return input;
});
export function runtimeErrorMessage(value: RuntimeErrorData): pb.RuntimeError {
  return parseMessage(pb.RuntimeErrorSchema, {
    ...value,
    code: `RUNTIME_ERROR_CODE_${value.code.toUpperCase()}`,
  });
}
export function runtimeErrorData(value: pb.RuntimeError): RuntimeErrorData {
  const name = enumToJson(pb.RuntimeErrorCodeSchema, value.code);
  requireCondition(typeof name === 'string', 'Unknown runtime error code');
  const code = runtimeErrorCodeSchema.parse(
    name.replace(/^RUNTIME_ERROR_CODE_/, '').toLowerCase(),
  );
  return {
    code,
    message: value.message,
    retryable: value.retryable,
    ...(value.javaClass !== undefined ? { javaClass: value.javaClass } : {}),
  };
}
export const runtimeErrorSchema = codec((input) =>
  runtimeErrorData(parseMessage(pb.RuntimeErrorSchema, input)),
);

export const sourceInfoSchema = codec<SourceInfo>((input) => {
  const value = plainMessage(pb.SourceInfoSchema, input);
  requireFields(value, ['id', 'name', 'lang']);
  validSourceId(value.id);
  return value;
});
export const runtimeHelloSchema = codec<RuntimeHello>((input) => {
  const value = plainMessage(pb.RuntimeHelloSchema, input);
  requireFields(value, [
    'protocolVersion',
    'hostAbi',
    'runtimeBaseline',
    'generation',
    'capabilities',
    'sourceReady',
  ]);
  requireCondition(
    value.protocolVersion === protocolVersion &&
      value.hostAbi === hostAbi &&
      value.runtimeBaseline === runtimeBaseline,
    'Incompatible runtime handshake',
  );
  validId(value.generation);
  return value;
});
export const runtimeSessionSchema = codec<RuntimeSession>((input) => {
  const value = plainMessage(pb.RuntimeSessionSchema, input);
  requireFields(value, [
    'protocolVersion',
    'workerInstanceId',
    'generation',
    'buildId',
    'sources',
    'capabilities',
  ]);
  requireCondition(
    value.protocolVersion === protocolVersion,
    'Incompatible runtime protocol',
  );
  [value.workerInstanceId, value.generation, value.buildId].forEach(validId);
  const sources = value.sources.map((source) =>
    sourceInfoSchema.parse(messageJson(pb.SourceInfoSchema, source)),
  );
  requireCondition(
    sources.length > 0 &&
      new Set(sources.map((source) => source.id)).size === sources.length,
    'Sources must be nonempty and unique',
  );
  return { ...value, sources };
});
export const rpcEnvelopeSchema = codec<RpcEnvelope>((input) => {
  const value = plainMessage(pb.RpcEnvelopeSchema, input);
  requireFields(value, [
    'protocolVersion',
    'workerInstanceId',
    'generation',
    'buildId',
    'requestId',
  ]);
  requireCondition(
    value.protocolVersion === protocolVersion,
    'Incompatible runtime protocol',
  );
  [
    value.workerInstanceId,
    value.generation,
    value.buildId,
    value.requestId,
  ].forEach(validId);
  return value;
});

function validMemo(value: string | undefined): void {
  if (value === undefined) return;
  requireCondition(
    new TextEncoder().encode(value).byteLength <= SOURCE_MEMO_LIMIT,
    'Source memo exceeds its byte budget',
  );
  const parsed: unknown = JSON.parse(value);
  validateJsonDepth(parsed);
  requireCondition(
    parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed),
    'Source memo must be a JSON object',
  );
}
function validReference(value: string): void {
  requireCondition(
    value.length > 0 && value.length <= 16_384,
    'Explicit Source reference is required',
  );
}
function validManga(value: pb.Manga): void {
  validReference(value.url);
  validMemo(value.memoJson);
  requireCondition(
    value.updateStrategy === '' ||
      value.updateStrategy === 'ALWAYS_UPDATE' ||
      value.updateStrategy === 'ONLY_FETCH_ONCE',
    'Unknown manga update strategy',
  );
}
function validChapter(value: pb.Chapter): void {
  validReference(value.url);
  validMemo(value.memoJson);
  if (value.dateUpload !== '') {
    requireCondition(
      /^-?\d+$/.test(value.dateUpload),
      'Invalid chapter upload date',
    );
    const date = BigInt(value.dateUpload);
    requireCondition(
      date >= -9223372036854775808n && date <= 9223372036854775807n,
      'Chapter upload date exceeds signed int64',
    );
  }
  if (value.chapterNumber !== undefined)
    requireCondition(
      Number.isFinite(value.chapterNumber) && value.chapterNumber >= 0,
      'Invalid chapter number',
    );
}
export function validatePageList(value: pb.PageList): void {
  validId(value.pageSessionId);
  requireCondition(
    value.pages.length <= 2048 &&
      new Set(value.pages.map((page) => page.pageKey)).size ===
        value.pages.length,
    'Invalid page-session window',
  );
  value.pages.forEach((page, index) => {
    validId(page.pageKey);
    requireCondition(
      page.index === index,
      'Page index must equal its list position',
    );
  });
  jsonText(messageJson(pb.PageListSchema, value), PAGE_LIST_JSON_LIMIT);
}
export const FILTER_DEPTH_LIMIT = 8;
export const FILTER_NODE_LIMIT = 256;
export const FILTER_OPTION_LIMIT = 256;
export const FILTER_LABEL_LIMIT = 512;
export const FILTER_TEXT_LIMIT = 4096;
export const FILTER_SNAPSHOT_JSON_LIMIT = 256 * 1024;

function validFilterIndex(value: number, limit = FILTER_OPTION_LIMIT): void {
  requireCondition(
    Number.isInteger(value) && value >= 0 && value < limit,
    'Filter index exceeds its range',
  );
}
function validFilterSortState(
  value: pb.FilterSortState,
  options = FILTER_OPTION_LIMIT,
): void {
  if (value.selection !== undefined)
    validFilterIndex(value.selection.index, options);
}
function validFilterOptions(values: string[]): void {
  requireCondition(
    values.length > 0 &&
      values.length <= FILTER_OPTION_LIMIT &&
      values.every((value) => value.length <= FILTER_LABEL_LIMIT),
    'Filter options exceed their count or label budget',
  );
}
export function validateFilterSnapshot(value: pb.FilterSnapshot): void {
  validId(value.snapshotId);
  let count = 0;
  function visit(nodes: pb.FilterNode[], depth: number): void {
    requireCondition(
      depth <= FILTER_DEPTH_LIMIT,
      'Filter tree exceeds its depth budget',
    );
    for (const node of nodes) {
      requireCondition(
        ++count <= FILTER_NODE_LIMIT,
        'Filter tree exceeds its node budget',
      );
      requireCondition(
        node.name.length <= FILTER_LABEL_LIMIT,
        'Filter label exceeds its budget',
      );
      switch (node.kind.case) {
        case 'header':
        case 'separator':
        case 'checkBox':
          break;
        case 'text':
          requireCondition(
            node.kind.value.state.length <= FILTER_TEXT_LIMIT,
            'Filter text exceeds its budget',
          );
          break;
        case 'triState':
          validFilterIndex(node.kind.value.state, 3);
          break;
        case 'select':
          validFilterOptions(node.kind.value.options);
          validFilterIndex(
            node.kind.value.state,
            node.kind.value.options.length,
          );
          break;
        case 'sort':
          validFilterOptions(node.kind.value.options);
          requireFields(node.kind.value, ['state']);
          validFilterSortState(
            node.kind.value.state,
            node.kind.value.options.length,
          );
          break;
        case 'group':
          if (node.kind.value.nodes.length)
            visit(node.kind.value.nodes, depth + 1);
          break;
        default:
          throw new Error('A filter node must select a supported kind');
      }
    }
  }
  visit(value.nodes, 1);
  jsonText(
    messageJson(pb.FilterSnapshotSchema, value),
    FILTER_SNAPSHOT_JSON_LIMIT,
  );
}
export function validateFilterSelection(value: pb.FilterSelection): void {
  validId(value.snapshotId);
  requireCondition(
    value.updates.length <= FILTER_NODE_LIMIT,
    'Filter updates exceed their count budget',
  );
  const paths = new Set<string>();
  for (const update of value.updates) {
    requireCondition(
      update.path.length > 0 && update.path.length <= FILTER_DEPTH_LIMIT,
      'Filter path exceeds its depth budget',
    );
    update.path.forEach((index) => validFilterIndex(index, FILTER_NODE_LIMIT));
    const path = JSON.stringify(update.path);
    requireCondition(!paths.has(path), 'Duplicate filter update path');
    paths.add(path);
    switch (update.state.case) {
      case 'text':
        requireCondition(
          update.state.value.length <= FILTER_TEXT_LIMIT,
          'Filter text exceeds its budget',
        );
        break;
      case 'checkBox':
        break;
      case 'triState':
        validFilterIndex(update.state.value, 3);
        break;
      case 'select':
        validFilterIndex(update.state.value);
        break;
      case 'sort':
        validFilterSortState(update.state.value);
        break;
      default:
        throw new Error('A filter update must select an editable state');
    }
  }
  jsonText(messageJson(pb.FilterSelectionSchema, value), SOURCE_ARGUMENT_LIMIT);
}
export const filterSnapshotSchema = codec((input) => {
  const value = parseMessage(
    pb.FilterSnapshotSchema,
    input,
    FILTER_SNAPSHOT_JSON_LIMIT,
  );
  validateFilterSnapshot(value);
  return value;
});
export const filterSelectionSchema = codec((input) => {
  const value = parseMessage(
    pb.FilterSelectionSchema,
    input,
    SOURCE_ARGUMENT_LIMIT,
  );
  validateFilterSelection(value);
  return value;
});

export function validateSourceCall(value: SourceCall): SourceCall {
  validId(value.requestId);
  validId(value.generation);
  validSourceId(value.sourceId);
  if (value.timeoutMs !== undefined)
    requireCondition(
      value.timeoutMs > 0 && value.timeoutMs <= 300_000,
      'Invalid Source deadline',
    );
  switch (value.request.case) {
    case 'popular':
    case 'latest':
    case 'search':
      requireCondition(
        value.request.value.page > 0 && value.request.value.page <= 2147483647,
        'Invalid Source page',
      );
      if (
        value.request.case === 'search' &&
        value.request.value.filters !== undefined
      )
        validateFilterSelection(value.request.value.filters);
      break;
    case 'getFilters':
      if (value.request.value.retainedSnapshotId !== undefined)
        validId(value.request.value.retainedSnapshotId);
      break;
    case 'details':
    case 'chapters':
      requireCondition(
        value.request.value.manga !== undefined,
        'Explicit manga is required',
      );
      validManga(value.request.value.manga);
      break;
    case 'pages':
      requireCondition(
        value.request.value.chapter !== undefined,
        'Explicit chapter is required',
      );
      validChapter(value.request.value.chapter);
      break;
    default:
      throw new Error('A Source operation must be selected');
  }
  jsonText(messageJson(pb.SourceCallSchema, value), SOURCE_ARGUMENT_LIMIT);
  return value;
}
export const sourceCallSchema = codec((input) =>
  validateSourceCall(
    parseMessage(pb.SourceCallSchema, input, SOURCE_ARGUMENT_LIMIT),
  ),
);

export function javaSourceInvocation(value: SourceCall): {
  operation: string;
  argsJson: string;
} {
  validateSourceCall(value);
  const request = value.request;
  switch (request.case) {
    case 'getFilters':
      return {
        operation: 'getFilters',
        argsJson: JSON.stringify(
          messageJson(pb.GetFiltersRequestSchema, request.value),
        ),
      };
    case 'popular':
    case 'latest':
      return {
        operation: request.case,
        argsJson: JSON.stringify(
          messageJson(pb.PageRequestSchema, request.value),
        ),
      };
    case 'search':
      return {
        operation: request.case,
        argsJson: JSON.stringify(
          messageJson(pb.SearchRequestSchema, request.value),
        ),
      };
    case 'details':
    case 'chapters':
      return {
        operation: request.case,
        argsJson: JSON.stringify(
          messageJson(pb.MangaRequestSchema, request.value),
        ),
      };
    case 'pages':
      return {
        operation: request.case,
        argsJson: JSON.stringify(
          messageJson(pb.ChapterRequestSchema, request.value),
        ),
      };
    default:
      throw new Error('A Source operation must be selected');
  }
}
export function parseJavaSourcePayload(
  call: SourceCall,
  input: unknown,
): SourcePayload {
  switch (call.request.case) {
    case 'getFilters': {
      const value = filterSnapshotSchema.parse(input);
      return { case: 'filters', value };
    }
    case 'popular':
    case 'latest':
    case 'search': {
      const value = parseMessage(pb.MangaPageSchema, input);
      value.mangas.forEach(validManga);
      return { case: 'mangaPage', value };
    }
    case 'details': {
      const value = parseMessage(pb.MangaSchema, input);
      validManga(value);
      return { case: 'manga', value };
    }
    case 'chapters': {
      const value = parseMessage(pb.ChapterListSchema, input);
      value.chapters.forEach(validChapter);
      return { case: 'chapters', value };
    }
    case 'pages': {
      const value = parseMessage(
        pb.PageListSchema,
        input,
        PAGE_LIST_JSON_LIMIT,
      );
      validatePageList(value);
      return { case: 'pageList', value };
    }
    default:
      throw new Error('A Source operation must be selected');
  }
}
export function validateSourceResult(value: SourceResult): SourceResult {
  [value.requestId, value.generation, value.buildId].forEach(validId);
  switch (value.payload.case) {
    case 'filters':
      validateFilterSnapshot(value.payload.value);
      break;
    case 'mangaPage':
      value.payload.value.mangas.forEach(validManga);
      break;
    case 'manga':
      validManga(value.payload.value);
      break;
    case 'chapters':
      value.payload.value.chapters.forEach(validChapter);
      break;
    case 'pageList':
      validatePageList(value.payload.value);
      break;
    default:
      throw new Error('A Source result must select a payload');
  }
  return value;
}
export const sourceResultSchema = codec((input) =>
  validateSourceResult(parseMessage(pb.SourceResultSchema, input)),
);
export function sourceResultFor(
  call: SourceCall,
  buildId: string,
  payload: SourcePayload,
): SourceResult {
  const expected =
    call.request.case === 'getFilters'
      ? 'filters'
      : call.request.case === 'pages'
        ? 'pageList'
        : call.request.case === 'details'
          ? 'manga'
          : call.request.case === 'chapters'
            ? 'chapters'
            : 'mangaPage';
  requireCondition(
    payload.case === expected,
    'Source result does not match its request',
  );
  return validateSourceResult(
    create(pb.SourceResultSchema, {
      requestId: call.requestId,
      generation: call.generation,
      buildId,
      payload,
    }),
  );
}
