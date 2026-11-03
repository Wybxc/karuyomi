// WebCrypto provider for the bounded JCA API in java/compat. No keys are logged.
import {
  decodeBase64,
  encodeBase64,
  errorText,
  integer,
  object,
  text,
  workerScope,
} from './bridge-common.js';

type CryptoRequest =
  | { algorithm: 'HMAC'; key: string; body: string }
  | {
      algorithm: 'AES-CBC';
      operation: 'encrypt' | 'decrypt';
      key: string;
      body: string;
      iv: string;
    }
  | {
      algorithm: 'AES-GCM';
      operation: 'encrypt' | 'decrypt';
      key: string;
      body: string;
      iv: string;
      tagLength: number;
      aad: string;
    };
export type CryptoResult = { body: string } | { error: string };

function parseRequest(input: unknown): CryptoRequest {
  const data = object(input);
  const key = text(data.key),
    body = text(data.body);
  if (data.algorithm === 'HMAC')
    return { algorithm: data.algorithm, key, body };
  if (
    (data.algorithm !== 'AES-CBC' && data.algorithm !== 'AES-GCM') ||
    (data.operation !== 'encrypt' && data.operation !== 'decrypt')
  )
    throw Error('Unsupported crypto operation');
  const operation: 'encrypt' | 'decrypt' = data.operation;
  const common = { operation, key, body, iv: text(data.iv) };
  return data.algorithm === 'AES-CBC'
    ? { ...common, algorithm: data.algorithm }
    : {
        ...common,
        algorithm: data.algorithm,
        tagLength: integer(data.tagLength, 32, 128),
        aad: text(data.aad),
      };
}

declare global {
  var teaCrypto: typeof cryptoBridge | undefined;
}

const scope = workerScope();
const cryptoBridge = async (input: unknown): Promise<CryptoResult> => {
  try {
    const request = parseRequest(input);
    const keyBytes = decodeBase64(request.key),
      bytes = decodeBase64(request.body);
    let result: ArrayBuffer;
    if (request.algorithm === 'HMAC') {
      const key = await crypto.subtle.importKey(
        'raw',
        keyBytes,
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
      );
      result = await crypto.subtle.sign('HMAC', key, bytes);
    } else {
      const key = await crypto.subtle.importKey(
        'raw',
        keyBytes,
        request.algorithm,
        false,
        [request.operation],
      );
      const algorithm: AesCbcParams | AesGcmParams =
        request.algorithm === 'AES-CBC'
          ? { name: request.algorithm, iv: decodeBase64(request.iv) }
          : {
              name: request.algorithm,
              iv: decodeBase64(request.iv),
              tagLength: request.tagLength,
              additionalData: decodeBase64(request.aad),
            };
      result = await crypto.subtle[request.operation](algorithm, key, bytes);
    }
    return { body: encodeBase64(new Uint8Array(result)) };
  } catch (error) {
    return { error: errorText(error) };
  }
};
scope.teaCrypto = cryptoBridge;
