import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/source_runtime.dart';

const sourceId = '9223372036854775806';
const testManga = <String, Object?>{
  'url': '/manga/opaque-source-ref',
  'title': '真实源 DTO 测试',
  'author': '作者',
  'thumbnailUrl': 'https://private-image.invalid/never-loaded',
  'genre': '冒险',
  'genres': ['冒险'],
  'initialized': false,
};

final class TestPlatform extends PlatformRuntime {
  @override
  Uri get origin => Uri.parse('https://reader.example.com');

  int bootstrapStatus = 200;
  bool loginHtml = false;
  Object? inventory = {
    'builds': [
      {
        'buildId': 'build-1',
        'packageName': 'source.test',
        'version': '1.0',
        'manifestPath': '/api/extensions/builds/build-1/manifest',
      },
    ],
    'nextCursor': null,
  };
  int authCalls = 0;
  final invocations = <Map<String, Object?>>[];
  Map<String, Object?>? continuation;
  Future<Object?> Function(Map<String, Object?> payload)? invokeHandler;

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final response = switch (path) {
      '/api/bootstrap' => {
        'protocolVersion': protocolVersion,
        'identity': {'subject': 'owner-subject', 'email': 'owner@example.com'},
      },
      '/api/extensions/builds' => inventory,
      '/api/extensions/builds/build-1/manifest' => {
        'buildId': 'build-1',
        'bundle': {'sha256': 'a' * 64},
      },
      _ => throw StateError('Unexpected API path $path'),
    };
    return ApiReply(
      status: path == '/api/bootstrap' ? bootstrapStatus : 200,
      headers: {'content-type': loginHtml ? 'text/html' : 'application/json'},
      body: loginHtml ? '<html>login</html>' : jsonEncode(response),
      redirected: false,
    );
  }

  @override
  Future<Object?> call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    switch (method) {
      case 'ready':
        return {
          'protocolVersion': protocolVersion,
          'hostAbi': hostAbi,
          'runtimeBaseline': runtimeBaseline,
        };
      case 'open':
        return {
          'protocolVersion': protocolVersion,
          'workerInstanceId': 'worker-1',
          'generation': 'generation-1',
          'buildId': 'build-1',
          'sources': [
            {
              'id': sourceId,
              'name': '测试漫画源',
              'lang': 'zh',
              'supportsLatest': true,
            },
          ],
          'capabilities': ['source-rpc'],
        };
      case 'invoke':
        invocations.add(payload);
        final Object? data;
        if (invokeHandler != null) {
          data = await invokeHandler!(payload);
        } else {
          data = switch (payload['operation']) {
            'details' => {
              ...testManga,
              'description': '漫画源返回的完整简介',
              'initialized': true,
            },
            'chapters' => {
              'chapters': [
                {'url': '/chapter/opaque-ref', 'name': '第 1 章'},
              ],
            },
            _ => {
              'mangas': [testManga],
              'hasNextPage': false,
            },
          };
        }
        return {
          'requestId': payload['requestId'],
          'generation': 'generation-1',
          'buildId': 'build-1',
          'data': data,
        };
      default:
        return null;
    }
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
  Future<void> dispose() => runtime.dispose();
}
