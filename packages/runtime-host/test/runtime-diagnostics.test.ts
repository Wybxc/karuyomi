import { afterEach, expect, test, vi } from 'vitest';
import {
  reportRuntimeDiagnostic,
  runtimeDiagnosticSchema,
  setRuntimeDiagnosticSink,
  type RuntimeDiagnostic,
  type RuntimeDiagnosticSink,
} from '../src/runtime-diagnostics.js';

const httpDiagnostic: RuntimeDiagnostic = {
  component: 'http',
  requestId: 'operation-1',
  generation: 'generation-1',
  handle: 'http-handle',
  stage: 'eof',
  phase: 'eof',
  elapsedMs: 12,
  readCount: 2,
  bytesRead: 65537,
};
const teaVMDiagnostic: RuntimeDiagnostic = {
  component: 'teavm',
  requestId: 'operation-1',
  generation: 'generation-1',
  operation: 'cache-read',
  phase: 'resolved',
  sequence: 3,
  byteLength: 0,
  eof: true,
};

afterEach(() => {
  setRuntimeDiagnosticSink(undefined);
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

test('diagnostics are disabled by default even when a sink is installed', () => {
  vi.stubEnv('VITE_KARUYOMI_RUNTIME_DIAGNOSTICS', undefined);
  const sink = vi.fn<RuntimeDiagnosticSink>();
  setRuntimeDiagnosticSink(sink);
  reportRuntimeDiagnostic(httpDiagnostic);
  expect(sink).not.toHaveBeenCalled();
});

test.each([httpDiagnostic, teaVMDiagnostic])(
  'enabled $component diagnostics deliver the known payload to the current sink',
  (diagnostic) => {
    vi.stubEnv('VITE_KARUYOMI_RUNTIME_DIAGNOSTICS', '1');
    const sink = vi.fn<RuntimeDiagnosticSink>();
    setRuntimeDiagnosticSink(sink);
    reportRuntimeDiagnostic(diagnostic);
    expect(sink).toHaveBeenCalledExactlyOnceWith(diagnostic);
  },
);

test('diagnostics reject an additional URL field before invoking the sink', () => {
  vi.stubEnv('VITE_KARUYOMI_RUNTIME_DIAGNOSTICS', '1');
  const sink = vi.fn<RuntimeDiagnosticSink>();
  setRuntimeDiagnosticSink(sink);
  for (const diagnostic of [httpDiagnostic, teaVMDiagnostic]) {
    const withUrl = { ...diagnostic, url: 'https://private.example/source' };
    expect(runtimeDiagnosticSchema.safeParse(withUrl).success).toBe(false);
    reportRuntimeDiagnostic(withUrl);
  }
  expect(sink).not.toHaveBeenCalled();
});

test.each([
  { ...httpDiagnostic, stage: 'unknown-stage' },
  { ...teaVMDiagnostic, phase: 'unknown-phase' },
  { ...teaVMDiagnostic, operation: 'unknown-operation' },
])(
  'diagnostic parsing rejects unknown stage, phase or operation values',
  (input) => {
    expect(runtimeDiagnosticSchema.safeParse(input).success).toBe(false);
  },
);

test('a failed diagnostic sink cannot change the reporting caller outcome', () => {
  vi.stubEnv('VITE_KARUYOMI_RUNTIME_DIAGNOSTICS', '1');
  const sink = vi.fn<RuntimeDiagnosticSink>(() => {
    throw Error('Diagnostic delivery failed');
  });
  setRuntimeDiagnosticSink(sink);
  expect(() => reportRuntimeDiagnostic(httpDiagnostic)).not.toThrow();
  expect(sink).toHaveBeenCalledExactlyOnceWith(httpDiagnostic);
});
