library;

import 'dart:async';
import 'dart:convert';
import 'package:reader_core/reader_core.dart';
import 'control_protocol.dart' as wire;
import 'src/generated.dart';

export 'src/generated.dart';
part 'src/transport_runtime.dart';
part 'src/chapter_provider.dart';
part 'src/extension_management.dart';

/// Web uses JS interop; native uses a managed WebView control page.
abstract interface class SourceRuntime {
  Stream<RuntimeEvent> get events;
  Future<RuntimeSession> open(BuildDescriptor build);
  Future<wire.PreparedBuild> prepareBuild({
    required String preparationId,
    required wire.CatalogReference catalog,
    required wire.ExtensionBuildDescriptor build,
  });
  Future<void> cancelPreparation(String preparationId);
  Future<wire.ExtensionCacheState> extensionCache();
  Future<void> forgetExtensionArtifact(String sha256);
  Future<void> closeBuild({
    required String buildId,
    required String generation,
  });
  Future<SourceResult> invoke(SourceRequest request);
  Future<void> cancel(String requestId);
  Future<ImageResource> acquireImage(ImageAcquireRequest request);

  Future<void> cancelImage(ImageCancelRequest request);
  Future<void> releaseImage(ImageReleaseRequest request);
  Future<void> closePageSession(PageSessionRef session);
  Future<void> rebuildHost();
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
    required this.catalog,
    required this.manifestUri,
    required this.sha256,
    this.identity = '',
    this.packageId,
    this.preferenceBootstrap,
  });

  final String buildId;
  final wire.CatalogReference catalog;
  final Uri manifestUri;
  final String sha256;

  /// Confirmed Access subject. Never a JWT or service token.
  final String identity;
  final String? packageId;

  /// Confirmed account values plus current client session values, injected before Source construction.
  final wire.PreferenceBootstrap? preferenceBootstrap;
}

typedef RuntimeSession = wire.RuntimeSession;
typedef SourceInfo = wire.SourceInfo;
typedef SourceResult = wire.SourceResult;

final class SourceRequest {
  const SourceRequest({required this.packageId, required this.call});

  final String packageId;
  final wire.SourceCall call;
}

enum RuntimeErrorCode {
  storageBusy,
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
    this.containerWide = false,
  });
  final bool containerWide;
  final String generation;
  final RuntimeErrorCode code;
  final String? message;
}

/// Shared version check; readiness also requires package, files and Source init.
bool isCompatibleHost(wire.RuntimeHello hello) =>
    hello.protocolVersion == protocolVersion && hello.hostAbi == hostAbi;
