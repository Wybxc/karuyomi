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
final class const ImageAcquireRequest({
  required final String requestId,
  required final String sourceId,
  required final String pageSessionId,
  required final String pageKey,
  required final String generation,
  final Duration timeout = const Duration(seconds: 30),
});

final class const ImageCancelRequest({
  required final String requestId,
  required final String generation,
});

final class const ImageReleaseRequest({
  required final String resourceId,
  required final String generation,
});

final class const PageSessionRef({
  required final String pageSessionId,
  required final String generation,
});

final class const BuildDescriptor({
  required final String buildId,
  required final wire.CatalogReference catalog,
  required final Uri manifestUri,
  required final String sha256,

  /// Confirmed Access subject. Never a JWT or service token.
  final String identity = '',
  final String? packageId,

  /// Confirmed account values plus current client session values, injected before Source construction.
  final wire.PreferenceBootstrap? preferenceBootstrap,
});

typedef RuntimeSession = wire.RuntimeSession;
typedef SourceInfo = wire.SourceInfo;
typedef SourceResult = wire.SourceResult;

final class const SourceRequest({
  required final String packageId,
  required final wire.SourceCall call,
});

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

final class const RuntimeEvent({
  required final String generation,
  required final RuntimeErrorCode code,
  final String? message,
  final bool containerWide = false,
});

/// Shared version check; readiness also requires package, files and Source init.
bool isCompatibleHost(wire.RuntimeHello hello) =>
    hello.protocolVersion == protocolVersion && hello.hostAbi == hostAbi;
