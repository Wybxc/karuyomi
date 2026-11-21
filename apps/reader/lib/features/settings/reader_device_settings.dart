import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../reader/reader_preferences.dart';

part 'reader_device_settings.g.dart';

typedef ReaderDeviceScope = ({String origin, String mangaKey});

typedef ReaderDevicePreferences = ({
  ReaderBackground? background,
  int? dimPercent,
  ReaderInputPreset? tapZones,
  ReaderInputPreset? keyboard,
});

const ReaderDevicePreferences _inherited = (
  background: null,
  dimPercent: null,
  tapZones: null,
  keyboard: null,
);

const defaultReaderDevicePreferences = (
  background: ReaderBackground.black,
  dimPercent: 0,
  tapZones: ReaderInputPreset.standard,
  keyboard: ReaderInputPreset.standard,
);

@riverpod
SharedPreferencesAsync readerDeviceStorage(Ref ref) => SharedPreferencesAsync();

typedef EffectiveReaderDevicePreferences = ({
  ReaderBackground background,
  int dimPercent,
  ReaderInputPreset tapZones,
  ReaderInputPreset keyboard,
});

@riverpod
EffectiveReaderDevicePreferences effectiveReaderDevicePreferences(
  Ref ref, {
  ReaderDeviceScope? scope,
}) {
  final defaults = ref.watch(readerDeviceSettingsProvider()).value?.preferences;
  final overrides = scope == null
      ? null
      : ref
            .watch(readerDeviceSettingsProvider(scope: scope))
            .value
            ?.preferences;
  return (
    background:
        overrides?.background ??
        defaults?.background ??
        defaultReaderDevicePreferences.background,
    dimPercent:
        overrides?.dimPercent ??
        defaults?.dimPercent ??
        defaultReaderDevicePreferences.dimPercent,
    tapZones:
        overrides?.tapZones ??
        defaults?.tapZones ??
        defaultReaderDevicePreferences.tapZones,
    keyboard:
        overrides?.keyboard ??
        defaults?.keyboard ??
        defaultReaderDevicePreferences.keyboard,
  );
}

final class const ReaderDeviceState({
  required final ReaderDevicePreferences preferences,
  final bool saving = false,
  final ReaderDevicePreferences? failed,
});

@riverpod
class ReaderDeviceSettings extends _$ReaderDeviceSettings {
  String get _key => switch (scope) {
    final manga? => 'device_reader/${manga.origin}/${manga.mangaKey}',
    null => 'device_reader',
  };

  @override
  Future<ReaderDeviceState> build({ReaderDeviceScope? scope}) async {
    final storage = ref.watch(readerDeviceStorageProvider);
    try {
      final text = await storage
          .getString(_key)
          .timeout(const Duration(seconds: 3));
      if (text != null && text.length <= 256) {
        final Object? document = jsonDecode(text);
        if (document case final Map<String, Object?> values) {
          final dim = values['dimPercent'];
          return ReaderDeviceState(
            preferences: (
              background: ReaderBackground.values
                  .asNameMap()[values['background']],
              dimPercent: dim is int && dim >= 0 && dim <= 80 ? dim : null,
              tapZones: ReaderInputPreset.values
                  .asNameMap()[values['tapZones']],
              keyboard: ReaderInputPreset.values
                  .asNameMap()[values['keyboard']],
            ),
          );
        }
      }
    } catch (_) {
      // Device preferences are optional at startup.
    }
    return const ReaderDeviceState(preferences: _inherited);
  }

  Future<void> save(ReaderDevicePreferences preferences) async {
    if (preferences.dimPercent case final dim? when dim < 0 || dim > 80) {
      throw RangeError.range(dim, 0, 80, 'dimPercent');
    }
    final previous = state.value;
    if (previous == null ||
        previous.saving ||
        preferences == previous.preferences) {
      return;
    }
    final storage = ref.read(readerDeviceStorageProvider);
    final retained = ref.keepAlive();
    state = AsyncData(
      ReaderDeviceState(preferences: previous.preferences, saving: true),
    );
    try {
      if (preferences == _inherited) {
        await storage.remove(_key);
      } else {
        await storage.setString(
          _key,
          jsonEncode({
            'background': ?preferences.background?.name,
            'dimPercent': ?preferences.dimPercent,
            'tapZones': ?preferences.tapZones?.name,
            'keyboard': ?preferences.keyboard?.name,
          }),
        );
      }
      if (ref.mounted) {
        state = AsyncData(ReaderDeviceState(preferences: preferences));
      }
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          ReaderDeviceState(
            preferences: previous.preferences,
            failed: preferences,
          ),
        );
      }
    } finally {
      retained.close();
    }
  }
}
