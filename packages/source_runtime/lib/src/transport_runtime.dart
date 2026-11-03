part of '../source_runtime.dart';

/// A platform bridge for small control DTOs. Image bytes have a separate gate.
abstract interface class RuntimeTransport {
  Future<Object?> call(
    String method, [
    Map<String, Object?> payload = const {},
  ]);
}

final class RuntimeException implements Exception {
  const RuntimeException(
    this.code,
    this.message, {
    this.retryable = false,
    this.javaClass,
  });
  final RuntimeErrorCode code;
  final String message;
  final bool retryable;
  final String? javaClass;

  factory RuntimeException.fromWire(Object? value) {
    if (value is RuntimeException) return value;
    final data = value is Map && value.keys.every((key) => key is String)
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final code = switch (data['code']) {
      'cancelled' => RuntimeErrorCode.cancelled,
      'timeout' => RuntimeErrorCode.timeout,
      'access_required' => RuntimeErrorCode.accessRequired,
      'access_denied' => RuntimeErrorCode.accessDenied,
      'unsupported_capability' => RuntimeErrorCode.unsupportedCapability,
      'protocol_error' => RuntimeErrorCode.protocolError,
      'integrity_error' => RuntimeErrorCode.integrityError,
      'limit_exceeded' => RuntimeErrorCode.limitExceeded,
      'source_error' => RuntimeErrorCode.sourceError,
      _ => RuntimeErrorCode.runtimeLost,
    };
    return RuntimeException(
      code,
      data['message']?.toString() ?? value.toString(),
      retryable: data['retryable'] == true,
      javaClass: data['javaClass'] is String
          ? data['javaClass'] as String
          : null,
    );
  }

  @override
  String toString() => '$code: $message';
}

/// Validates the same protocol/generation across JS interop and WebView RPC.
final class TransportSourceRuntime implements SourceRuntime {
  TransportSourceRuntime(this.transport);
  final RuntimeTransport transport;
  final _events = StreamController<RuntimeEvent>.broadcast();
  RuntimeSession? _session;
  String? _packageId;
  int _epoch = 0;
  bool _disposed = false;
  Future<RuntimeSession>? _opening;
  String? _openKey;

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  /// Called by native content-process lifecycle notifications.
  void containerLost(String message) {
    ++_epoch;
    _session = null;
    _opening = null;
    _openKey = null;
    if (!_events.isClosed) {
      _events.add(
        RuntimeEvent(
          generation: '',
          code: RuntimeErrorCode.runtimeLost,
          message: message,
        ),
      );
    }
  }

  Map<String, Object?> _object(Object? value) {
    if (value is! Map || !value.keys.every((key) => key is String)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime did not return an object',
      );
    }
    return Map<String, Object?>.from(value);
  }

  Future<Object?> _call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (_disposed && method != 'dispose') {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Runtime was disposed',
      );
    }
    try {
      return await transport.call(method, payload);
    } catch (error) {
      final failure = RuntimeException.fromWire(error);
      if (!_events.isClosed) {
        _events.add(
          RuntimeEvent(
            generation: _session?.generation ?? '',
            code: failure.code,
            message: failure.message,
          ),
        );
      }
      if ({
        RuntimeErrorCode.runtimeLost,
        RuntimeErrorCode.accessRequired,
        RuntimeErrorCode.accessDenied,
      }.contains(failure.code)) {
        _session = null;
      }
      throw failure;
    }
  }

  @override
  Future<RuntimeSession> open(BuildDescriptor build) {
    final key = [
      build.buildId,
      build.manifestUri.toString(),
      build.sha256,
      build.identity,
      build.packageId ?? '',
    ].join('\u0000');
    if (_openKey == key) {
      if (_opening != null) return _opening!;
      if (_session != null) return Future.value(_session);
    }
    _openKey = key;
    final opening = _open(build);
    _opening = opening;
    unawaited(
      opening.then<void>(
        (_) {
          if (identical(_opening, opening)) _opening = null;
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_opening, opening)) {
            _opening = null;
            _openKey = null;
          }
        },
      ),
    );
    return opening;
  }

  Future<RuntimeSession> _open(BuildDescriptor build) async {
    if (build.identity.isEmpty) {
      throw const RuntimeException(
        RuntimeErrorCode.accessRequired,
        'Confirm an Access identity before loading an extension',
      );
    }
    if (build.manifestUri.hasScheme ||
        build.manifestUri.hasAuthority ||
        !RegExp(r'^[a-zA-Z0-9._-]{1,200}$').hasMatch(build.buildId) ||
        build.manifestUri.toString() !=
            '/extensions/builds/${build.buildId}/manifest.json') {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime manifest must match the selected static build',
      );
    }
    final epoch = ++_epoch;
    _session = null;
    final hello = _object(await _call('ready'));
    if (!isCompatibleHost(hello) ||
        hello['runtimeBaseline'] != runtimeBaseline) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Incompatible runtime host',
      );
    }
    if (_disposed || epoch != _epoch) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Runtime handshake belongs to an expired container',
      );
    }
    final response = _object(
      await _call('open', {
        'manifestPath': build.manifestUri.toString(),
        'identity': build.identity,
        'expectedBuildId': build.buildId,
        'expectedBundleSha256': build.sha256,
      }),
    );
    if (_disposed || epoch != _epoch) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Runtime open result belongs to an expired container',
      );
    }
    if (response['protocolVersion'] != protocolVersion ||
        response['buildId'] != build.buildId ||
        response['generation'] is! String ||
        (response['generation'] as String).isEmpty ||
        response['workerInstanceId'] is! String ||
        (response['workerInstanceId'] as String).isEmpty ||
        response['sources'] is! List ||
        response['capabilities'] is! List ||
        !(response['capabilities'] as List).every((value) => value is String)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime session does not match the requested build',
      );
    }
    final sources = (response['sources'] as List)
        .map((value) {
          final item = _object(value);
          if (item['id'] is! String ||
              !RegExp(r'^-?\d+$').hasMatch(item['id'] as String) ||
              item['name'] is! String ||
              item['lang'] is! String ||
              (item['supportsLatest'] != null &&
                  item['supportsLatest'] is! bool) ||
              (item['baseUrl'] != null && item['baseUrl'] is! String)) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Invalid Source identity',
            );
          }
          return SourceInfo(
            id: item['id'] as String,
            name: item['name'] as String,
            lang: item['lang'] as String,
            supportsLatest: item['supportsLatest'] as bool?,
            baseUrl: item['baseUrl'] as String?,
          );
        })
        .toList(growable: false);
    if (sources.isEmpty ||
        sources.map((source) => source.id).toSet().length != sources.length) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime Sources must be nonempty and unique',
      );
    }
    _packageId = build.packageId;
    return _session = RuntimeSession(
      generation: response['generation'] as String,
      buildId: build.buildId,
      workerInstanceId: response['workerInstanceId'] as String,
      sources: sources,
      capabilities: List<String>.from(
        response['capabilities'] as List? ?? const [],
      ),
    );
  }

  @override
  Future<SourceResult> invoke(SourceRequest request) async {
    final session = _session;
    if (session == null ||
        request.generation != session.generation ||
        (_packageId != null && request.packageId != _packageId) ||
        !session.sources.any((source) => source.id == request.sourceId)) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Source request belongs to an expired or different runtime',
      );
    }
    final epoch = _epoch;
    final response = _object(
      await _call('invoke', {
        'requestId': request.requestId,
        'sourceId': request.sourceId,
        'operation': request.operation,
        'args': request.arguments,
        'timeoutMs': request.timeout.inMilliseconds,
      }),
    );
    if (_disposed ||
        epoch != _epoch ||
        response['generation'] != session.generation ||
        response['requestId'] != request.requestId ||
        response['buildId'] != session.buildId) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Discarded a stale Source result',
      );
    }
    return SourceResult(
      requestId: request.requestId,
      generation: session.generation,
      data: _object(response['data']),
    );
  }

  @override
  Future<void> cancel(String requestId) async {
    await _call('cancel', {'requestId': requestId});
  }

  @override
  Future<ImageResource> acquire(PageRef page) => Future.error(
    const RuntimeException(
      RuntimeErrorCode.unsupportedCapability,
      'The processed-image resource channel has not passed its platform gate',
    ),
  );

  @override
  Future<void> release(String resourceId) async {
    // This adapter never acquires an image until that resource channel exists.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _session = null;
    try {
      await _call('dispose');
    } finally {
      await _events.close();
    }
  }
}
