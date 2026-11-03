import type {
  Artifact,
  BuildManifest,
  SourceInfo,
} from '../../packages/contracts/src/index.ts';

export interface ValidationFailure {
  code: string;
  message: string;
}

export interface ValidationReport {
  schemaVersion: 1;
  kind: 'karuyomi-extension-build-validation';
  valid: boolean;
  runtimeReady: boolean;
  onlineCompatibility: 'not_tested';
  stages: Record<
    'artifactIntegrity' | 'workerInit' | 'browserLoad',
    'not_run' | 'passed' | 'failed'
  >;
  capabilities: string[];
  buildId?: string;
  packageName?: string;
  protocolVersion?: number;
  hostAbi?: string;
  runtimeBaseline?: string;
  bundleSha256?: string;
  manifestSha256?: string;
  sourceIds?: string[];
  artifactCount?: number;
  bundleArtifactCount?: number;
  sharedMaterialCount?: number;
  artifactBytes?: number;
  failure?: ValidationFailure;
  scope?: string;
  runtimeHostSha256?: Record<string, string>;
  browser?: { userAgent: string; indexedDb: boolean; networkAttempts: number };
  sources?: SourceInfo[];
}

export interface VerifiedPayload extends Artifact {
  bytes: Buffer;
  transportContentType: string;
  transportSize: number;
}

export interface VerifiedInputs {
  report: ValidationReport;
  manifest: BuildManifest;
  manifestBytes: Buffer;
  payloads: Map<string, VerifiedPayload>;
}

export type IntegrityResult =
  | VerifiedInputs
  | {
      report: ValidationReport;
      manifest?: undefined;
      manifestBytes?: undefined;
      payloads?: undefined;
    };

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function isSourceInfo(value: unknown): value is SourceInfo {
  return (
    isRecord(value) &&
    typeof value.id === 'string' &&
    /^-?\d+$/.test(value.id) &&
    typeof value.name === 'string' &&
    typeof value.lang === 'string' &&
    (value.supportsLatest === undefined ||
      typeof value.supportsLatest === 'boolean') &&
    (value.baseUrl === undefined || typeof value.baseUrl === 'string')
  );
}
