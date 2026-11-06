import { z } from 'zod';

const identity = z.string().min(1).max(200);
const count = z.number().int().nonnegative();

export const httpDiagnosticSchema = z
  .object({
    component: z.literal('http'),
    requestId: identity,
    generation: identity,
    handle: identity,
    stage: z.enum([
      'finish-fetch',
      'response',
      'meta',
      'first-read',
      'first-read-result',
      'eof',
      'error',
      'close',
    ]),
    phase: z.enum(['upload', 'opening', 'response', 'eof']),
    elapsedMs: count,
    readCount: count,
    bytesRead: count,
  })
  .strict();

export const teaVMDiagnosticOperationSchema = z.enum([
  'host',
  'popular',
  'latest',
  'search',
  'details',
  'chapters',
  'pages',
  'getFilters',
  'getPreferences',
  'editPreference',
  'cache-control',
  'cache-get',
  'cache-begin',
  'cache-commit',
  'cache-update',
  'cache-remove',
  'cache-abort',
  'cache-reader-close',
  'cache-close',
  'cache-delete',
  'cache-clear',
  'cache-urls',
  'cache-initialize',
  'cache-flush',
  'cache-size',
  'cache-read',
  'cache-write',
]);
export const teaVMDiagnosticPhaseSchema = z.enum([
  'begin',
  'settled',
  'resolved',
  'rejected',
]);
export const teaVMDiagnosticSchema = z
  .object({
    component: z.literal('teavm'),
    requestId: identity.optional(),
    generation: identity.optional(),
    operation: teaVMDiagnosticOperationSchema,
    phase: teaVMDiagnosticPhaseSchema,
    sequence: count.optional(),
    byteLength: count.optional(),
    eof: z.boolean().optional(),
  })
  .strict();

export const javaCacheStageSchema = z.enum([
  'cache-callback-before',
  'cache-callback-after',
  'cache-callback-error',
  'cache-command-return',
  'cache-command-text',
  'cache-command-error',
  'cache-get-start',
  'cache-get-command',
  'cache-get-error',
  'cache-entry',
  'cache-miss',
  'cache-metadata',
  'cache-headers',
  'cache-vary',
  'cache-body',
  'cache-entry-tag',
  'cache-response',
  'cache-return',
  'cache-finally',
]);
export const javaCacheDiagnosticSchema = z
  .object({
    component: z.literal('java-cache'),
    generation: identity,
    stage: javaCacheStageSchema,
  })
  .strict();

export const runtimeDiagnosticSchema = z.discriminatedUnion('component', [
  httpDiagnosticSchema,
  teaVMDiagnosticSchema,
  javaCacheDiagnosticSchema,
]);
export type RuntimeDiagnostic = z.infer<typeof runtimeDiagnosticSchema>;
export type HttpDiagnosticStage = z.infer<typeof httpDiagnosticSchema>['stage'];
export type RuntimeDiagnosticSink = (diagnostic: RuntimeDiagnostic) => void;

function consoleDiagnostic(diagnostic: RuntimeDiagnostic): void {
  const { component, ...detail } = diagnostic;
  if (component === 'http')
    console.info('Karuyomi runtime HTTP', JSON.stringify(detail));
  else console.info('Karuyomi runtime stage', JSON.stringify(diagnostic));
}

// Each Worker has its own module instance; installing a sink affects only that realm.
let sink: RuntimeDiagnosticSink = consoleDiagnostic;
export function setRuntimeDiagnosticSink(
  next: RuntimeDiagnosticSink | undefined,
): void {
  sink = next ?? consoleDiagnostic;
}

export function reportRuntimeDiagnostic(diagnostic: RuntimeDiagnostic): void {
  if (import.meta.env.VITE_KARUYOMI_RUNTIME_DIAGNOSTICS !== '1') return;
  const parsed = runtimeDiagnosticSchema.safeParse(diagnostic);
  if (parsed.success) {
    try {
      sink(parsed.data);
    } catch {
      // Observation must not change the Source operation's outcome.
    }
  }
}
