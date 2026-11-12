import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'reading_progress.dart';

/// A confirmed online snapshot. Missing override fields mean inheritance;
/// an explicit AUTO layout remains present in [overrides].
final class SettingsSnapshot._(wire.SettingsResponse value) {
  final int accountRevision = value.accountRevision;
  final int globalRevision = value.global.revision;
  final wire.GlobalSettingsValues global = value.global.values.deepCopy()
    ..freeze();
  final String? mangaKey = value.hasManga() ? value.manga.mangaKey : null;
  final int? mangaRevision = value.hasManga() ? value.manga.revision : null;
  final wire.ReaderSettingsOverride? overrides = value.hasManga()
      ? (value.manga.overrides.deepCopy()..freeze())
      : null;
  final wire.ReaderSettings effectiveReader = value.effectiveReader.deepCopy()
    ..freeze();
}

/// Frozen submitted values. Retrying this exact draft retains its UUID/CAS.
final class SettingsDraft._(wire.SettingsMutation value, final bool retryable) {
  final String? mangaKey = value.hasSetManga() ? value.setManga.mangaKey : null;
  final wire.GlobalSettingsValues? global = value.hasSetGlobal()
      ? (value.setGlobal.deepCopy()..freeze())
      : null;
  final wire.ReaderSettingsOverride? overrides = value.hasSetManga()
      ? (value.setManga.overrides.deepCopy()..freeze())
      : null;
  final int basedOnRevision = value.expectedRevision;
}

final class SettingsRepository(final BusinessStateClient client) {
  ProgressIdentity get identity => client.identity;

  Stream<SettingsSnapshot> watchConfirmed() =>
      client.watchSettings().map(SettingsSnapshot._);

  SettingsDraft? pendingGlobal() => _pending();
  SettingsDraft? pendingManga(String mangaKey) => _pending(mangaKey: mangaKey);
  SettingsDraft? _pending({String? mangaKey}) {
    final value = client.pendingSettings(mangaKey: mangaKey);
    return value == null
        ? null
        : SettingsDraft._(value.request, value.retryable);
  }

  Future<SettingsSnapshot> loadGlobal() async =>
      SettingsSnapshot._(await client.readSettings());
  Future<SettingsSnapshot> loadManga(String mangaKey) async =>
      SettingsSnapshot._(await client.readSettings(mangaKey: mangaKey));

  Future<SettingsSnapshot> setGlobal({
    required wire.GlobalSettingsValues values,
    required int basedOnRevision,
  }) async => SettingsSnapshot._(
    await client.mutateSettings(
      wire.SettingsMutation(
        expectedRevision: basedOnRevision,
        setGlobal: values,
      ),
    ),
  );

  Future<SettingsSnapshot> setManga({
    required String mangaKey,
    required wire.ReaderSettingsOverride overrides,
    required int basedOnRevision,
  }) async => SettingsSnapshot._(
    await client.mutateSettings(
      wire.SettingsMutation(
        expectedRevision: basedOnRevision,
        setManga: wire.SetMangaReaderSettings(
          mangaKey: mangaKey,
          overrides: overrides,
        ),
      ),
    ),
  );
}
