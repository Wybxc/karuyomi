part of '../source_runtime.dart';

/// A platform bridge for standard ProtoJSON control envelopes, never body bytes.
abstract interface class RuntimeTransport {
  Future<Object?> control(Map<String, Object?> request);
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

  factory RuntimeException.fromProto(wire.RuntimeError error) =>
      RuntimeException(
        switch (error.code) {
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_CANCELLED =>
            RuntimeErrorCode.cancelled,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_TIMEOUT =>
            RuntimeErrorCode.timeout,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED =>
            RuntimeErrorCode.accessRequired,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED =>
            RuntimeErrorCode.accessDenied,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR =>
            RuntimeErrorCode.sourceError,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY =>
            RuntimeErrorCode.unsupportedCapability,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_PROTOCOL_ERROR =>
            RuntimeErrorCode.protocolError,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_INTEGRITY_ERROR =>
            RuntimeErrorCode.integrityError,
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_LIMIT_EXCEEDED =>
            RuntimeErrorCode.limitExceeded,
          _ => RuntimeErrorCode.runtimeLost,
        },
        error.message,
        retryable: error.retryable,
        javaClass: error.hasJavaClass() ? error.javaClass : null,
      );

  @override
  String toString() => '$code: $message';
}

final class TransportSourceRuntime implements SourceRuntime {
  TransportSourceRuntime(this.transport);
  static int _instanceSequence = 0;
  final RuntimeTransport transport;
  final int _instanceId = ++_instanceSequence;
  int _controlSequence = 0;
  final _events = StreamController<RuntimeEvent>.broadcast();
  RuntimeSession? _session;
  String? _packageId;
  int _epoch = 0;
  bool _disposed = false;
  Future<RuntimeSession>? _opening;
  String? _openKey;

  @override
  Stream<RuntimeEvent> get events => _events.stream;

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

  Future<wire.ControlResponse> _exchange(
    wire.ControlRequest request,
    wire.ControlResponse_Result expected,
  ) async {
    final command = request.whichCommand();
    if (_disposed && command != wire.ControlRequest_Command.dispose) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Runtime was disposed',
      );
    }
    request.requestId = 'control-$_instanceId-${++_controlSequence}';
    try {
      final response = wire.decodeProtoJson(
        wire.ControlResponse(),
        await transport.control(wire.encodeProtoJson(request)),
      );
      if (response.requestId != request.requestId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Control response identity mismatch',
        );
      }
      if (response.whichResult() == wire.ControlResponse_Result.error) {
        throw RuntimeException.fromProto(response.error);
      }
      if (response.whichResult() != expected) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Control response has the wrong result',
        );
      }
      return response;
    } catch (error) {
      final failure = error is RuntimeException
          ? error
          : error is FormatException
          ? const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Invalid runtime ProtoJSON',
            )
          : const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Runtime control transport failed',
            );
      final localImageTimeout =
          failure.code == RuntimeErrorCode.timeout &&
          {
            wire.ControlRequest_Command.acquireImage,
            wire.ControlRequest_Command.cancelImage,
            wire.ControlRequest_Command.releaseImage,
            wire.ControlRequest_Command.closePageSession,
          }.contains(command);
      if (!_events.isClosed && !localImageTimeout) {
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
    final hello = (await _exchange(
      wire.ControlRequest(ready: wire.Empty()),
      wire.ControlResponse_Result.hello,
    )).hello;
    if (!isCompatibleHost(hello) || hello.runtimeBaseline != runtimeBaseline) {
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
    final response = (await _exchange(
      wire.ControlRequest(
        open: wire.OpenRequest(
          manifestPath: build.manifestUri.toString(),
          identity: build.identity,
          expectedBuildId: build.buildId,
          expectedBundleSha256: build.sha256,
        ),
      ),
      wire.ControlResponse_Result.session,
    )).session;
    if (_disposed || epoch != _epoch) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Runtime open result belongs to an expired container',
      );
    }
    if (response.protocolVersion != protocolVersion ||
        response.buildId != build.buildId ||
        response.generation.isEmpty ||
        response.workerInstanceId.isEmpty ||
        response.sources.isEmpty ||
        response.sources.any(
          (source) => !RegExp(r'^-?\d+$').hasMatch(source.id),
        ) ||
        response.sources.map((source) => source.id).toSet().length !=
            response.sources.length) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime session does not match the requested build',
      );
    }
    _packageId = build.packageId;
    response.freeze();
    return _session = response;
  }

  @override
  Future<SourceResult> invoke(SourceRequest request) async {
    final session = _session;
    final call = request.call.deepCopy();
    if (session == null ||
        call.generation != session.generation ||
        (_packageId != null && request.packageId != _packageId) ||
        !session.sources.any((source) => source.id == call.sourceId)) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Source request belongs to an expired or different runtime',
      );
    }
    final expected = switch (call.whichRequest()) {
      wire.SourceCall_Request.popular ||
      wire.SourceCall_Request.latest ||
      wire.SourceCall_Request.search => wire.SourceResult_Payload.mangaPage,
      wire.SourceCall_Request.details => wire.SourceResult_Payload.manga,
      wire.SourceCall_Request.chapters => wire.SourceResult_Payload.chapters,
      wire.SourceCall_Request.pages => wire.SourceResult_Payload.pageList,
      _ => throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Source request requires an operation',
      ),
    };
    final epoch = _epoch;
    final response = (await _exchange(
      wire.ControlRequest(invoke: call),
      wire.ControlResponse_Result.source,
    )).source;
    if (_disposed ||
        epoch != _epoch ||
        response.generation != session.generation ||
        response.requestId != call.requestId ||
        response.buildId != session.buildId) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Discarded a stale Source result',
      );
    }
    if (response.whichPayload() != expected) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Source result does not match its operation',
      );
    }
    try {
      void manga(wire.Manga value) {
        if (value.hasMemoJson()) wire.checkSourceMemo(value.memoJson);
      }

      switch (response.whichPayload()) {
        case wire.SourceResult_Payload.mangaPage:
          response.mangaPage.mangas.forEach(manga);
        case wire.SourceResult_Payload.manga:
          manga(response.manga);
        case wire.SourceResult_Payload.chapters:
          for (final chapter in response.chapters.chapters) {
            if (chapter.hasMemoJson()) wire.checkSourceMemo(chapter.memoJson);
            if (chapter.hasChapterNumber() && !chapter.chapterNumber.isFinite) {
              throw const FormatException('Chapter number must be finite');
            }
          }
        case wire.SourceResult_Payload.pageList:
          wire.checkJsonBudget(
            wire.encodeProtoJson(response.pageList, maxBytes: 2 * 1024 * 1024),
            maxBytes: 2 * 1024 * 1024,
          );
        case wire.SourceResult_Payload.notSet:
          throw const FormatException('Source result requires a payload');
      }
    } on FormatException {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid Source metadata',
      );
    }
    response.freeze();
    return response;
  }

  @override
  Future<void> cancel(String requestId) async {
    final session = _session;
    if (session == null) return;
    final result = (await _exchange(
      wire.ControlRequest(
        cancel: wire.CancelSourceRequest(
          requestId: requestId,
          generation: session.generation,
        ),
      ),
      wire.ControlResponse_Result.completed,
    )).completed;
    _requireAck(result.completed);
  }

  void _requireAck(bool acknowledged) {
    if (!acknowledged) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime cleanup was not acknowledged',
      );
    }
  }

  @override
  Future<ImageResource> acquireImage(ImageAcquireRequest request) async {
    final session = _session;
    if (session == null ||
        request.generation != session.generation ||
        !session.sources.any((source) => source.id == request.sourceId)) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Image request belongs to an expired Source',
      );
    }
    if ([
          request.requestId,
          request.pageSessionId,
          request.pageKey,
        ].any((value) => value.isEmpty || value.length > 200) ||
        request.timeout <= Duration.zero ||
        request.timeout > const Duration(minutes: 5)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid image control request',
      );
    }
    final epoch = _epoch;
    final response = (await _exchange(
      wire.ControlRequest(
        acquireImage: wire.AcquireImage(
          requestId: request.requestId,
          sourceId: request.sourceId,
          pageSessionId: request.pageSessionId,
          pageKey: request.pageKey,
          generation: request.generation,
          timeoutMs: request.timeout.inMilliseconds,
        ),
      ),
      wire.ControlResponse_Result.image,
    )).image;
    try {
      if (response.resourceId.isEmpty ||
          response.resourceId.length > 200 ||
          response.generation != session.generation) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid image resource identity',
        );
      }
      if (_disposed ||
          epoch != _epoch ||
          _session?.generation != session.generation) {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Discarded a stale image resource',
        );
      }
      final location = response.url.length <= 4096
          ? Uri.tryParse(response.url)
          : null;
      if (location == null ||
          location.scheme != 'blob' ||
          !RegExp(
            r'^image/[a-zA-Z0-9.+-]{1,80}$',
          ).hasMatch(response.mimeType) ||
          response.byteLength <= 0 ||
          response.byteLength > 64 * 1024 * 1024 ||
          response.width <= 0 ||
          response.height <= 0 ||
          response.width > 1000000 ||
          response.height > 1000000) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid managed image resource',
        );
      }
      if (response.width * response.height > 16 * 1024 * 1024) {
        throw const RuntimeException(
          RuntimeErrorCode.limitExceeded,
          'Image exceeds the raster budget',
        );
      }
      return ImageResource(
        id: response.resourceId,
        generation: session.generation,
        location: location,
        mimeType: response.mimeType,
        byteLength: response.byteLength,
        width: response.width,
        height: response.height,
      );
    } catch (_) {
      if (response.resourceId.isNotEmpty) {
        await releaseImage(
          ImageReleaseRequest(
            resourceId: response.resourceId,
            generation: request.generation,
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> cancelImage(ImageCancelRequest request) async {
    if (_disposed) return;
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          cancelImage: wire.CancelImage(
            requestId: request.requestId,
            generation: request.generation,
          ),
        ),
        wire.ControlResponse_Result.released,
      )).released.released,
    );
  }

  @override
  Future<void> releaseImage(ImageReleaseRequest request) async {
    if (_disposed) return;
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          releaseImage: wire.ReleaseImage(
            resourceId: request.resourceId,
            generation: request.generation,
          ),
        ),
        wire.ControlResponse_Result.released,
      )).released.released,
    );
  }

  @override
  Future<void> closePageSession(PageSessionRef session) async {
    if (_disposed) return;
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          closePageSession: wire.ClosePageSession(
            pageSessionId: session.pageSessionId,
            generation: session.generation,
          ),
        ),
        wire.ControlResponse_Result.closed,
      )).closed.closed,
    );
  }

  Future<wire.ApiFetchResponse> fetchApi(wire.ApiFetchRequest request) async {
    final response = (await _exchange(
      wire.ControlRequest(fetchApi: request),
      wire.ControlResponse_Result.api,
    )).api;
    if ((response.status == 0 && !response.redirected) ||
        (response.status != 0 &&
            (response.status < 100 || response.status > 599))) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid API HTTP status',
      );
    }
    return response;
  }

  Future<void> rebuildHost() async {
    _requireAck(
      (await _exchange(
        wire.ControlRequest(rebuild: wire.Empty()),
        wire.ControlResponse_Result.completed,
      )).completed.completed,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _session = null;
    try {
      _requireAck(
        (await _exchange(
          wire.ControlRequest(dispose: wire.Empty()),
          wire.ControlResponse_Result.completed,
        )).completed.completed,
      );
    } finally {
      await _events.close();
    }
  }
}
