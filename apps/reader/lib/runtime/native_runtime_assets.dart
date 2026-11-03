import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:source_runtime/source_runtime.dart';

/// Installed app code, separate from authenticated extension AOT downloads.
final class NativeRuntimeAssets {
  NativeRuntimeAssets._(
    this.hostSource,
    this.workerSource,
    this.materialVersion,
  );

  static const assetDirectory = 'assets/runtime/';
  static const _maxScriptBytes = 8 * 1024 * 1024;
  static final _digest = RegExp(r'^[a-f0-9]{64}$');

  final String hostSource;
  final String workerSource;
  final String materialVersion;

  static Future<NativeRuntimeAssets> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    try {
      final data = await assets.load('${assetDirectory}manifest.json');
      if (data.lengthInBytes > 64 * 1024) {
        throw const FormatException('Native runtime manifest is too large');
      }
      final manifest = jsonDecode(
        utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
      if (manifest is! Map<String, dynamic> ||
          manifest['schemaVersion'] != 1 ||
          manifest['protocolVersion'] != protocolVersion ||
          manifest['hostAbi'] != hostAbi ||
          manifest['runtimeBaseline'] != runtimeBaseline ||
          manifest['materialVersion'] is! String ||
          !_digest.hasMatch(manifest['materialVersion'] as String)) {
        throw const RuntimeException(
          RuntimeErrorCode.unsupportedCapability,
          'The installed Native runtime has an incompatible protocol or ABI',
        );
      }
      final files = manifest['files'];
      if (files is! Map<String, dynamic>) {
        throw const FormatException('Native runtime files are missing');
      }
      Future<String> readScript(String name) async {
        final file = files[name];
        if (file is! Map<String, dynamic> ||
            file['path'] != '$name.js' ||
            file['sha256'] is! String ||
            !_digest.hasMatch(file['sha256'] as String) ||
            file['size'] is! int ||
            (file['size'] as int) <= 0 ||
            (file['size'] as int) > _maxScriptBytes) {
          throw const FormatException(
            'Native runtime file metadata is invalid',
          );
        }
        final data = await assets.load('$assetDirectory$name.js');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.length != file['size'] ||
            sha256.convert(bytes).toString() != file['sha256']) {
          throw const FormatException('Native runtime file integrity failed');
        }
        return utf8.decode(bytes);
      }

      final host = await readScript('host');
      final worker = await readScript('worker');
      return NativeRuntimeAssets._(
        host,
        worker,
        manifest['materialVersion'] as String,
      );
    } on RuntimeException {
      rethrow;
    } catch (_) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'The installed Native runtime assets are missing or corrupt; rebuild the app',
      );
    }
  }

  /// iOS 6.1.5 does not enforce allowedOriginRules for WKUserScript. Keep the
  /// origin/frame/path checks in the script as well as the native navigation gate.
  String documentStartScript(Uri origin, {String? imageFileToken}) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError(
        'Native runtime injection requires a deployment HTTPS origin',
      );
    }
    return '''
(() => {
  if (window !== window.top || location.origin !== ${jsonEncode(origin.origin)} ||
      !['/runtime/host.html', '/runtime/host'].includes(location.pathname) || location.search || location.hash) return;
  if (window.karuyomiRuntime || window.__karuyomiNativeRuntime) return;
  ${imageFileToken == null ? '' : "Object.defineProperty(window, '__karuyomiNativeImageToken', {value: ${jsonEncode(imageFileToken)}});"}
  Object.defineProperty(window, '__karuyomiNativeRuntime', {configurable: true, value: Object.freeze({
    workerSource: ${jsonEncode(workerSource)}, materialVersion: ${jsonEncode(materialVersion)}, imageFiles: ${imageFileToken != null}
  })});
$hostSource
  if (!window.karuyomiRuntime) throw new Error('Bundled Native runtime did not install');
  Object.defineProperty(window, '__karuyomiNativeRuntimeInstalled', {value: Object.freeze({
    materialVersion: ${jsonEncode(materialVersion)}, runtime: window.karuyomiRuntime
  })});
})();
''';
  }
}
