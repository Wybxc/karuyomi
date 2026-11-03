library;

import 'package:reader_core/reader_core.dart';
import 'src/generated.dart';

export 'src/generated.dart';

/// Web uses JS interop; native uses a managed WebView control page.
/// No production adapter or TeaVM artifact is included in this scaffold.
abstract interface class SourceRuntime implements PageProvider {
  Stream<RuntimeEvent> get events;
  Future<RuntimeSession> open(BuildDescriptor build);
  Future<SourceResult> invoke(SourceRequest request);
  Future<void> dispose();
}

final class BuildDescriptor {
  const BuildDescriptor({
    required this.buildId,
    required this.manifestUri,
    required this.sha256,
  });

  final String buildId;
  final Uri manifestUri;
  final String sha256;
}

final class RuntimeSession {
  const RuntimeSession({required this.generation, required this.buildId});
  final String generation;
  final String buildId;
}

final class SourceRequest {
  const SourceRequest({
    required this.requestId,
    required this.generation,
    required this.packageId,
    required this.sourceId,
    required this.operation,
    required this.arguments,
  });

  final String requestId;
  final String generation;
  final String packageId;
  // External 64 bit identifiers stay strings across Dart/JS.
  final String sourceId;
  final String operation;
  final Map<String, Object?> arguments;
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
}

final class RuntimeEvent {
  const RuntimeEvent({required this.generation, required this.code});
  final String generation;
  final RuntimeErrorCode code;
}

/// Shared version check; readiness also requires package, files and Source init.
bool isCompatibleHost(Map<String, Object?> hello) =>
    hello['protocolVersion'] == protocolVersion && hello['hostAbi'] == hostAbi;
