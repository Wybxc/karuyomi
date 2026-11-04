/** Client image processing failures never become Source control messages. */
export class ImageCodecFailure extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = 'ImageCodecFailure';
  }
}
export function imageCodecFailure(error: unknown): ImageCodecFailure {
  return error instanceof ImageCodecFailure
    ? error
    : new ImageCodecFailure(
        'decode_error',
        error instanceof Error ? error.message : String(error),
      );
}
