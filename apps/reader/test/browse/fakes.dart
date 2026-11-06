import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/runtime/catalog_transport.dart';
import 'package:karuyomi/runtime/cover_transport.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';

const sourceId = '9223372036854775806';
wire.CatalogSource get testCatalogSource =>
    wire.CatalogSource(id: sourceId, name: '测试漫画源', lang: 'zh');
wire.InstalledExtension testInstalledExtension({
  String catalogUrl = 'https://reader.example.com/extensions/index.json',
  String packageName = 'eu.kanade.source.test',
  String buildId = 'build-1',
  String repoId = 'keiyoushi',
  String? sha256,
  bool enabled = true,
}) => wire.InstalledExtension(
  catalogUrl: catalogUrl,
  repoId: repoId,
  packageName: packageName,
  buildId: buildId,
  bundleSha256: sha256 ?? 'a' * 64,
  enabled: enabled,
);

wire.Manga get testManga => wire.Manga(
  url: '/manga/opaque-source-ref',
  title: '真实源 DTO 测试',
  author: '作者',
  thumbnailUrl: 'https://private-image.invalid/never-loaded',
  genre: '冒险',
  genres: ['冒险'],
);

final class TestPlatform extends PlatformRuntime {
  TestPlatform({
    Uri? origin,
    this.bootstrapSubject = 'owner-subject',
    TestBusinessServer? businessServer,
    bool seedDefaultInstallation = true,
  }) : _origin = origin ?? Uri.parse('https://reader.example.com'),
       businessServer = businessServer ?? TestBusinessServer() {
    if (seedDefaultInstallation) {
      this.businessServer.seedInstalledExtensions([
        testInstalledExtension(
          catalogUrl: '${_origin.origin}/extensions/index.json',
        ),
      ], subject: bootstrapSubject);
    }
  }
  final Uri _origin;
  final TestBusinessServer businessServer;
  @override
  late final CatalogTransport catalogTransport = _TestCatalogTransport(this);
  final publicDocuments = <String, Object?>{};
  final publicReads = <Uri>[];
  final policyDocuments = <String, wire.ExtensionNetworkPoliciesResponse>{};
  CoverTransport? covers;
  @override
  CoverTransport? get coverTransport => covers;
  String bootstrapSubject;
  int disposalCount = 0;
  int rebuildCount = 0;
  Future<void> Function(String path)? beforeApiFetch;
  FutureOr<ApiReply> Function(TestBusinessRequest request, ApiReply reply)?
  afterBusinessReply;
  Future<void> Function()? beforeRebuild;
  final openedIdentities = <String>[];
  final openedBuilds = <String>[];
  final preferenceBootstraps = <wire.PreferenceBootstrap>[];
  String manifestBuildId = 'build-1';
  wire.BuildManifest? manifestOverride;
  String _openedBuildId = 'build-1';
  List<wire.SourceInfo>? sourceInventory;
  @override
  Uri get origin => _origin;

  int bootstrapStatus = 200;
  bool loginHtml = false;
  Object? inventory = wire.encodeProtoJson(
    wire.ExtensionIndex(
      schemaVersion: 1,
      repoId: 'keiyoushi',
      builds: [
        wire.ExtensionBuildDescriptor(
          buildId: 'build-1',
          packageName: 'eu.kanade.source.test',
          repoId: 'keiyoushi',
          sourceIds: [sourceId],
          sources: [testCatalogSource],
          version: '1.0',
          manifestPath: '/extensions/builds/build-1/manifest.json',
        ),
      ],
    ),
  );
  int authCalls = 0;
  String runtimeGeneration = 'generation-1';
  Future<bool> Function()? authenticateHandler;
  final invocations = <wire.SourceCall>[];
  final imageControls = <(String, Map<String, Object?>)>[];
  final controlCommands = <wire.ControlRequest_Command>[];
  Map<String, Object?>? continuation;
  Future<wire.SourceResult> Function(wire.SourceCall call)? invokeHandler;
  Future<void> Function(String pageSessionId)? closePageSessionHandler;
  bool closeAcknowledged = true;

  final cachedArtifacts = <String, wire.CachedExtensionArtifact>{};
  final preparations = <wire.PrepareBuildRequest>[];
  final buildClosures = <wire.CloseBuildRequest>[];
  Future<void> Function(wire.PrepareBuildRequest)? beforePrepare;
  wire.RuntimeError? preparationFailure;
  final _cancelledPreparations = <String>{};
  String? _liveBuild;

  void seedInstalledBuilds(Iterable<wire.ExtensionBuildDescriptor> builds) {
    businessServer.seedInstalledExtensions(
      builds.map(
        (build) => testInstalledExtension(
          catalogUrl: '${origin.origin}/extensions/index.json',
          packageName: build.packageName,
          buildId: build.buildId,
          repoId: build.repoId,
        ),
      ),
      subject: bootstrapSubject,
      advanceRevision: true,
    );
  }

  wire.BuildManifest _currentManifest() {
    final index = wire.decodeProtoJson(wire.ExtensionIndex(), inventory);
    final build = index.builds.singleWhere(
      (build) => build.buildId == manifestBuildId,
    );
    return wire.BuildManifest(
      buildId: build.buildId,
      packageName: build.packageName,
      repoId: build.repoId,
      version: build.version,
      sourceIds: build.sourceIds,
      sources: build.sources.map((source) => source.deepCopy()),
      bundle: wire.BundleArtifact(sha256: 'a' * 64),
    );
  }

  wire.ApiFetchResponse _fetch(String path) {
    final uri = Uri.parse(path);
    if (uri.path == '/api/extensions/network-policies') {
      final url = uri.queryParameters['catalogUrl']!;
      final repo = uri.queryParameters['repoId']!;
      final index = wire.decodeProtoJson(wire.ExtensionIndex(), inventory);
      final value =
          policyDocuments[url] ??
          wire.ExtensionNetworkPoliciesResponse(
            schemaVersion: 1,
            catalog: wire.CatalogReference(catalogUrl: url, repoId: repo),
            builds:
                url == '${origin.origin}/extensions/index.json' &&
                    repo == index.repoId
                ? index.builds.map(
                    (build) => wire.ExtensionNetworkPolicy(
                      buildId: build.buildId,
                      packageName: build.packageName,
                      bundleSha256: 'a' * 64,
                    ),
                  )
                : const <wire.ExtensionNetworkPolicy>[],
          );
      return wire.ApiFetchResponse(
        status: 200,
        headers: {'content-type': 'application/json'}.entries,
        body: jsonEncode(wire.encodeProtoJson(value)),
      );
    }
    final response = switch (path) {
      '/api/bootstrap' => wire.encodeProtoJson(
        wire.Bootstrap(
          protocolVersion: protocolVersion,
          identity: wire.Identity(
            subject: bootstrapSubject,
            email: 'owner@example.com',
          ),
          expiresAt: 2000000000,
          stage: wire.BootstrapStage.BOOTSTRAP_STAGE_P0,
        ),
      ),
      '/extensions/index.json' => inventory,
      final String value
          when value == '/extensions/builds/$manifestBuildId/manifest.json' =>
        wire.encodeProtoJson(manifestOverride ?? _currentManifest()),
      _ => throw StateError('Unexpected API path $path'),
    };
    return wire.ApiFetchResponse(
      status: path == '/api/bootstrap' ? bootstrapStatus : 200,
      headers: {
        'content-type': loginHtml ? 'text/html' : 'application/json',
      }.entries,
      body: loginHtml ? '<html>login</html>' : jsonEncode(response),
    );
  }

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    controlCommands.add(request.whichCommand());
    final response = wire.ControlResponse(requestId: request.requestId);
    switch (request.whichCommand()) {
      case wire.ControlRequest_Command.fetchApi:
        await beforeApiFetch?.call(request.fetchApi.path);
        if (request.fetchApi.path.startsWith('/api/library') ||
            request.fetchApi.path.startsWith('/api/categories') ||
            request.fetchApi.path.startsWith('/api/settings') ||
            request.fetchApi.path.startsWith('/api/source-preferences/') ||
            request.fetchApi.path.startsWith('/api/state/')) {
          final businessRequest = TestBusinessRequest(
            path: request.fetchApi.path,
            method: request.fetchApi.method,
            headers: request.fetchApi.headers,
            body: request.fetchApi.hasBody() ? request.fetchApi.body : null,
          );
          final serverReply = await businessServer.handle(
            businessRequest,
            subject: bootstrapSubject,
          );
          final reply =
              await afterBusinessReply?.call(businessRequest, serverReply) ??
              serverReply;
          response.api = wire.ApiFetchResponse(
            status: reply.status,
            headers: reply.headers.entries,
            body: reply.body,
            redirected: reply.redirected,
          );
        } else {
          response.api = _fetch(request.fetchApi.path);
        }
      case wire.ControlRequest_Command.ready:
        response.hello = wire.RuntimeHello(
          protocolVersion: protocolVersion,
          hostAbi: hostAbi,
          runtimeBaseline: runtimeBaseline,
        );
      case wire.ControlRequest_Command.open:
        openedIdentities.add(request.open.identity);
        preferenceBootstraps.add(request.open.preferenceBootstrap.deepCopy());
        openedBuilds.add(request.open.expectedBuildId);
        _openedBuildId = request.open.expectedBuildId;
        _liveBuild = _openedBuildId;
        response.session = wire.RuntimeSession(
          protocolVersion: protocolVersion,
          catalog: request.open.catalog.deepCopy(),
          workerInstanceId: 'worker-1',
          generation: runtimeGeneration,
          buildId: _openedBuildId,
          sources:
              sourceInventory ??
              [
                wire.SourceInfo(
                  id: sourceId,
                  name: '测试漫画源',
                  lang: 'zh',
                  supportsLatest: true,
                ),
              ],
          capabilities: ['source-rpc'],
        );
      case wire.ControlRequest_Command.prepareBuild:
        final prepare = request.prepareBuild.deepCopy()..freeze();
        preparations.add(prepare);
        await beforePrepare?.call(prepare);
        if (_cancelledPreparations.contains(prepare.preparationId)) {
          response.error = wire.RuntimeError(
            code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_CANCELLED,
            message: 'Preparation cancelled',
          );
        } else if (preparationFailure != null) {
          response.error = preparationFailure!.deepCopy();
        } else {
          cachedArtifacts['a' * 64] = wire.CachedExtensionArtifact(
            sha256: 'a' * 64,
            byteLength: 256,
            contentType: 'application/javascript',
          );
          response.preparedBuild = wire.PreparedBuild(
            catalog: prepare.catalog.deepCopy(),
            build: prepare.build.deepCopy(),
            bundleSha256: 'a' * 64,
            byteLength: 256,
          );
        }
      case wire.ControlRequest_Command.cancelPreparation:
        _cancelledPreparations.add(request.cancelPreparation.preparationId);
        response.completed = wire.Completed(completed: true);
      case wire.ControlRequest_Command.extensionCache:
        response.extensionCache = wire.ExtensionCacheState(
          artifacts: cachedArtifacts.values.map(
            (artifact) => artifact.deepCopy(),
          ),
          totalBytes: cachedArtifacts.values.fold<int>(
            0,
            (sum, artifact) => sum + artifact.byteLength,
          ),
          maxBytes: 256 * 1024 * 1024,
          maxArtifacts: 128,
        );
      case wire.ControlRequest_Command.forgetExtensionArtifact:
        cachedArtifacts.remove(request.forgetExtensionArtifact.sha256);
        response.completed = wire.Completed(completed: true);
      case wire.ControlRequest_Command.closeBuild:
        buildClosures.add(request.closeBuild.deepCopy()..freeze());
        if (_liveBuild == request.closeBuild.buildId &&
            runtimeGeneration == request.closeBuild.generation) {
          _liveBuild = null;
        }
        response.closed = wire.Closed(closed: closeAcknowledged);
      case wire.ControlRequest_Command.invoke:
        final call = request.invoke;
        invocations.add(call.deepCopy()..freeze());
        final result = invokeHandler == null
            ? switch (call.whichRequest()) {
                wire.SourceCall_Request.details => wire.SourceResult(
                  manga: testManga
                    ..description = '漫画源返回的完整简介'
                    ..initialized = true,
                ),
                wire.SourceCall_Request.chapters => wire.SourceResult(
                  chapters: wire.ChapterList(
                    chapters: [
                      wire.Chapter(
                        url: '/chapter/opaque-ref',
                        name: '第 1 章',
                        dateUpload: '0',
                      ),
                    ],
                  ),
                ),
                wire.SourceCall_Request.pages => wire.SourceResult(
                  pageList: wire.PageList(
                    pageSessionId: 'pages-1',
                    pages: [
                      wire.Page(
                        pageKey: 'p-0',
                        index: 0,
                        sourceIndex: 7,
                        url: '/page/stable-1',
                        imageUrl: 'https://source.invalid/raw-1.png',
                      ),
                    ],
                  ),
                ),
                _ => wire.SourceResult(
                  mangaPage: wire.MangaPage(mangas: [testManga]),
                ),
              }
            : await invokeHandler!(call);
        response.source = result.deepCopy()
          ..requestId = call.requestId
          ..generation = call.generation
          ..buildId = _openedBuildId;
      case wire.ControlRequest_Command.acquireImage:
        imageControls.add((
          'acquireImage',
          wire.encodeProtoJson(request.acquireImage),
        ));
        response.error = wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY,
          message: 'Test platform has no native image file channel',
        );
      case wire.ControlRequest_Command.cancelImage:
        imageControls.add((
          'cancelImage',
          wire.encodeProtoJson(request.cancelImage),
        ));
        response.released = wire.Released(released: true);
      case wire.ControlRequest_Command.releaseImage:
        imageControls.add((
          'releaseImage',
          wire.encodeProtoJson(request.releaseImage),
        ));
        response.released = wire.Released(released: true);
      case wire.ControlRequest_Command.closePageSession:
        await closePageSessionHandler?.call(
          request.closePageSession.pageSessionId,
        );
        imageControls.add((
          'closePageSession',
          wire.encodeProtoJson(request.closePageSession),
        ));
        response.closed = wire.Closed(closed: closeAcknowledged);
      default:
        response.completed = wire.Completed(completed: true);
    }
    return wire.encodeProtoJson(response, maxBytes: wire.controlJsonLimit);
  }

  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async {
    ++authCalls;
    bootstrapStatus = 200;
    continuation = {'returnTo': returnTo, 'pending': pending};
    return authenticateHandler == null ? true : await authenticateHandler!();
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final value = continuation;
    continuation = null;
    return value;
  }

  @override
  Future<void> rebuild() async {
    rebuildCount++;
    runtime.containerLost('Rebuilt test container');
    await beforeRebuild?.call();
  }

  @override
  Future<void> dispose() {
    disposalCount++;
    catalogTransport.close();
    return runtime.dispose();
  }
}

final class _TestCatalogTransport implements CatalogTransport {
  _TestCatalogTransport(this.platform);
  final TestPlatform platform;
  @override
  Future<Object?> read(
    Uri uri, {
    bool Function()? shouldContinue,
    Future<void>? cancelled,
  }) async {
    if (shouldContinue?.call() == false) {
      throw StateError('Cancelled public read');
    }
    platform.publicReads.add(uri);
    await platform.beforeApiFetch?.call(uri.path);
    if (shouldContinue?.call() == false) {
      throw StateError('Cancelled public read');
    }
    if (platform.publicDocuments.containsKey(uri.toString())) {
      return platform.publicDocuments[uri.toString()];
    }
    if (uri.origin != platform.origin.origin) {
      throw StateError('Unknown public repository');
    }
    final value = platform._fetch(uri.path);
    if (value.status != 200 ||
        !Map.fromEntries(
          value.headers.entries,
        ).values.contains('application/json')) {
      throw const FormatException('Public repository is unavailable');
    }
    return jsonDecode(value.body);
  }

  @override
  void close() {}
}
