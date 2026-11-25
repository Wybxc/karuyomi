import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'device_source_preferences_native.dart'
    if (dart.library.js_interop) 'device_source_preferences_web.dart';
import 'reading_progress.dart';
import 'source_preferences_validation.dart';

/// Stores the Source's confirmed local values without using the business API.
final class DeviceSourcePreferences(this.identity) {
  final ProgressIdentity identity;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    webOptions: WebOptions(publicKey: 'KaruyomiSourcePreferences'),
  );
  static const _recordLimit = wire.preferenceValuesLimit + 128;

  String _key(
    wire.CatalogReference catalog,
    String packageName,
    String sourceId,
  ) {
    final digest = sha256.convert(
      utf8.encode(
        jsonEncode([
          identity.key,
          catalog.catalogUrl,
          catalog.repoId,
          packageName,
          sourceId,
        ]),
      ),
    );
    return 'source-preferences:$digest';
  }

  Future<List<wire.PreferenceEntry>> load({
    required wire.CatalogReference catalog,
    required String packageName,
    required String sourceId,
  }) async {
    try {
      final value = await _storage.read(
        key: _key(catalog, packageName, sourceId),
      );
      if (value == null) return const [];
      if (value.length > _recordLimit) {
        throw const FormatException('Device preference record exceeds budget');
      }
      final stored = wire.decodeProtoJson(
        wire.SourcePreferenceValues(),
        jsonDecode(value),
        maxBytes: _recordLimit,
      );
      if (stored.sourceId != sourceId) {
        throw const FormatException('Device preference Source mismatch');
      }
      wire.validatePreferenceEntries(stored.entries);
      return stored.entries;
    } catch (_) {
      // Storage and decoder failures can include the saved value.
      throw const FormatException('无法读取本机保存的漫画源设置。');
    }
  }

  Future<void> save({
    required wire.CatalogReference catalog,
    required String packageName,
    required String sourceId,
    required List<wire.PreferenceEntry> entries,
  }) async {
    wire.validatePreferenceEntries(entries);
    final key = _key(catalog, packageName, sourceId);
    final value = entries.isEmpty
        ? null
        : jsonEncode(
            wire.encodeProtoJson(
              wire.SourcePreferenceValues(
                sourceId: sourceId,
                entries: canonicalPreferenceEntries(entries),
              ),
              maxBytes: _recordLimit,
            ),
          );
    try {
      await writeDeviceSourcePreferences(_storage, key, value);
    } catch (_) {
      throw const FormatException('无法在本机保存漫画源设置。请重新打开设置后重试。');
    }
  }
}
