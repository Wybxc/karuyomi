import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/popup_authentication.dart';

void main() {
  const attempt = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
  final origin = Uri.parse('https://read.example.com');
  Uri callback([String current = attempt]) =>
      origin.resolve('/auth/complete?attempt=$current');

  testWidgets('same window, origin, callback and attempt complete and close', (
    tester,
  ) async {
    final authentication = PopupAuthentication();
    var closes = 0;
    final result = authentication.wait(
      origin: origin,
      attempt: attempt,
      readLocation: callback,
      isClosed: () => false,
      close: () => closes++,
    );
    expect(await result, isTrue);
    expect(closes, 1);
    authentication.cancel();
    await tester.pump(const Duration(minutes: 4));
    expect(closes, 1);
  });

  testWidgets('foreign origin, old attempt and other paths cannot complete', (
    tester,
  ) async {
    final authentication = PopupAuthentication();
    Uri? location;
    var completed = false;
    final result = authentication.wait(
      origin: origin,
      attempt: attempt,
      readLocation: () => location,
      isClosed: () => false,
      close: () {},
    )..then((_) => completed = true);
    for (final invalid in [
      Uri.parse('about:blank'),
      Uri.parse('https://foreign.example/auth/complete?attempt=$attempt'),
      callback('previous-attempt'),
      origin.resolve('/settings?attempt=$attempt'),
    ]) {
      location = invalid;
      await tester.pump(const Duration(milliseconds: 200));
      expect(completed, isFalse);
    }
    location = callback();
    await tester.pump(const Duration(milliseconds: 200));
    expect(await result, isTrue);
  });

  testWidgets(
    'closed or isolated popup reports cancellation and stops polling',
    (tester) async {
      final authentication = PopupAuthentication();
      var closed = false;
      var reads = 0;
      var closes = 0;
      final result = authentication.wait(
        origin: origin,
        attempt: attempt,
        readLocation: () {
          reads++;
          return null;
        },
        isClosed: () => closed,
        close: () => closes++,
      );
      final failure = expectLater(result, throwsStateError);
      closed = true;
      await tester.pump(const Duration(milliseconds: 200));
      await failure;
      final finalReads = reads;
      await tester.pump(const Duration(minutes: 4));
      expect(reads, finalReads);
      expect(closes, 1);
    },
  );

  testWidgets('timeout closes the popup and releases timers', (tester) async {
    final authentication = PopupAuthentication(
      timeout: const Duration(seconds: 1),
    );
    var closes = 0;
    final result = authentication.wait(
      origin: origin,
      attempt: attempt,
      readLocation: () => null,
      isClosed: () => false,
      close: () => closes++,
    );
    final failure = expectLater(result, throwsStateError);
    await tester.pump(const Duration(seconds: 1));
    await failure;
    expect(closes, 1);
  });

  testWidgets('runtime cancellation closes the popup exactly once', (
    tester,
  ) async {
    final authentication = PopupAuthentication();
    var closes = 0;
    final result = authentication.wait(
      origin: origin,
      attempt: attempt,
      readLocation: () => null,
      isClosed: () => false,
      close: () => closes++,
    );
    final failure = expectLater(result, throwsStateError);
    authentication.cancel();
    authentication.cancel();
    await tester.pump();
    await failure;
    await tester.pump(const Duration(minutes: 4));
    expect(closes, 1);
  });
}
