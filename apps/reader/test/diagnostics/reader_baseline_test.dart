import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cross_file/cross_file.dart';
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
    'large reports never enter paragraph layout and download complete UTF8 bytes once per report',
    (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late ReaderBaselineRecorder recorder;
      final files = <XFile>[];
      final downloads = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ReaderBaselineHost(
            saveReportForTesting: (file) async {
              files.add(file);
              downloads.add(await file.readAsBytes());
            },
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                recorder = ReaderBaselineScope.read(context)!;
                return const Text('正式 UI');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      var currentFrame = 42;
      recorder.setFrameNumberReaderForTesting(() => currentFrame);
      await tester.tap(find.text('性能采集'));
      await tester.pump();
      await tester.tap(find.text('开始采集'));
      await tester.pump();
      // Raw fixture samples stress export integrity and layout only, not speed.
      recorder.recordFrameTimings(List.generate(4096, (i) => timing(42 + i)));
      recorder.event('export_fixture', {'label': '中文导出完整性'});
      currentFrame = 42 + 4095;
      await tester.tap(find.text('停止采集'));
      await tester.pump(const Duration(milliseconds: 1500));
      final complete = recorder.exportJson();
      expect(complete.length, greaterThan(1000000));
      await tester.tap(find.text('查看摘要'));
      await tester.pumpAndSettle();
      final preview = tester
          .widget<Text>(find.byKey(const ValueKey('reader-baseline-preview')))
          .data!;
      expect(preview.length, lessThanOrEqualTo(1024));
      expect(complete, startsWith(preview));
      final paragraphs = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '');
      expect(paragraphs.every((text) => text.length <= 1024), true);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('下载 JSON'));
      await tester.tap(find.text('下载 JSON'));
      await tester.pumpAndSettle();
      expect(downloads, hasLength(1));
      expect(downloads.single, orderedEquals(utf8.encode(complete)));
      expect(
        jsonDecode(utf8.decode(downloads.single))['frames'],
        hasLength(4096),
      );
      expect(files.single.mimeType, 'application/json');
      expect(files.single.name, 'karuyomi-reader-baseline-1.json');
      expect(find.text('已请求下载 JSON'), findsOneWidget);
      await tester.tap(find.text('下载 JSON'));
      await tester.pumpAndSettle();
      expect(files, hasLength(2));
      expect(identical(files.first, files.last), true);
      expect(downloads.last, orderedEquals(downloads.first));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'panel displays only bounded summary and preview then copies the complete report',
    (tester) async {
      String? clipboard;
      late ReaderBaselineRecorder recorder;
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
          home: Scaffold(
            body: Builder(
              builder: (context) {
                recorder = ReaderBaselineScope.read(context)!;
                return const Text('正式 UI');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('性能采集'));
      await tester.pump();
      await tester.tap(find.text('开始采集'));
      await tester.pump();
      await tester.tap(find.text('收起性能采集'));
      await tester.pump();
      expect(find.text('正式 UI'), findsOneWidget);
      await tester.tap(find.text('性能采集'));
      await tester.pump();
      await tester.tap(find.text('停止采集'));
      await tester.pump();
      expect(find.textContaining('停止中'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(find.text('查看摘要'));
      await tester.pump();
      final preview = tester
          .widget<Text>(find.byKey(const ValueKey('reader-baseline-preview')))
          .data!;
      final text = recorder.exportJson();
      expect(preview.length, lessThanOrEqualTo(1024));
      expect(text, startsWith(preview));
      expect(jsonDecode(text)['schema'], 'karuyomi.reader-baseline.v1');
      expect(
        jsonDecode(text)['environment']['devicePixelRatio'],
        tester.view.devicePixelRatio,
      );
      expect(
        jsonDecode(text)['environment']['refreshRateHz'],
        tester.view.display.refreshRate,
      );
      await tester.tap(find.text('复制 JSON'));
      await tester.pump();
      expect(clipboard, text);
      await tester.tap(find.text('开始采集'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reader-baseline-preview')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
