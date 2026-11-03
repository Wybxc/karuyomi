import {
  fromJsonString,
  toJson,
  type DescMessage,
  type MessageJsonType,
  type MessageShape,
  type Message,
} from '@bufbuild/protobuf';

export const CONTROL_JSON_LIMIT = 8 * 1024 * 1024;
export const SOURCE_ARGUMENT_LIMIT = 128 * 1024;
export const SOURCE_MEMO_LIMIT = 64 * 1024;
export const PAGE_LIST_JSON_LIMIT = 2 * 1024 * 1024;
export const CONTROL_JSON_DEPTH_LIMIT = 64;

export interface Codec<T> {
  parse(input: unknown): T;
  safeParse(
    input: unknown,
  ): { success: true; data: T } | { success: false; error: Error };
}

export function codec<T>(parse: (input: unknown) => T): Codec<T> {
  return {
    parse,
    safeParse(input) {
      try {
        return { success: true, data: parse(input) };
      } catch (error) {
        return {
          success: false,
          error: error instanceof Error ? error : new Error(String(error)),
        };
      }
    },
  };
}

export function jsonText(input: unknown, limit = CONTROL_JSON_LIMIT): string {
  validateJsonDepth(input);
  const text = JSON.stringify(input);
  if (text === undefined || new TextEncoder().encode(text).byteLength > limit)
    throw new Error('Control JSON exceeds its size budget');
  return text;
}

/** Bound nesting before entering the generated recursive JSON decoder. */
export function validateJsonDepth(input: unknown): void {
  const pending = [{ value: input, depth: 0 }];
  const seen = new Map<object, number>();
  while (pending.length) {
    const entry = pending.pop();
    if (!entry || entry.value === null || typeof entry.value !== 'object')
      continue;
    if (entry.depth > CONTROL_JSON_DEPTH_LIMIT)
      throw new Error('Control JSON exceeds its nesting budget');
    if ((seen.get(entry.value) ?? -1) >= entry.depth) continue;
    seen.set(entry.value, entry.depth);
    for (const value of Object.values(entry.value))
      pending.push({ value, depth: entry.depth + 1 });
  }
}

/** Generated ProtoJSON decoding owns structure, scalar types, enums and oneofs. */
export function parseMessage<D extends DescMessage>(
  schema: D,
  input: unknown,
  limit = CONTROL_JSON_LIMIT,
): MessageShape<D> {
  return fromJsonString(schema, jsonText(input, limit), {
    ignoreUnknownFields: false,
  });
}

export function messageJson<D extends DescMessage>(
  schema: D,
  message: MessageShape<D>,
): MessageJsonType<D> {
  return toJson<D, undefined>(schema, message);
}

export type PlainMessage<T extends Message> = Omit<T, '$typeName' | '$unknown'>;

export function plain<T extends Message>(message: T): PlainMessage<T> {
  const { $typeName, $unknown, ...value } = message;
  return value;
}

export function plainMessage<D extends DescMessage>(
  schema: D,
  input: unknown,
): PlainMessage<MessageShape<D>> {
  return plain(parseMessage(schema, input));
}

/** A sound presence refinement for fields emitted by the generated codec. */
export function requireFields<T extends object, K extends keyof T>(
  value: T,
  keys: readonly K[],
): asserts value is T & { [P in K]-?: NonNullable<T[P]> } {
  for (const key of keys)
    if (value[key] === undefined || value[key] === null)
      throw new Error(`Missing control field: ${String(key)}`);
}

export function requireCondition(
  condition: unknown,
  message: string,
): asserts condition {
  if (!condition) throw new Error(message);
}
