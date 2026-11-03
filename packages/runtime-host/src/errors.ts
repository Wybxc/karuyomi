import type { RuntimeErrorCode, RuntimeErrorData } from '@karuyomi/contracts';

export class RuntimeFailure extends Error {
  readonly code: RuntimeErrorCode;
  readonly retryable: boolean;
  readonly javaClass: string | undefined;

  constructor(
    code: RuntimeErrorCode,
    message: string,
    retryable = false,
    javaClass?: string,
  ) {
    super(message);
    this.name = 'RuntimeFailure';
    this.code = code;
    this.retryable = retryable;
    this.javaClass = javaClass;
  }

  toJSON(): RuntimeErrorData {
    return {
      code: this.code,
      message: this.message,
      retryable: this.retryable,
      ...(this.javaClass === undefined ? {} : { javaClass: this.javaClass }),
    };
  }
}

export function runtimeFailure(error: unknown): RuntimeFailure {
  if (error instanceof RuntimeFailure) return error;
  return new RuntimeFailure(
    'source_error',
    error instanceof Error ? error.message : String(error),
  );
}
