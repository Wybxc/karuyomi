import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browse/fakes.dart';

final class _Preferences extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
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
