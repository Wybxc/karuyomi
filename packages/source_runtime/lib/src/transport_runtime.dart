part of '../source_runtime.dart';

/// A platform bridge for standard ProtoJSON control envelopes, never body bytes.
abstract interface class RuntimeTransport {
  Future<Object?> control(Map<String, Object?> request);
}

/// Only a platform-owned resource table may authorize a local image file.
/// A file URI received from a WebView is not itself evidence of ownership.
abstract interface class ManagedImageTransport {
  bool ownsImageLocation(String resourceId, String generation, Uri location);
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
          wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY =>
            RuntimeErrorCode.storageBusy,
          _ => RuntimeErrorCode.runtimeLost,
        },
        error.message,
        retryable: error.retryable,
        javaClass: error.hasJavaClass() ? error.javaClass : null,
      );

  @override
  String toString() => '$code: $message';
}

final class _ImageAcquisition {
  bool cancelled = false;
}

final class _ImageOwner {
  _ImageOwner(this.image);
  final ImageResource image;
  Future<void>? releasing;
}

final class TransportSourceRuntime implements SourceRuntime {
  TransportSourceRuntime(this.transport);
  static int _instanceSequence = 0;
  final RuntimeTransport transport;
  final int _instanceId = ++_instanceSequence;
  int _controlSequence = 0;
  // Container state and its invalidation event must change in one turn.
  // Delayed delivery can otherwise retire a replacement opened after rebuild.
  final _events = StreamController<RuntimeEvent>.broadcast(sync: true);
  RuntimeSession? _session;
  String? _packageId;
  int _epoch = 0;
  bool _disposed = false;
  bool _preferencesEdited = false;
  RuntimeException? _accessFailure;
  Future<RuntimeSession>? _opening;
  String? _openKey;
  final _imageAcquisitions = <(String, String), _ImageAcquisition>{};
  final _imageOwners = <(String, String), _ImageOwner>{};

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  void containerLost(String message) {
    ++_epoch;
    _session = null;
    _opening = null;
    _openKey = null;
    _accessFailure = null;
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
    final epoch = _epoch;
    final requestGeneration = switch (command) {
      wire.ControlRequest_Command.invoke => request.invoke.generation,
      wire.ControlRequest_Command.cancel => request.cancel.generation,
      wire.ControlRequest_Command.acquireImage =>
        request.acquireImage.generation,
      wire.ControlRequest_Command.cancelImage => request.cancelImage.generation,
      wire.ControlRequest_Command.releaseImage =>
        request.releaseImage.generation,
      wire.ControlRequest_Command.closePageSession =>
        request.closePageSession.generation,
      wire.ControlRequest_Command.closeBuild => request.closeBuild.generation,
      _ => null,
    };
    bool current() =>
        epoch == _epoch &&
        (!_disposed || command == wire.ControlRequest_Command.dispose);
    const expired = RuntimeException(
      RuntimeErrorCode.runtimeLost,
      'Control response belongs to an expired runtime',
    );
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
      final ownsImageResult =
          command == wire.ControlRequest_Command.acquireImage &&
          response.whichResult() == wire.ControlResponse_Result.image;
      if (response.requestId != request.requestId) {
        if (ownsImageResult) {
          await _releaseRejectedImage(
            response.image,
            request.acquireImage.generation,
          );
        }
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Control response identity mismatch',
        );
      }
      // An image body still needs ownership cleanup if it arrives after replacement.
      if (!current() && !ownsImageResult) throw expired;
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
      if (!current()) throw expired;
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
      // Cleanup may still address the previous generation after a new open.
      // Its failure belongs to that owner and cannot invalidate the new slot.
      if (requestGeneration != null &&
          requestGeneration != _session?.generation) {
        throw failure;
      }
      final localImageTimeout =
          failure.code == RuntimeErrorCode.timeout &&
          {
            wire.ControlRequest_Command.acquireImage,
            wire.ControlRequest_Command.cancelImage,
            wire.ControlRequest_Command.releaseImage,
            wire.ControlRequest_Command.closePageSession,
          }.contains(command);
      final management = {
        wire.ControlRequest_Command.prepareBuild,
        wire.ControlRequest_Command.cancelPreparation,
        wire.ControlRequest_Command.extensionCache,
        wire.ControlRequest_Command.forgetExtensionArtifact,
        wire.ControlRequest_Command.closeBuild,
      }.contains(command);
      final independentApiFailure =
          command == wire.ControlRequest_Command.fetchApi &&
          !{
            RuntimeErrorCode.accessRequired,
            RuntimeErrorCode.accessDenied,
          }.contains(failure.code);
      final failedGeneration = _session?.generation ?? '';
      if (!management &&
          {
            RuntimeErrorCode.accessRequired,
            RuntimeErrorCode.accessDenied,
          }.contains(failure.code)) {
        // Keep the old generation available for release/close. It has no
        // execution capability while Access is paused, even for cached reads.
        _accessFailure = failure;
        _openKey = null;
        _opening = null;
      } else if (!management &&
          !independentApiFailure &&
          failure.code == RuntimeErrorCode.runtimeLost) {
        _session = null;
      }
      if (!_events.isClosed &&
          !localImageTimeout &&
          !management &&
          !independentApiFailure) {
        _events.add(
          RuntimeEvent(
            generation: failedGeneration,
            code: failure.code,
            message: failure.message,
          ),
        );
      }
      throw failure;
    }
  }

  @override
  Future<wire.PreparedBuild> prepareBuild({
    required String preparationId,
    required wire.ExtensionBuildDescriptor build,
  }) async {
    _extensionRequire(
      _extensionControlId.hasMatch(preparationId),
      'Invalid preparation identity',
    );
    _extensionRequire(
      _extensionControlId.hasMatch(build.buildId) &&
          build.manifestPath ==
              '/extensions/builds/${build.buildId}/manifest.json' &&
          build.packageName.isNotEmpty &&
          build.packageName.length <= 200 &&
          build.repoId.isNotEmpty &&
          build.repoId.length <= 200 &&
          build.sources.isNotEmpty &&
          build.sources.length <= 500,
      'Invalid preparation descriptor',
    );
    final selected = build.deepCopy()..freeze();
    final value = (await _exchange(
      wire.ControlRequest(
        prepareBuild: wire.PrepareBuildRequest(
          preparationId: preparationId,
          build: selected,
        ),
      ),
      wire.ControlResponse_Result.preparedBuild,
    )).preparedBuild;
    _extensionRequire(
      value.hasBuild() &&
          value.build == selected &&
          _extensionDigest.hasMatch(value.bundleSha256) &&
          value.byteLength > 0 &&
          value.byteLength <= 64 * 1024 * 1024,
      'Prepared extension does not match the selected build',
    );
    return value.deepCopy()..freeze();
  }

  @override
  Future<wire.ExtensionCacheState> extensionCache() async {
    final value = (await _exchange(
      wire.ControlRequest(extensionCache: wire.Empty()),
      wire.ControlResponse_Result.extensionCache,
    )).extensionCache;
    _extensionRequire(
      value.maxArtifacts == 128 &&
          value.maxBytes == 256 * 1024 * 1024 &&
          value.artifacts.length <= value.maxArtifacts &&
          value.totalBytes <= value.maxBytes,
      'Invalid extension cache budget',
    );
    final digests = <String>{};
    var total = 0;
    for (final artifact in value.artifacts) {
      _extensionRequire(
        _extensionDigest.hasMatch(artifact.sha256) &&
            digests.add(artifact.sha256) &&
            artifact.byteLength > 0 &&
            artifact.byteLength <= 64 * 1024 * 1024 &&
            {
              'application/javascript',
              'text/javascript',
            }.contains(artifact.contentType),
        'Invalid cached extension artifact',
      );
      total += artifact.byteLength;
    }
    _extensionRequire(
      total == value.totalBytes,
      'Extension cache size does not match its artifacts',
    );
    return value.deepCopy()..freeze();
  }

  @override
  Future<void> cancelPreparation(String preparationId) async {
    _extensionRequire(
      _extensionControlId.hasMatch(preparationId),
      'Invalid preparation identity',
    );
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          cancelPreparation: wire.CancelPreparationRequest(
            preparationId: preparationId,
          ),
        ),
        wire.ControlResponse_Result.completed,
      )).completed.completed,
    );
  }

  @override
  Future<void> forgetExtensionArtifact(String sha256) async {
    _extensionRequire(
      _extensionDigest.hasMatch(sha256),
      'Invalid extension digest',
    );
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          forgetExtensionArtifact: wire.ForgetExtensionArtifactRequest(
            sha256: sha256,
          ),
        ),
        wire.ControlResponse_Result.completed,
      )).completed.completed,
    );
  }

  @override
  Future<void> closeBuild({
    required String buildId,
    required String generation,
  }) async {
    _extensionRequire(
      _extensionControlId.hasMatch(buildId) &&
          generation.isNotEmpty &&
          generation.length <= 200,
      'Invalid extension close identity',
    );
    _requireAck(
      (await _exchange(
        wire.ControlRequest(
          closeBuild: wire.CloseBuildRequest(
            buildId: buildId,
            generation: generation,
          ),
        ),
        wire.ControlResponse_Result.closed,
      )).closed.closed,
    );
    if (_session?.buildId == buildId && _session?.generation == generation) {
      ++_epoch;
      _session = null;
      _opening = null;
      _openKey = null;
      _preferencesEdited = false;
      _accessFailure = null;
    }
  }

  @override
  Future<RuntimeSession> open(BuildDescriptor build) {
    final bootstrap = build.preferenceBootstrap?.deepCopy();
    bootstrap?.freeze();
    if (bootstrap != null) {
      wire.validatePreferenceBootstrap(bootstrap);
      if (build.packageId != null && bootstrap.packageName != build.packageId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Preference bootstrap package does not match the selected extension',
        );
      }
    }
    final openingBuild = BuildDescriptor(
      buildId: build.buildId,
      manifestUri: build.manifestUri,
      sha256: build.sha256,
      identity: build.identity,
      packageId: build.packageId,
      preferenceBootstrap: bootstrap,
    );
    final key = [
      build.buildId,
      build.manifestUri.toString(),
      build.sha256,
      build.identity,
      build.packageId ?? '',
      bootstrap == null ? '' : jsonEncode(wire.encodeProtoJson(bootstrap)),
    ].join('\u0000');
    if (!_preferencesEdited && _openKey == key) {
      if (_opening != null) return _opening!;
      if (_session != null) return Future.value(_session);
    }
    _openKey = key;
    final opening = _open(openingBuild);
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
    _preferencesEdited = false;
    _accessFailure = null;
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
          preferenceBootstrap: build.preferenceBootstrap,
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
    final bootstrap = build.preferenceBootstrap;
    if (bootstrap != null &&
        bootstrap.sources.any(
          (source) => !response.sources.any(
            (candidate) => candidate.id == source.sourceId,
          ),
        )) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Preference bootstrap contains a Source outside this extension',
      );
    }
    _packageId = build.packageId;
    response.freeze();
    return _session = response;
  }

  @override
  Future<SourceResult> invoke(SourceRequest request) async {
    _requireConfirmedPreferences();
    final accessFailure = _accessFailure;
    if (accessFailure != null) throw accessFailure;
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
    try {
      if (call.hasEditPreference()) {
        wire.validatePreferenceEditRequest(call.editPreference);
      }
      if (call.hasGetFilters()) wire.validateGetFiltersRequest(call.getFilters);
      if (call.hasSearch() && call.search.hasFilters()) {
        wire.validateFilterSelection(call.search.filters);
      }
    } on FormatException {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid Source control request',
      );
    }
    final expected = switch (call.whichRequest()) {
      wire.SourceCall_Request.getPreferences =>
        wire.SourceResult_Payload.preferences,
      wire.SourceCall_Request.editPreference =>
        wire.SourceResult_Payload.preferenceEdit,
      wire.SourceCall_Request.getFilters => wire.SourceResult_Payload.filters,
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
    // A dispatched callback can mutate storage even if its response is lost.
    // Only a fresh confirmed bootstrap and generation may resume Source work.
    if (call.hasEditPreference()) _preferencesEdited = true;
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
    final pausedFailure = _accessFailure;
    if (pausedFailure != null) throw pausedFailure;
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
        case wire.SourceResult_Payload.preferences:
          wire.validatePreferenceSnapshot(response.preferences);
        case wire.SourceResult_Payload.preferenceEdit:
          wire.validatePreferenceEditResult(response.preferenceEdit);
        case wire.SourceResult_Payload.filters:
          wire.validateFilterSnapshot(response.filters);
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

  void _requireConfirmedPreferences() {
    if (_preferencesEdited) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Confirm Source preferences and reopen the runtime before continuing',
      );
    }
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

  RuntimeSession _imageRequestSession(ImageAcquireRequest request) {
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
    return session;
  }

  Future<void> _releaseRejectedImage(
    wire.ImageResource image,
    String generation,
  ) async {
    // A rejected reply cannot revoke an accepted resource still used by the UI.
    if (image.resourceId.isNotEmpty &&
        !_imageOwners.containsKey((generation, image.resourceId))) {
      await releaseImage(
        ImageReleaseRequest(
          resourceId: image.resourceId,
          generation: generation,
        ),
      );
    }
  }

  @override
  Future<ImageResource> acquireImage(ImageAcquireRequest request) async {
    _requireConfirmedPreferences();
    final accessFailure = _accessFailure;
    if (accessFailure != null) throw accessFailure;
    final session = _imageRequestSession(request);
    final epoch = _epoch;
    final key = (request.generation, request.requestId);
    if (_imageAcquisitions.containsKey(key)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image request is already pending',
      );
    }
    if (_imageAcquisitions.length + _imageOwners.length >=
        wire.imageResourceLimit) {
      throw const RuntimeException(
        RuntimeErrorCode.limitExceeded,
        'Image resource window is full',
      );
    }
    final acquisition = _ImageAcquisition();
    _imageAcquisitions[key] = acquisition;
    try {
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
        if (_disposed ||
            epoch != _epoch ||
            _session?.generation != session.generation) {
          throw const RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Discarded a stale image resource',
          );
        }
        final pausedFailure = _accessFailure;
        if (pausedFailure != null) throw pausedFailure;
        if (acquisition.cancelled) {
          throw const RuntimeException(
            RuntimeErrorCode.cancelled,
            'Discarded a cancelled image resource',
          );
        }
        if (response.resourceId.isEmpty ||
            response.resourceId.length > 200 ||
            response.generation != session.generation ||
            _imageOwners.containsKey((
              request.generation,
              response.resourceId,
            ))) {
          throw const RuntimeException(
            RuntimeErrorCode.protocolError,
            'Invalid or reused image resource identity',
          );
        }
        final location = response.url.length <= 4096
            ? Uri.tryParse(response.url)
            : null;
        final managedFile =
            location != null &&
            location.scheme == 'file' &&
            transport is ManagedImageTransport &&
            (transport as ManagedImageTransport).ownsImageLocation(
              response.resourceId,
              response.generation,
              location,
            );
        if (location == null ||
            (location.scheme != 'blob' && !managedFile) ||
            response.byteLength <= 0 ||
            response.byteLength > wire.imageByteLimit) {
          throw const RuntimeException(
            RuntimeErrorCode.protocolError,
            'Invalid managed image resource',
          );
        }
        final residentBytes = _imageOwners.values.fold<int>(
          0,
          (sum, owner) => sum + owner.image.byteLength,
        );
        if (residentBytes + response.byteLength > wire.imageByteLimit) {
          throw const RuntimeException(
            RuntimeErrorCode.limitExceeded,
            'Image resources exceed their body budget',
          );
        }
        final image = ImageResource(
          id: response.resourceId,
          generation: response.generation,
          location: location,
          byteLength: response.byteLength,
        );
        _imageOwners[(image.generation, image.id)] = _ImageOwner(image);
        return image;
      } catch (_) {
        await _releaseRejectedImage(response, request.generation);
        rethrow;
      }
    } finally {
      if (identical(_imageAcquisitions[key], acquisition)) {
        _imageAcquisitions.remove(key);
      }
    }
  }

  @override
  Future<void> cancelImage(ImageCancelRequest request) async {
    final acquisition =
        _imageAcquisitions[(request.generation, request.requestId)];
    if (acquisition != null) acquisition.cancelled = true;
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
  Future<void> releaseImage(ImageReleaseRequest request) {
    if (_disposed) return Future.value();
    final key = (request.generation, request.resourceId);
    final owner = _imageOwners[key];
    Future<void> release() async {
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
      if (owner != null && identical(_imageOwners[key], owner)) {
        _imageOwners.remove(key);
      }
    }

    if (owner == null) return release();
    final releasing = owner.releasing ??= release();
    unawaited(
      releasing.then(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(owner.releasing, releasing)) owner.releasing = null;
        },
      ),
    );
    return releasing;
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
      _imageOwners.clear();
      await _events.close();
    }
  }
}
