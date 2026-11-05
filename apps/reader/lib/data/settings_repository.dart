import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'reading_progress.dart';

/// A confirmed online snapshot. Missing override fields mean inheritance;
/// an explicit AUTO layout remains present in [overrides].
final class SettingsSnapshot {
  SettingsSnapshot._(wire.SettingsResponse value)
    : accountRevision = value.accountRevision,
      globalRevision = value.global.revision,
      global = value.global.values.deepCopy()..freeze(),
      mangaKey = value.hasManga() ? value.manga.mangaKey : null,
      mangaRevision = value.hasManga() ? value.manga.revision : null,
      overrides = value.hasManga()
          ? (value.manga.overrides.deepCopy()..freeze())
          : null,
      effectiveReader = value.effectiveReader.deepCopy()..freeze();
  final int accountRevision;
  final int globalRevision;
  final wire.GlobalSettingsValues global;
  final String? mangaKey;
  final int? mangaRevision;
  final wire.ReaderSettingsOverride? overrides;
  final wire.ReaderSettings effectiveReader;
}

/// Frozen submitted values. Retrying this exact draft retains its UUID/CAS.
final class SettingsDraft {
  SettingsDraft._(wire.SettingsMutation value, this.retryable)
    : mangaKey = value.hasSetManga() ? value.setManga.mangaKey : null,
      global = value.hasSetGlobal()
          ? (value.setGlobal.deepCopy()..freeze())
          : null,
      overrides = value.hasSetManga()
          ? (value.setManga.overrides.deepCopy()..freeze())
          : null,
      basedOnRevision = value.expectedRevision;
  final String? mangaKey;
  final wire.GlobalSettingsValues? global;
  final wire.ReaderSettingsOverride? overrides;
  final int basedOnRevision;
  final bool retryable;
}

final class SettingsRepository {
  SettingsRepository(this.client);
  final BusinessStateClient client;
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
