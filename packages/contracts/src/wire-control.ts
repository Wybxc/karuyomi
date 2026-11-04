import * as pb from '@karuyomi/protocol';
import {
  codec,
  messageJson,
  parseMessage,
  requireCondition,
  SOURCE_ARGUMENT_LIMIT,
} from './codec.ts';
import {
  buildManifestSchema,
  staticManifestPathSchema,
  validId,
} from './static-control.ts';
import {
  rpcEnvelopeSchema,
  runtimeErrorData,
  runtimeHelloSchema,
  runtimeSessionSchema,
  validateSourceCall,
  validateSourceResult,
} from './runtime-control.ts';
import {
  acquireImageSchema,
  cancelImageSchema,
  closePageSessionSchema,
  imageResourceSchema,
  encodedImageSchema,
  processedImageSchema,
  releaseImageSchema,
  closedSchema,
  releasedSchema,
  completedSchema,
} from './image-control.ts';

export type ControlRequest = pb.ControlRequest;
export type ControlResponse = pb.ControlResponse;
export type WorkerCommand = pb.WorkerCommand & { envelope: pb.RpcEnvelope };
export type WorkerResponse = pb.WorkerResponse & { envelope: pb.RpcEnvelope };

function envelope(value: pb.RpcEnvelope | undefined): pb.RpcEnvelope {
  requireCondition(value !== undefined, 'Worker envelope is required');
  rpcEnvelopeSchema.parse(messageJson(pb.RpcEnvelopeSchema, value));
  return value;
}
export function validateWorkerCommand(value: pb.WorkerCommand): WorkerCommand {
  const rpc = envelope(value.envelope);
  switch (value.command.case) {
    case 'open':
      requireCondition(
        value.command.value.manifest !== undefined,
        'Worker manifest is required',
      );
      buildManifestSchema.parse(
        messageJson(pb.BuildManifestSchema, value.command.value.manifest),
      );
      requireCondition(
        value.command.value.manifest.buildId === rpc.buildId &&
          value.command.value.userAgent.length <= 1000,
        'Invalid Worker open identity',
      );
      break;
    case 'invoke':
      validateSourceCall(value.command.value);
      requireCondition(
        value.command.value.requestId === rpc.requestId &&
          value.command.value.generation === rpc.generation,
        'Source call does not match its envelope',
      );
      break;
    case 'acquireImage': {
      const request = value.command.value.request;
      requireCondition(request !== undefined, 'Image request is required');
      acquireImageSchema.parse(messageJson(pb.AcquireImageSchema, request));
      requireCondition(
        request.requestId === rpc.requestId &&
          request.generation === rpc.generation,
        'Image call does not match its envelope',
      );
      validId(value.command.value.resourceId);
      break;
    }
    case 'closePageSession':
      closePageSessionSchema.parse(
        messageJson(pb.ClosePageSessionSchema, value.command.value),
      );
      requireCondition(
        value.command.value.generation === rpc.generation,
        'Page session does not match its envelope',
      );
      break;
    case 'shutdown':
      break;
    default:
      throw new Error('A Worker command must be selected');
  }
  return { ...value, envelope: rpc };
}
export function validateWorkerResponse(
  value: pb.WorkerResponse,
): WorkerResponse {
  const rpc = envelope(value.envelope);
  switch (value.result.case) {
    case 'session': {
      const session = value.result.value;
      runtimeSessionSchema.parse(messageJson(pb.RuntimeSessionSchema, session));
      requireCondition(
        session.generation === rpc.generation &&
          session.workerInstanceId === rpc.workerInstanceId &&
          session.buildId === rpc.buildId,
        'Session does not match its envelope',
      );
      break;
    }
    case 'source': {
      const source = validateSourceResult(value.result.value);
      requireCondition(
        source.requestId === rpc.requestId &&
          source.generation === rpc.generation &&
          source.buildId === rpc.buildId,
        'Source result does not match its envelope',
      );
      break;
    }
    case 'image':
      processedImageSchema.parse(
        messageJson(pb.ProcessedImageSchema, value.result.value),
      );
      requireCondition(
        value.result.value.generation === rpc.generation,
        'Image result does not match its envelope',
      );
      break;
    case 'encodedImage':
      encodedImageSchema.parse(
        messageJson(pb.EncodedImageSchema, value.result.value),
      );
      requireCondition(
        value.result.value.generation === rpc.generation,
        'Encoded image result does not match its envelope',
      );
      break;
    case 'closed':
      closedSchema.parse(messageJson(pb.ClosedSchema, value.result.value));
      break;
    case 'error':
      runtimeErrorData(value.result.value);
      break;
    default:
      throw new Error('A Worker result must be selected');
  }
  return { ...value, envelope: rpc };
}
export const workerCommandSchema = codec((input) =>
  validateWorkerCommand(parseMessage(pb.WorkerCommandSchema, input)),
);
export const workerResponseSchema = codec((input) =>
  validateWorkerResponse(parseMessage(pb.WorkerResponseSchema, input)),
);
export const encodeWorkerCommand = (value: pb.WorkerCommand) =>
  messageJson(pb.WorkerCommandSchema, validateWorkerCommand(value));
export const encodeWorkerResponse = (value: pb.WorkerResponse) =>
  messageJson(pb.WorkerResponseSchema, validateWorkerResponse(value));

export function validateControlRequest(value: ControlRequest): ControlRequest {
  validId(value.requestId);
  switch (value.command.case) {
    case 'ready':
    case 'rebuild':
    case 'dispose':
      break;
    case 'open':
      staticManifestPathSchema.parse(value.command.value.manifestPath);
      requireCondition(
        value.command.value.identity.length > 0 &&
          value.command.value.identity.length <= 1000,
        'A confirmed identity is required',
      );
      break;
    case 'invoke':
      validateSourceCall(value.command.value);
      break;
    case 'cancel':
      validId(value.command.value.requestId);
      validId(value.command.value.generation);
      break;
    case 'acquireImage':
    case 'acquireEncodedImage':
      acquireImageSchema.parse(
        messageJson(pb.AcquireImageSchema, value.command.value),
      );
      break;
    case 'cancelImage':
      cancelImageSchema.parse(
        messageJson(pb.CancelImageSchema, value.command.value),
      );
      break;
    case 'releaseImage':
      releaseImageSchema.parse(
        messageJson(pb.ReleaseImageSchema, value.command.value),
      );
      break;
    case 'closePageSession':
      closePageSessionSchema.parse(
        messageJson(pb.ClosePageSessionSchema, value.command.value),
      );
      break;
    case 'fetchApi':
      requireCondition(
        value.command.value.path.length > 0,
        'API path is required',
      );
      break;
    default:
      throw new Error('A control command must be selected');
  }
  return value;
}
export function validateControlResponse(
  value: ControlResponse,
): ControlResponse {
  validId(value.requestId);
  switch (value.result.case) {
    case 'hello':
      runtimeHelloSchema.parse(
        messageJson(pb.RuntimeHelloSchema, value.result.value),
      );
      break;
    case 'session':
      runtimeSessionSchema.parse(
        messageJson(pb.RuntimeSessionSchema, value.result.value),
      );
      break;
    case 'source':
      validateSourceResult(value.result.value);
      break;
    case 'image':
      imageResourceSchema.parse(
        messageJson(pb.ImageResourceSchema, value.result.value),
      );
      break;
    case 'encodedImage':
      encodedImageSchema.parse(
        messageJson(pb.EncodedImageSchema, value.result.value),
      );
      break;
    case 'released':
      releasedSchema.parse(messageJson(pb.ReleasedSchema, value.result.value));
      break;
    case 'closed':
      closedSchema.parse(messageJson(pb.ClosedSchema, value.result.value));
      break;
    case 'completed':
      completedSchema.parse(
        messageJson(pb.CompletedSchema, value.result.value),
      );
      break;
    case 'api':
      requireCondition(
        value.result.value.status <= 599 &&
          (value.result.value.status >= 100 ||
            (value.result.value.status === 0 && value.result.value.redirected)),
        'Invalid API response status',
      );
      break;
    case 'error':
      runtimeErrorData(value.result.value);
      break;
    default:
      throw new Error('A control response must select a result');
  }
  return value;
}
export const parseControlRequest = (input: unknown) =>
  validateControlRequest(
    parseMessage(pb.ControlRequestSchema, input, SOURCE_ARGUMENT_LIMIT),
  );
export const parseControlResponse = (input: unknown) =>
  validateControlResponse(parseMessage(pb.ControlResponseSchema, input));
export const encodeControlRequest = (value: ControlRequest) =>
  messageJson(pb.ControlRequestSchema, validateControlRequest(value));
export const encodeControlResponse = (value: ControlResponse) =>
  messageJson(pb.ControlResponseSchema, validateControlResponse(value));
