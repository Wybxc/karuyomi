import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/native_runtime_assets.dart';
import 'package:source_runtime/source_runtime.dart';

final class MemoryAssets extends CachingAssetBundle {
  MemoryAssets(this.files);
  final Map<String, List<int>> files;
  final List<String> requests = [];

  @override
  Future<ByteData> load(String key) async {
    requests.add(key);
    final bytes = files[key];
    if (bytes == null) throw StateError('Missing fixture asset');
    // AssetBundle data can be a view into a larger backing buffer.
    final storage = Uint8List.fromList([1, 2, ...bytes, 3]);
    return ByteData.sublistView(storage, 2, storage.length - 1);
  }
}

void main() {
  late Map<String, Object?> manifest;
  late MemoryAssets bundle;
  const directory = NativeRuntimeAssets.assetDirectory;

  setUp(() {
    final host = utf8.encode(
      'window.karuyomiRuntime = Object.freeze({ready: Promise.resolve({})});',
    );
    final worker = utf8.encode('self.fixture = "Unicode 中文 and \\n";');
    Map<String, Object?> metadata(String name, List<int> bytes) => {
      'path': '$name.js',
      'sha256': sha256.convert(bytes).toString(),
      'size': bytes.length,
    };
    manifest = {
      'schemaVersion': 1,
      'protocolVersion': protocolVersion,
      'hostAbi': hostAbi,
      'runtimeBaseline': runtimeBaseline,
      'materialVersion': 'a' * 64,
      'files': {
        'host': metadata('host', host),
        'worker': metadata('worker', worker),
      },
    };
    bundle = MemoryAssets({
      '${directory}host.js': host,
      '${directory}worker.js': worker,
    });
  });

  Future<NativeRuntimeAssets> load() {
    bundle.files['${directory}manifest.json'] = utf8.encode(
      jsonEncode(manifest),
    );
    return NativeRuntimeAssets.load(bundle: bundle);
  }

  test('verified installed files load from offset asset views without material downloads', () async {
    final assets = await load();
    expect(assets.workerSource, contains('中文'));
    expect(assets.materialVersion, 'a' * 64);
    expect(bundle.requests, [
      '${directory}manifest.json',
      '${directory}host.js',
      '${directory}worker.js',
    ]);
  });

  test('same-length corruption fails before any script can execute', () async {
    final bytes = List<int>.from(bundle.files['${directory}worker.js']!);
    bytes[0] ^= 1;
    bundle.files['${directory}worker.js'] = bytes;
    await expectLater(
      load(),
      throwsA(
        isA<RuntimeException>().having(
          (error) => error.code,
          'code',
          RuntimeErrorCode.runtimeLost,
        ),
      ),
    );
  });

  test('truncated installed code fails its declared length', () async {
    bundle.files['${directory}host.js'] = [1, 2, 3];
    await expectLater(load(), throwsA(isA<RuntimeException>()));
  });

  test(
    'missing installed code fails explicitly without a remote fallback',
    () async {
      bundle.files.remove('${directory}worker.js');
      await expectLater(
        load(),
        throwsA(
          isA<RuntimeException>().having(
            (error) => error.code,
            'code',
            RuntimeErrorCode.runtimeLost,
          ),
        ),
      );
    },
  );

  test('protocol, ABI, baseline and material identity drift require a compatible app', () async {
    for (final entry in {
      'protocolVersion': 999,
      'hostAbi': 'unknown-host',
      'runtimeBaseline': 'unknown-baseline',
      'materialVersion': '../invalid-materials',
    }.entries) {
      final original = manifest[entry.key];
      manifest[entry.key] = entry.value;
      await expectLater(
        load(),
        throwsA(
          isA<RuntimeException>().having(
            (error) => error.code,
            'code',
            RuntimeErrorCode.unsupportedCapability,
          ),
        ),
      );
      manifest[entry.key] = original;
    }
    expect(
      bundle.requests.every((path) => path.endsWith('manifest.json')),
      isTrue,
    );
  });

  test(
    'manifest cannot choose an arbitrary app asset or oversized script',
    () async {
      final host = (manifest['files'] as Map)['host'] as Map;
      host['path'] = '../private.js';
      await expectLater(load(), throwsA(isA<RuntimeException>()));
      host['path'] = 'host.js';
      host['size'] = 8 * 1024 * 1024 + 1;
      await expectLater(load(), throwsA(isA<RuntimeException>()));
      expect(
        bundle.requests.every((path) => path.endsWith('manifest.json')),
        isTrue,
      );
    },
  );

  test('injection cannot be configured for a file origin or credential-bearing URL', () async {
    final assets = await load();
    for (final value in [
      'file:///runtime/host.html',
      'http://example.com',
      'https://user:password@example.com',
      'https://example.com/other',
      'https://example.com/?query=1',
      'https://example.com/#fragment',
    ]) {
      expect(
        () => assets.documentStartScript(Uri.parse(value)),
        throwsArgumentError,
      );
    }
  });

  test('managed file capability and binding token are explicitly opted in together', () async {
    final assets = await load();
    final ordinary = assets.documentStartScript(
      Uri.parse('https://reader.example'),
    );
    expect(ordinary, contains('imageFiles: false'));
    expect(ordinary, isNot(contains('__karuyomiNativeImageToken')));
    final managed = assets.documentStartScript(
      Uri.parse('https://reader.example'),
      imageFileToken: 'native-token',
    );
    expect(managed, contains('imageFiles: true'));
    expect(
      managed,
      contains("Object.defineProperty(window, '__karuyomiNativeImageToken'"),
    );
    expect(managed, contains('location.origin !== "https://reader.example"'));
    expect(managed, contains("['/runtime/host.html', '/runtime/host']"));
  });
}
