/** Java/IndexedDB are untyped boundaries; validate values before using them. */
export interface RuntimeWorkerContext {
  origin?: string;
  plugin?: string;
  fsNamespace?: string;
}

declare global {
  var karuyomiWorkerContext: RuntimeWorkerContext | undefined;
  var karuyomiResources: Record<string, string> | undefined;
}

/** Project globals describe installed values without claiming a Worker subtype. */
export function workerScope(): typeof globalThis {
  return globalThis;
}

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw Error('Expected a bridge object');
  return value as Record<string, unknown>;
}

export function text(value: unknown): string {
  if (typeof value !== 'string') throw Error('Expected a bridge string');
  return value;
}

export function number(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value))
    throw Error('Expected a finite bridge number');
  return value;
}

export function integer(
  value: unknown,
  minimum = 0,
  maximum = Number.MAX_SAFE_INTEGER,
): number {
  const result = number(value);
  if (!Number.isSafeInteger(result) || result < minimum || result > maximum)
    throw Error('Bridge integer is outside its supported range');
  return result;
}

export function bool(value: unknown): boolean {
  if (typeof value !== 'boolean') throw Error('Expected a bridge boolean');
  return value;
}

export function optionalText(value: unknown): string | undefined {
  return value === undefined || value === null ? undefined : text(value);
}

export function decodeBase64(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

export function encodeBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 16_384)
    binary += String.fromCharCode(...bytes.subarray(index, index + 16_384));
  return btoa(binary);
}

export function errorText(error: unknown): string {
  return error instanceof Error
    ? error.name + ': ' + error.message
    : String(error);
}

export type StorageKey = [string, string];
export function storageKey(value: unknown): StorageKey {
  if (!Array.isArray(value) || value.length !== 2)
    throw Error('Invalid stored namespace key');
  return [text(value[0]), text(value[1])];
}

export function array(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw Error('Expected a stored array');
  return value as unknown[];
}

export function idbRequest<T>(request: IDBRequest<T>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
