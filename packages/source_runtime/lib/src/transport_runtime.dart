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
          _ => RuntimeErrorCode.runtimeLost,
        },
        error.message,
        retryable: error.retryable,
        javaClass: error.hasJavaClass() ? error.javaClass : null,
      );

  @override
  String toString() => '$code: $message';
}

final class _ImageWindowDemand {
  _ImageWindowDemand(this.request);
  final wire.RequestImageWindow request;
  int revision = 0;
  wire.ImageWindowSnapshot? snapshot;
}

final class _ImageTileOwner {
  _ImageTileOwner(this.pageId, this.epoch, this.tile);
  final String pageId;
  final int epoch;
  final wire.ImageTile tile;
  bool invalidated = false;
  bool retiring = false;
}

final class _ImageWindowObservation {
  _ImageWindowObservation(Iterable<(String, String)> released)
    : excluded = released.toSet();
  final Set<(String, String)> excluded;
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
  final _imagePages = <(String, String), wire.ImagePage>{};
  final _imageWindows = <(String, String), _ImageWindowDemand>{};
  final _imageWindowIds = <(String, String), Set<String>>{};
  final _imageTileLeases = <(String, String), _ImageTileOwner>{};
  final _closingImagePages = <(String, String)>{};
  final _imageWindowObservations = <_ImageWindowObservation>{};
  final _imageTileReleases = <(String, String), int>{};

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  void containerLost(String message) {
    ++_epoch;
    _session = null;
    _opening = null;
    _openKey = null;
    _imagePages.clear();
    _imageWindows.clear();
    _imageWindowIds.clear();
    _closingImagePages.clear();
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
      wire.ControlRequest_Command.acquireEncodedImage =>
        request.acquireEncodedImage.generation,
      wire.ControlRequest_Command.cancelImage => request.cancelImage.generation,
      wire.ControlRequest_Command.releaseImage =>
        request.releaseImage.generation,
      wire.ControlRequest_Command.closePageSession =>
        request.closePageSession.generation,
      wire.ControlRequest_Command.openImagePage =>
        request.openImagePage.generation,
      wire.ControlRequest_Command.requestImageWindow =>
        request.requestImageWindow.generation,
      wire.ControlRequest_Command.waitImageWindow =>
        request.waitImageWindow.generation,
      wire.ControlRequest_Command.releaseImageTile =>
        request.releaseImageTile.generation,
      wire.ControlRequest_Command.closeImagePage =>
        request.closeImagePage.generation,
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
      final ownsEncodedResult =
          command == wire.ControlRequest_Command.acquireEncodedImage &&
          response.whichResult() == wire.ControlResponse_Result.encodedImage;
      if (response.requestId != request.requestId) {
        // A typed resource returned to this acquisition still needs cleanup
        // when its envelope is rejected. Never address a foreign generation.
        if (ownsEncodedResult && response.encodedImage.resourceId.isNotEmpty) {
          await releaseImage(
            ImageReleaseRequest(
              resourceId: response.encodedImage.resourceId,
              generation: request.acquireEncodedImage.generation,
            ),
          );
        }
        await _cleanupRejectedTileControl(request, response);
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Control response identity mismatch',
        );
      }
      // A late image must reach its acquisition ownership cleanup below. Other
      // stale replies cannot publish API/Source/session data into a new epoch.
      final ownsImageResult =
          (command == wire.ControlRequest_Command.acquireImage &&
              response.whichResult() == wire.ControlResponse_Result.image) ||
          ownsEncodedResult ||
          (command == wire.ControlRequest_Command.openImagePage &&
              response.whichResult() ==
                  wire.ControlResponse_Result.imagePage) ||
          ({
                wire.ControlRequest_Command.requestImageWindow,
                wire.ControlRequest_Command.waitImageWindow,
              }.contains(command) &&
              response.whichResult() ==
                  wire.ControlResponse_Result.imageWindow);
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
            wire.ControlRequest_Command.acquireEncodedImage,
            wire.ControlRequest_Command.cancelImage,
            wire.ControlRequest_Command.releaseImage,
            wire.ControlRequest_Command.closePageSession,
            wire.ControlRequest_Command.openImagePage,
            wire.ControlRequest_Command.requestImageWindow,
            wire.ControlRequest_Command.waitImageWindow,
            wire.ControlRequest_Command.releaseImageTile,
            wire.ControlRequest_Command.closeImagePage,
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

  @override
  Future<wire.EncodedImage> acquireEncodedImage(
    ImageAcquireRequest request,
  ) async {
    final session = _imageRequestSession(request);
    final epoch = _epoch;
    final response = (await _exchange(
      wire.ControlRequest(
        acquireEncodedImage: wire.AcquireImage(
          requestId: request.requestId,
          sourceId: request.sourceId,
          pageSessionId: request.pageSessionId,
          pageKey: request.pageKey,
          generation: request.generation,
          timeoutMs: request.timeout.inMilliseconds,
        ),
      ),
      wire.ControlResponse_Result.encodedImage,
    )).encodedImage;
    try {
      try {
        wire.checkEncodedImage(response);
      } on FormatException {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid encoded image descriptor',
        );
      }
      if (response.generation != session.generation) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Encoded image generation mismatch',
        );
      }
      if (_disposed ||
          epoch != _epoch ||
          _session?.generation != session.generation) {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Discarded a stale encoded image',
        );
      }
      response.freeze();
      return response;
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

  bool _imageId(String value) => value.isNotEmpty && value.length <= 200;

  void _imageControlIdentity(String id, String generation) {
    if (!_imageId(id) || !_imageId(generation)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid image control identity',
      );
    }
  }

  void _requireImageGeneration(String generation) {
    if (_disposed || _session == null || _session?.generation != generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Image page belongs to an expired runtime',
      );
    }
  }

  wire.ImagePage _imagePage(String pageId, String generation) {
    _imageControlIdentity(pageId, generation);
    _requireImageGeneration(generation);
    final page = _imagePages[(generation, pageId)];
    if (page == null || _closingImagePages.contains((generation, pageId))) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Image page has closed',
      );
    }
    return page;
  }

  Future<void> _discardImagePage(wire.ImagePage page, String generation) async {
    if (!_imageId(page.pageId) ||
        _imagePages.containsKey((generation, page.pageId))) {
      return;
    }
    try {
      await closeImagePage(
        wire.CloseImagePage(pageId: page.pageId, generation: generation),
      );
    } on Object {
      // Preserve the rejected response error; cleanup never invalidates a newer generation.
    }
  }

  Future<void> _discardImageWindow(
    wire.ImageWindowSnapshot snapshot,
    String pageId,
    String generation,
  ) async {
    // A foreign page is not evidence that its leases belong to this request.
    if (snapshot.pageId != pageId) return;
    for (final id in snapshot.tiles.map((tile) => tile.leaseId).toSet()) {
      // Accepted leases may still be displayed, including those in a newer window.
      if (!_imageId(id) || _imageTileLeases.containsKey((generation, id))) {
        continue;
      }
      try {
        await releaseImageTile(
          wire.ReleaseImageTile(leaseId: id, generation: generation),
        );
      } on Object {
        // The original protocol/stale response error remains the failure to report.
      }
    }
  }

  Future<void> _cleanupRejectedTileControl(
    wire.ControlRequest request,
    wire.ControlResponse response,
  ) async {
    if (request.hasOpenImagePage() && response.hasImagePage()) {
      await _discardImagePage(
        response.imagePage,
        request.openImagePage.generation,
      );
    } else if (request.hasRequestImageWindow() && response.hasImageWindow()) {
      await _discardImageWindow(
        response.imageWindow,
        request.requestImageWindow.pageId,
        request.requestImageWindow.generation,
      );
    } else if (request.hasWaitImageWindow() && response.hasImageWindow()) {
      await _discardImageWindow(
        response.imageWindow,
        request.waitImageWindow.pageId,
        request.waitImageWindow.generation,
      );
    }
  }

  @override
  Future<wire.ImagePage> openImagePage(wire.OpenImagePage request) async {
    final input = request.deepCopy()..freeze();
    _imageControlIdentity(input.resourceId, input.generation);
    _requireImageGeneration(input.generation);
    final epoch = _epoch;
    final page = (await _exchange(
      wire.ControlRequest(openImagePage: input),
      wire.ControlResponse_Result.imagePage,
    )).imagePage;
    try {
      try {
        wire.checkImagePage(page);
      } on FormatException {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid image page descriptor',
        );
      }
      if (page.generation != input.generation ||
          page.encoded.resourceId != input.resourceId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Image page ownership mismatch',
        );
      }
      if (_disposed ||
          epoch != _epoch ||
          _session?.generation != input.generation) {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Discarded a stale image page',
        );
      }
      final key = (input.generation, page.pageId);
      final existing = _imagePages[key];
      if (existing != null) {
        if (existing != page || _closingImagePages.contains(key)) {
          throw const RuntimeException(
            RuntimeErrorCode.protocolError,
            'Image page changed an existing owner',
          );
        }
        return existing;
      }
      page.freeze();
      _imagePages[key] = page;
      return page;
    } catch (_) {
      await _discardImagePage(page, input.generation);
      rethrow;
    }
  }

  wire.ImageWindowSnapshot _acceptImageWindow(
    wire.ImageWindowSnapshot snapshot,
    wire.ImagePage page,
    _ImageWindowDemand window,
    int epoch,
    _ImageWindowObservation observation, {
    int afterRevision = 0,
  }) {
    final request = window.request;
    try {
      wire.checkImageWindow(
        snapshot,
        isManagedFile: (resource) {
          final location = Uri.tryParse(resource.url);
          return location != null &&
              transport is ManagedImageTransport &&
              (transport as ManagedImageTransport).ownsImageLocation(
                resource.resourceId,
                resource.generation,
                location,
              );
        },
      );
    } on FormatException {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid image window descriptor',
      );
    }
    if (snapshot.pageId != request.pageId ||
        snapshot.generation != request.generation ||
        snapshot.windowId != request.windowId ||
        snapshot.revision < afterRevision ||
        snapshot.revision < window.revision) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image window identity or revision mismatch',
      );
    }
    if (window.snapshot != null &&
        snapshot.revision == window.revision &&
        snapshot != window.snapshot) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image window changed without a revision',
      );
    }
    if (_disposed ||
        epoch != _epoch ||
        _session?.generation != request.generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Discarded a stale image window',
      );
    }
    if (!identical(_imagePages[(request.generation, request.pageId)], page) ||
        !identical(
          _imageWindows[(request.generation, request.pageId)],
          window,
        ) ||
        _closingImagePages.contains((request.generation, request.pageId))) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Image window was replaced or closed',
      );
    }
    if (snapshot.hasHeader() &&
        (snapshot.header.sourceWidth != page.encoded.rawWidth ||
            snapshot.header.sourceHeight != page.encoded.rawHeight ||
            snapshot.header.denominator != request.denominator)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image window changed its encoded page geometry',
      );
    }
    final additions = <wire.ImageTile>[];
    for (final tile in snapshot.tiles) {
      if (observation.excluded.contains((request.generation, tile.leaseId))) {
        throw const RuntimeException(
          RuntimeErrorCode.cancelled,
          'Image tile was released during this window observation',
        );
      }
      final rect = tile.sourceRect;
      if (rect.y >= request.sourceEndY ||
          rect.y + rect.height <= request.sourceY) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Image tile lies outside its requested window',
        );
      }
      final prior = _imageTileLeases[(request.generation, tile.leaseId)];
      if (prior == null) {
        additions.add(tile);
      } else if (prior.retiring ||
          prior.invalidated ||
          prior.pageId != request.pageId ||
          prior.epoch != epoch ||
          prior.tile.sessionId != tile.sessionId ||
          prior.tile.index != tile.index ||
          prior.tile.sourceRect != tile.sourceRect ||
          prior.tile.denominator != tile.denominator ||
          prior.tile.resource != tile.resource ||
          (!prior.tile.provisional && tile.provisional)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Image tile lease changed its resource',
        );
      }
    }
    for (final id in snapshot.invalidatedLeaseIds) {
      final prior = _imageTileLeases[(request.generation, id)];
      if (prior != null &&
          (prior.pageId != request.pageId || prior.epoch != epoch)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Image window invalidated a foreign tile',
        );
      }
    }
    final retained = _imageTileLeases.values.map((owner) => owner.tile);
    if (retained.length + additions.length > wire.imageTileCountLimit ||
        [...retained, ...additions].fold<int>(
              0,
              (sum, tile) => sum + tile.resource.width * tile.resource.height,
            ) >
            wire.imageTilePixelLimit ||
        [
              ...retained,
              ...additions,
            ].fold<int>(0, (sum, tile) => sum + tile.resource.byteLength) >
            wire.imageTileCacheByteLimit) {
      throw const RuntimeException(
        RuntimeErrorCode.limitExceeded,
        'Image display leases exceed their retained budget',
      );
    }
    snapshot.freeze();
    for (final tile in snapshot.tiles) {
      _imageTileLeases[(request.generation, tile.leaseId)] = _ImageTileOwner(
        request.pageId,
        epoch,
        tile,
      );
    }
    for (final id in snapshot.invalidatedLeaseIds) {
      _imageTileLeases[(request.generation, id)]?.invalidated = true;
    }
    window.revision = snapshot.revision;
    window.snapshot = snapshot;
    return snapshot;
  }

  _ImageWindowObservation _observeImageWindow() {
    final observation = _ImageWindowObservation(_imageTileReleases.keys);
    _imageWindowObservations.add(observation);
    return observation;
  }

  @override
  Future<wire.ImageWindowSnapshot> requestImageWindow(
    wire.RequestImageWindow request,
  ) async {
    final input = request.deepCopy()..freeze();
    final page = _imagePage(input.pageId, input.generation);
    if (!_imageId(input.windowId) ||
        input.sourceY < 0 ||
        input.sourceY >= input.sourceEndY ||
        input.sourceEndY > page.encoded.rawHeight ||
        !const [1, 2, 4].contains(input.denominator)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid raw image window',
      );
    }
    if (page.encoded.mimeType == 'image/png' && input.denominator != 1) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'PNG requires scale 1',
      );
    }
    final key = (input.generation, input.pageId);
    final previous = _imageWindows[key];
    final usedIds = _imageWindowIds.putIfAbsent(key, () => <String>{});
    if (previous?.request.windowId != input.windowId &&
        usedIds.contains(input.windowId)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'A replaced image window identity cannot be reused',
      );
    }
    if (previous?.request.windowId == input.windowId &&
        previous!.request != input) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image window identity was reused for different geometry',
      );
    }
    final window = previous?.request.windowId == input.windowId
        ? previous!
        : _ImageWindowDemand(input);
    _imageWindows[key] = window;
    usedIds.add(input.windowId);
    final epoch = _epoch;
    final observation = _observeImageWindow();
    wire.ImageWindowSnapshot? response;
    try {
      response = (await _exchange(
        wire.ControlRequest(requestImageWindow: input),
        wire.ControlResponse_Result.imageWindow,
      )).imageWindow;
      return _acceptImageWindow(response, page, window, epoch, observation);
    } catch (_) {
      if (response == null && identical(_imageWindows[key], window)) {
        // A rejected new demand did not replace the host's accepted window.
        // Do not roll back a newer concurrent request or an accepted response.
        if (previous == null) {
          _imageWindows.remove(key);
        } else {
          _imageWindows[key] = previous;
        }
        if (previous?.request.windowId != input.windowId) {
          usedIds.remove(input.windowId);
        }
      }
      if (response != null) {
        await _discardImageWindow(response, input.pageId, input.generation);
      }
      rethrow;
    } finally {
      _imageWindowObservations.remove(observation);
    }
  }

  @override
  Future<wire.ImageWindowSnapshot> waitImageWindow(
    wire.WaitImageWindow request,
  ) async {
    final input = request.deepCopy()..freeze();
    final page = _imagePage(input.pageId, input.generation);
    final window = _imageWindows[(input.generation, input.pageId)];
    if (window?.request.windowId != input.windowId &&
        (_imageWindowIds[(input.generation, input.pageId)]?.contains(
              input.windowId,
            ) ??
            false)) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Image window was replaced',
      );
    }
    if (!_imageId(input.windowId) ||
        window == null ||
        window.request.windowId != input.windowId ||
        input.afterRevision < 0 ||
        input.afterRevision > window.revision ||
        (input.hasTimeoutMs() &&
            (input.timeoutMs <= 0 ||
                input.timeoutMs > wire.imageWindowWaitLimitMs))) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid image window wait',
      );
    }
    final epoch = _epoch;
    final observation = _observeImageWindow();
    wire.ImageWindowSnapshot? response;
    try {
      response = (await _exchange(
        wire.ControlRequest(waitImageWindow: input),
        wire.ControlResponse_Result.imageWindow,
      )).imageWindow;
      return _acceptImageWindow(
        response,
        page,
        window,
        epoch,
        observation,
        afterRevision: input.afterRevision,
      );
    } catch (_) {
      if (response != null) {
        await _discardImageWindow(response, input.pageId, input.generation);
      }
      rethrow;
    } finally {
      _imageWindowObservations.remove(observation);
    }
  }

  @override
  Future<void> releaseImageTile(wire.ReleaseImageTile request) async {
    if (_disposed) return;
    final input = request.deepCopy()..freeze();
    _imageControlIdentity(input.leaseId, input.generation);
    final key = (input.generation, input.leaseId);
    final owner = _imageTileLeases[key];
    owner?.retiring = true;
    _imageTileReleases.update(key, (count) => count + 1, ifAbsent: () => 1);
    for (final observation in _imageWindowObservations) {
      observation.excluded.add(key);
    }
    try {
      _requireAck(
        (await _exchange(
          wire.ControlRequest(releaseImageTile: input),
          wire.ControlResponse_Result.released,
        )).released.released,
      );
      if (identical(_imageTileLeases[key], owner)) _imageTileLeases.remove(key);
    } finally {
      final count = _imageTileReleases[key] ?? 0;
      if (count <= 1) {
        _imageTileReleases.remove(key);
      } else {
        _imageTileReleases[key] = count - 1;
      }
    }
  }

  @override
  Future<void> closeImagePage(wire.CloseImagePage request) async {
    if (_disposed) return;
    final input = request.deepCopy()..freeze();
    _imageControlIdentity(input.pageId, input.generation);
    final key = (input.generation, input.pageId);
    final page = _imagePages[key];
    _closingImagePages.add(key);
    _requireAck(
      (await _exchange(
        wire.ControlRequest(closeImagePage: input),
        wire.ControlResponse_Result.closed,
      )).closed.closed,
    );
    if (identical(_imagePages[key], page)) {
      _imagePages.remove(key);
      _imageWindows.remove(key);
      _imageWindowIds.remove(key);
      _closingImagePages.remove(key);
    }
    // Display leases stay charged until releaseImageTile receives its own ACK.
  }

  @override
  Future<ImageResource> acquireImage(ImageAcquireRequest request) async {
    final session = _imageRequestSession(request);
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
      _imagePages.clear();
      _imageWindows.clear();
      _imageWindowIds.clear();
      _imageTileLeases.clear();
      _closingImagePages.clear();
      _imageWindowObservations.clear();
      _imageTileReleases.clear();
      await _events.close();
    }
  }
}
