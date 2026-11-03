library;

import 'dart:async';
import 'package:reader_core/reader_core.dart';
import 'src/generated.dart';

export 'src/generated.dart';
part 'src/transport_runtime.dart';
part 'src/chapter_provider.dart';

/// Web uses JS interop; native uses a managed WebView control page.
abstract interface class SourceRuntime {
  Stream<RuntimeEvent> get events;
  Future<RuntimeSession> open(BuildDescriptor build);
  Future<SourceResult> invoke(SourceRequest request);
  Future<void> cancel(String requestId);
  Future<ImageResource> acquireImage(ImageAcquireRequest request);
  Future<void> cancelImage(ImageCancelRequest request);
  Future<void> releaseImage(ImageReleaseRequest request);
  Future<void> closePageSession(PageSessionRef session);
  Future<void> dispose();
}

/// Image controls stay small; bytes remain in the platform resource channel.
final class ImageAcquireRequest {
  const ImageAcquireRequest({
    required this.requestId,
    required this.sourceId,
    required this.pageSessionId,
    required this.pageKey,
    required this.generation,
    this.timeout = const Duration(seconds: 30),
  });
  final String requestId;
  final String sourceId;
  final String pageSessionId;
  final String pageKey;
  final String generation;
  final Duration timeout;
}

final class ImageCancelRequest {
  const ImageCancelRequest({required this.requestId, required this.generation});
  final String requestId;
  final String generation;
}

final class ImageReleaseRequest {
  const ImageReleaseRequest({
    required this.resourceId,
    required this.generation,
  });
  final String resourceId;
  final String generation;
}

final class PageSessionRef {
  const PageSessionRef({required this.pageSessionId, required this.generation});
  final String pageSessionId;
  final String generation;
}

final class BuildDescriptor {
  const BuildDescriptor({
    required this.buildId,
    required this.manifestUri,
    required this.sha256,
    this.identity = '',
    this.packageId,
  });

  final String buildId;
  final Uri manifestUri;
  final String sha256;

  /// Confirmed Access subject. Never a JWT or service token.
  final String identity;
  final String? packageId;
}

final class RuntimeSession {
  const RuntimeSession({
    required this.generation,
    required this.buildId,
    this.workerInstanceId = '',
    this.sources = const [],
    this.capabilities = const [],
  });
  final String generation;
  final String buildId;
  final String workerInstanceId;
  final List<SourceInfo> sources;
  final List<String> capabilities;
}

final class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.lang,
    this.supportsLatest,
    this.baseUrl,
  });
  final String id;
  final String name;
  final String lang;
  final bool? supportsLatest;
  final String? baseUrl;
}

final class SourceRequest {
  const SourceRequest({
    required this.requestId,
    required this.generation,
    required this.packageId,
    required this.sourceId,
    required this.operation,
    required this.arguments,
    this.timeout = const Duration(seconds: 30),
  });

  final String requestId;
  final String generation;
  final String packageId;
  // External 64 bit identifiers stay strings across Dart/JS.
  final String sourceId;
  final String operation;
  final Map<String, Object?> arguments;
  final Duration timeout;
}

final class SourceResult {
  const SourceResult({
    required this.requestId,
    required this.generation,
    required this.data,
  });
  final String requestId;
  final String generation;
  final Map<String, Object?> data;
}

enum RuntimeErrorCode {
  cancelled,
  timeout,
  accessRequired,
  sourceError,
  unsupportedCapability,
  runtimeLost,
  accessDenied,
  protocolError,
  integrityError,
  limitExceeded,
}

final class RuntimeEvent {
  const RuntimeEvent({
    required this.generation,
    required this.code,
    this.message,
  });
  final String generation;
  final RuntimeErrorCode code;
  final String? message;
}

/// Shared version check; readiness also requires package, files and Source init.
bool isCompatibleHost(Map<String, Object?> hello) =>
    hello['protocolVersion'] == protocolVersion && hello['hostAbi'] == hostAbi;
