import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';

const sourceId = '9223372036854775806';

final class FakeTransport implements RuntimeTransport {
  final calls = <wire.ControlRequest>[];
  Future<wire.ControlResponse> Function(wire.ControlRequest)? handler;
  Object? Function(wire.ControlRequest, Map<String, Object?>)? corrupt;

  wire.ControlResponse respond(wire.ControlRequest request) {
    final response = wire.ControlResponse(requestId: request.requestId);
    switch (request.whichCommand()) {
      case wire.ControlRequest_Command.ready:
        response.hello = wire.RuntimeHello(
          protocolVersion: protocolVersion,
          hostAbi: hostAbi,
          runtimeBaseline: runtimeBaseline,
        );
      case wire.ControlRequest_Command.open:
        response.session = wire.RuntimeSession(
          protocolVersion: protocolVersion,
          buildId: 'build-1',
          workerInstanceId: 'worker-1',
          generation: 'generation-1',
          sources: [wire.SourceInfo(id: sourceId, name: 'Source', lang: 'en')],
          capabilities: ['source-rpc'],
        );
      case wire.ControlRequest_Command.invoke:
        response.source = wire.SourceResult(
          requestId: request.invoke.requestId,
          generation: 'generation-1',
          buildId: 'build-1',
          mangaPage: wire.MangaPage(hasNextPage: false),
        );
      case wire.ControlRequest_Command.acquireImage:
        response.image = wire.ImageResource(
          resourceId: 'resource-1',
          generation: 'generation-1',
          mimeType: 'image/png',
          byteLength: 1234,
          width: 600,
          height: 900,
          url: 'blob:https://reader.example/image-1',
        );
      case wire.ControlRequest_Command.acquireEncodedImage:
        response.encodedImage = wire.EncodedImage(
          resourceId: 'encoded-1',
          generation: 'generation-1',
          mimeType: 'image/png',
          byteLength: 1234,
          rawWidth: 1080,
          rawHeight: 20000,
          orientation: 1,
        );
      case wire.ControlRequest_Command.cancelImage ||
          wire.ControlRequest_Command.releaseImage:
        response.released = wire.Released(released: true);
      case wire.ControlRequest_Command.closePageSession:
        response.closed = wire.Closed(closed: true);
      default:
        response.completed = wire.Completed(completed: true);
    }
    return response;
  }

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    calls.add(request.deepCopy()..freeze());
    final response = handler == null
        ? respond(request)
        : await handler!(request);
    final encoded = wire.encodeProtoJson(
      response,
      maxBytes: wire.controlJsonLimit,
    );
    return corrupt?.call(request, encoded) ?? encoded;
  }
}

final class ManagedTransport
    implements RuntimeTransport, ManagedImageTransport {
  ManagedTransport(this.delegate);
  final FakeTransport delegate;
  Uri? owned;
  @override
  Future<Object?> control(Map<String, Object?> request) =>
      delegate.control(request);
  @override
  bool ownsImageLocation(String resourceId, String generation, Uri location) =>
      resourceId == 'resource-1' &&
      generation == 'generation-1' &&
      location == owned;
}

BuildDescriptor build({String identity = 'owner', String? path}) =>
    BuildDescriptor(
      buildId: 'build-1',
      manifestUri: Uri.parse(
        path ?? '/extensions/builds/build-1/manifest.json',
      ),
      sha256: 'a' * 64,
      identity: identity,
      packageId: 'package-1',
    );
SourceRequest request({
  String generation = 'generation-1',
  String id = sourceId,
}) => SourceRequest(
  packageId: 'package-1',
  call: wire.SourceCall(
    requestId: 'request-1',
    generation: generation,
    sourceId: id,
    popular: wire.PageRequest(page: 2),
    timeoutMs: 30000,
  ),
);
TypeMatcher<RuntimeException> failure(RuntimeErrorCode code) =>
    isA<RuntimeException>().having((error) => error.code, 'code', code);
ImageAcquireRequest imageRequest({
  String generation = 'generation-1',
  String id = 'image-1',
  String source = sourceId,
  String session = 'pages-1',
  String page = 'p-0',
  Duration timeout = const Duration(seconds: 30),
}) => ImageAcquireRequest(
  requestId: id,
  sourceId: source,
  pageSessionId: session,
  pageKey: page,
  generation: generation,
  timeout: timeout,
);
