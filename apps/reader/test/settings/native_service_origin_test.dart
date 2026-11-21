import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:karuyomi/features/reader/reader_preferences.dart';
import 'package:karuyomi/features/settings/reader_device_settings.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/widgets/choice_field.dart';
import 'package:karuyomi/main.dart';

import '../browse/fakes.dart';
import 'settings_fixture.dart';
import 'settings_probe.dart';

void main() {
  test('reader device overrides survive restart and inherit by deployment and manga', () async {
    final storage = TestDevicePreferences();
    ProviderContainer open() => ProviderContainer(
      overrides: [readerDeviceStorageProvider.overrideWithValue(storage)],
    );
    const scope = (origin: 'https://first.example', mangaKey: 'book');
    const anotherDeployment = (
      origin: 'https://second.example',
      mangaKey: 'book',
    );
    const anotherManga = (origin: 'https://first.example', mangaKey: 'other');
    const defaults = (
      background: ReaderBackground.white,
      dimPercent: 40,
      tapZones: ReaderInputPreset.reversed,
      keyboard: ReaderInputPreset.disabled,
    );
    const ReaderDevicePreferences overrides = (
      background: null,
      dimPercent: 0,
      tapZones: null,
      keyboard: ReaderInputPreset.standard,
    );
    final base = readerDeviceSettingsProvider();
    final manga = readerDeviceSettingsProvider(scope: scope);
    final first = open();
    first.listen(base, (_, _) {});
    first.listen(manga, (_, _) {});
    await first.read(base.future);
    await first.read(manga.future);
    await first.read(base.notifier).save(defaults);
    await first.read(manga.notifier).save(overrides);
    first.dispose();

    final reopened = open();
    addTearDown(reopened.dispose);
    EffectiveReaderDevicePreferences effective(ReaderDeviceScope scope) =>
        reopened.read(effectiveReaderDevicePreferencesProvider(scope: scope));
    for (final provider in [
      base,
      manga,
      readerDeviceSettingsProvider(scope: anotherDeployment),
      readerDeviceSettingsProvider(scope: anotherManga),
    ]) {
      reopened.listen(provider, (_, _) {});
      await reopened.read(provider.future);
    }
    expect(effective(scope), (
      background: ReaderBackground.white,
      dimPercent: 0,
      tapZones: ReaderInputPreset.reversed,
      keyboard: ReaderInputPreset.standard,
    ));
    expect(effective(anotherDeployment), defaults);
    expect(effective(anotherManga), defaults);
    await reopened.read(manga.notifier).save((
      background: null,
      dimPercent: null,
      tapZones: null,
      keyboard: null,
    ));
    expect(effective(scope), defaults);
    expect(storage.values, hasLength(1));
  });

  testWidgets(
    'device appearance autosaves offline, retries and restores in a fresh app',
    (tester) async {
      var failWrites = true;
      final preferences = TestDevicePreferences(
        beforeWrite: () {
          if (failWrites) {
            throw StateError('Simulated preferences write failure');
          }
        },
      );
      KaruyomiApp app() => KaruyomiApp(
        appearancePreferences: preferences,
        platformFactory: (_) => throw ArgumentError('No configured service'),
      );
      final theme = find.byKey(const ValueKey('device-theme'));
      AppAppearance selection() =>
          tester.widget<ChoiceField<AppAppearance>>(theme).value!;
      Brightness? brightness() => tester
          .widget<CupertinoApp>(find.byType(CupertinoApp))
          .theme
          ?.brightness;

      Future<void> openAppearance() async {
        await tester.tap(find.byKey(const ValueKey(('app-destination', 2))));
        await tester.pumpAndSettle();
        await openSettingsSection(tester, 'appearance');
      }

      await tester.pumpApp(app());
      await tester.pumpAndSettle();
      await openAppearance();
      expect(selection(), AppAppearance.system);
      await tester.tap(theme);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoMenuItem, '深色'));
      await tester.pumpAndSettle();
      expect(selection(), AppAppearance.system);
      expect(preferences.values, isEmpty);
      expect(find.text('未能保存本机外观。'), findsOneWidget);

      failWrites = false;
      await tester.tap(find.text('重试保存外观'));
      await tester.pumpAndSettle();
      expect(selection(), AppAppearance.dark);
      expect(brightness(), Brightness.dark);
      expect(preferences.values.values, ['dark']);

      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpApp(app());
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await openAppearance();
      expect(selection(), AppAppearance.dark);
      expect(find.text('重试保存外观'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Native restores the selected HTTPS service in a fresh app', (
    tester,
  ) async {
    final preferences = TestDevicePreferences();
    final connected = <TestPlatform>[];
    KaruyomiApp app() => KaruyomiApp(
      connectionPreferences: preferences,
      platformFactory: (origin) {
        if (origin == null || origin.scheme != 'https') {
          throw ArgumentError('A service needs HTTPS');
        }
        final platform = TestPlatform(origin: origin);
        connected.add(platform);
        return platform;
      },
    );
    Future<void> openSettings() async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('app-navigation')),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('settings-section-connection'))
          .evaluate()
          .isNotEmpty) {
        await openSettingsSection(tester, 'connection');
      }
    }

    await tester.pumpApp(app());
    await tester.pumpAndSettle();
    await openSettings();

    final field = find.byType(CupertinoTextField);
    final connect = find.text('连接服务');
    await tester.enterText(field, 'https://reader.example.net:9443/');
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(connected.single.origin.origin, 'https://reader.example.net:9443');
    expect(connected.single.businessServer.appliedMutations, 0);

    await openSettingsSection(tester, 'connection');
    await tester.enterText(field, 'http://invalid.example.net');
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(connected, hasLength(1));
    expect(connected.single.disposalCount, 0);

    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpApp(app());
    await tester.pumpAndSettle();
    expect(connected, hasLength(2));
    expect(connected.last.origin.origin, 'https://reader.example.net:9443');
    expect(connected.last.businessServer.appliedMutations, 0);
    await openSettings();
    expect(
      tester.widget<CupertinoTextField>(field).controller!.text,
      'https://reader.example.net:9443',
    );
  });
}
