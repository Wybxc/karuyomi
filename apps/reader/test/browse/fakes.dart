import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

const sourceId = '9223372036854775806';
wire.Manga get testManga => wire.Manga(
  url: '/manga/opaque-source-ref',
  title: '真实源 DTO 测试',
  author: '作者',
  thumbnailUrl: 'https://private-image.invalid/never-loaded',
  genre: '冒险',
  genres: ['冒险'],
);

final class TestPlatform extends PlatformRuntime {
  TestPlatform({Uri? origin, this.bootstrapSubject = 'owner-subject'})
    : _origin = origin ?? Uri.parse('https://reader.example.com');
  final Uri _origin;
  final String bootstrapSubject;
  int disposalCount = 0;
  @override
  Uri get origin => _origin;

  int bootstrapStatus = 200;
  bool loginHtml = false;
  Object? inventory = wire.encodeProtoJson(
    wire.ExtensionIndex(
      schemaVersion: 1,
      builds: [
        wire.ExtensionBuildDescriptor(
          buildId: 'build-1',
          packageName: 'source.test',
          version: '1.0',
          manifestPath: '/extensions/builds/build-1/manifest.json',
        ),
      ],
    ),
  );
  int authCalls = 0;
  final invocations = <wire.SourceCall>[];
  final imageControls = <(String, Map<String, Object?>)>[];
  final controlCommands = <wire.ControlRequest_Command>[];
  Map<String, Object?>? continuation;
  Future<wire.SourceResult> Function(wire.SourceCall call)? invokeHandler;
  Future<void> Function(String pageSessionId)? closePageSessionHandler;
  bool closeAcknowledged = true;

  wire.ApiFetchResponse _fetch(String path) {
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
      '/extensions/builds/build-1/manifest.json' => wire.encodeProtoJson(
        wire.BuildManifest(
          buildId: 'build-1',
          bundle: wire.BundleArtifact(sha256: 'a' * 64),
        ),
      ),
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
        response.api = _fetch(request.fetchApi.path);
      case wire.ControlRequest_Command.ready:
        response.hello = wire.RuntimeHello(
          protocolVersion: protocolVersion,
          hostAbi: hostAbi,
          runtimeBaseline: runtimeBaseline,
        );
      case wire.ControlRequest_Command.open:
        response.session = wire.RuntimeSession(
          protocolVersion: protocolVersion,
          workerInstanceId: 'worker-1',
          generation: 'generation-1',
          buildId: 'build-1',
          sources: [
            wire.SourceInfo(
              id: sourceId,
              name: '测试漫画源',
              lang: 'zh',
              supportsLatest: true,
            ),
          ],
          capabilities: ['source-rpc'],
        );
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
          ..generation = 'generation-1'
          ..buildId = 'build-1';
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
    return true;
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final value = continuation;
    continuation = null;
    return value;
  }

  @override
  Future<void> rebuild() async =>
      runtime.containerLost('Rebuilt test container');
  @override
  Future<void> dispose() {
    disposalCount++;
    return runtime.dispose();
  }
}
