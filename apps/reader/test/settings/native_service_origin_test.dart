import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/widgets/choice_field.dart';
import 'package:karuyomi/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browse/fakes.dart';
import 'settings_probe.dart';

final class _Preferences extends Fake implements SharedPreferencesAsync {
  _Preferences({this.beforeWrite});

  final values = <String, String>{};
  final void Function()? beforeWrite;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    beforeWrite?.call();
    values[key] = value;
  }
}

void main() {
  testWidgets(
    'device appearance autosaves offline, retries and restores in a fresh app',
    (tester) async {
      var failWrites = true;
      final preferences = _Preferences(
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
    final preferences = _Preferences();
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
