import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:karuyomi/diagnostics/reader_baseline_host.dart';
import 'package:karuyomi/features/reader/resource_pool.dart';
import 'package:reader_core/reader_core.dart';

// Constructed timing samples test bookkeeping only; no pump duration or sample
// here is reported as product performance.
ui.FrameTiming timing(int number) => ui.FrameTiming(
  vsyncStart: 9000000000,
  buildStart: 9000000100,
  buildFinish: 9000000400,
  rasterStart: 9000000500,
  rasterFinish: 9000001200,
  rasterFinishWallTime: 1800000000001200,
  frameNumber: number,
  layerCacheCount: 2,
  layerCacheBytes: 1234,
);

List<Map<String, dynamic>> events(ReaderBaselineRecorder recorder) =>
    (jsonDecode(recorder.exportJson())['events'] as List)
        .cast<Map<String, dynamic>>();

final class DelayedProvider implements PageProvider {
  final result = Completer<ImageResource>();
  @override
  Future<ImageResource> acquire(PageRef page) => result.future;
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<void> release(String resourceId) async {}
}

void main() {
  testWidgets(
    'raw clocks stay separate and timings associate by exact frame ID after stop',
    (tester) async {
      final recorder = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 20),
      )..setFrameNumberReaderForTesting(() => 42);
      addTearDown(recorder.dispose);
      recorder.start();
      const number = 42;
      recorder.event('image_frame', {'frameNumber': number});
      recorder.event('viewport', {'frameNumber': number + 10});
      final stopped = recorder.stop();
      expect(recorder.state, ReaderBaselineState.flushing);
      expect(recorder.exportJson, throwsStateError);
      recorder.event('after_stop');
      recorder.recordFrameTimings([
        timing(number),
        timing(number),
        timing(number + 1),
        timing(-1),
      ]);
      await tester.pump(const Duration(milliseconds: 20));
      await stopped;
      final export = jsonDecode(recorder.exportJson());
      expect(export['frames'], hasLength(1));
      expect(export['frames'][0]['frameNumber'], number);
      expect(export['frames'][0]['timestampsUs']['vsyncStart'], 9000000000);
      expect(
        export['frames'][0]['timestampsUs']['rasterFinishWallTime'],
        1800000000001200,
      );
      expect(export['frames'][0]['rasterDurationUs'], 700);
      expect(export['frames'][0]['layerCacheBytes'], 1234);
      expect(export['capture']['imageFramesWithoutTiming'], isEmpty);
      expect(export['capture']['eventFramesWithoutTiming'], [number + 10]);
      expect(export['capture']['frameTimingStatus'], 'incomplete');
      expect(export['capture']['unassociatedTimings'], 1);
      expect(
        export['notMeasured'],
        containsAll(['rss', 'gpu_memory', 'physical_presentation']),
      );
      expect(
        events(recorder).map((e) => e['type']),
        isNot(contains('after_stop')),
      );
      final times = events(recorder).map((e) => e['atUs'] as int).toList();
      expect(times, orderedEquals([...times]..sort()));
      recorder.recordFrameTimings([timing(number)]);
      expect(recorder.frameCount, 1);
    },
  );

  testWidgets(
    'event/frame capacity, duration and disposal all stop in bounded time',
    (tester) async {
      final capped = ReaderBaselineRecorder(
        maxEvents: 2,
        flushDuration: const Duration(milliseconds: 10),
      );
      capped.start();
      capped.event('last');
      capped.event('overflow');
      expect(capped.state, ReaderBaselineState.flushing);
      await tester.pump(const Duration(milliseconds: 10));
      expect(capped.eventCount, 2);
      expect(
        capped.export()['capture'],
        containsPair('stopReason', 'event_limit'),
      );
      expect(capped.export()['capture'], containsPair('truncated', true));
      capped.dispose();

      final frameCapped = ReaderBaselineRecorder(
        maxFrames: 1,
        flushDuration: const Duration(milliseconds: 10),
      )..setFrameNumberReaderForTesting(() => 42);
      frameCapped.start();
      const number = 42;
      frameCapped.recordFrameTimings([timing(number), timing(number + 1)]);
      await tester.pump(const Duration(milliseconds: 10));
      expect(frameCapped.frameCount, 1);
      expect(
        frameCapped.export()['capture'],
        containsPair('stopReason', 'frame_limit'),
      );
      frameCapped.dispose();

      final deadline = ReaderBaselineRecorder(
        maxDuration: const Duration(milliseconds: 20),
        flushDuration: const Duration(milliseconds: 10),
      );
      deadline.start();
      await tester.pump(const Duration(milliseconds: 20));
      expect(deadline.state, ReaderBaselineState.flushing);
      await tester.pump(const Duration(milliseconds: 10));
      expect(deadline.state, ReaderBaselineState.stopped);
      expect(
        deadline.export()['capture'],
        containsPair('frameTimingStatus', 'unavailable'),
      );
      deadline.start();
      final completion = deadline.stop();
      deadline.dispose();
      await completion;
      await tester.pump(const Duration(seconds: 2));
      expect(deadline.state, ReaderBaselineState.disposed);
    },
  );

  testWidgets(
    'late real acquire completion cannot enter a subsequent capture',
    (tester) async {
      final recorder = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      );
      addTearDown(recorder.dispose);
      final provider = DelayedProvider();
      final pool = ReaderResourcePool(provider, baseline: recorder);
      recorder.start();
      final acquire = pool.acquire(
        const PageRef(
          requestId: 'request',
          chapterKey: 'chapter',
          pageKey: 'page',
          generation: 'generation',
        ),
      );
      final stopped = recorder.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      expect(
        events(recorder).map((e) => e['type']),
        contains('acquire_started'),
      );
      recorder.start();
      provider.result.complete(
        ImageResource(
          id: 'image',
          generation: 'generation',
          location: Uri.file('/managed/image'),
          byteLength: 100,
        ),
      );
      await acquire;
      final next = recorder.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await next;
      expect(
        events(recorder).map((e) => e['type']),
        isNot(contains('acquire_finished')),
      );
      await pool.release('image');
    },
  );

  testWidgets(
    'panel exports accessible JSON only after the bounded flush and copies the same result',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ReaderBaselineHost(child: child!),
          home: const Scaffold(body: Text('正式 UI')),
        ),
      );
      await tester.tap(find.text('性能采集'));
      await tester.pump();
      await tester.tap(find.text('开始采集'));
      await tester.pump();
      await tester.tap(find.byTooltip('收起性能采集'));
      await tester.pump();
      expect(find.text('正式 UI'), findsOneWidget);
      await tester.tap(find.text('性能采集'));
      await tester.pump();
      await tester.tap(find.text('停止采集'));
      await tester.pump();
      expect(find.textContaining('停止中'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.text('查看 JSON'));
      await tester.pump();
      final text = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('reader-baseline-json')),
          )
          .data!;
      expect(jsonDecode(text)['schema'], 'karuyomi.reader-baseline.v1');
      expect(
        jsonDecode(text)['environment']['devicePixelRatio'],
        tester.view.devicePixelRatio,
      );
      expect(
        jsonDecode(text)['environment']['refreshRateHz'],
        tester.view.display.refreshRate,
      );
      expect(tester.binding.semanticsEnabled, true);
      await tester.tap(find.text('复制 JSON'));
      await tester.pump();
      expect(clipboard, text);
      await tester.tap(find.text('开始采集'));
      await tester.pump();
      expect(find.byKey(const ValueKey('reader-baseline-json')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
