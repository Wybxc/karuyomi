import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const readerBaselineEnabled = bool.fromEnvironment('READER_BASELINE');

enum ReaderBaselineState { idle, recording, flushing, stopped, disposed }

/// App-only measurement. Event timestamps and engine timestamps deliberately
/// remain separate; frameNumber is the only join key between those clocks.
final class ReaderBaselineRecorder extends ChangeNotifier {
  ReaderBaselineRecorder({
    this.maxEvents = 12000,
    this.maxFrames = 12000,
    this.maxDuration = const Duration(seconds: 60),
    this.flushDuration = const Duration(milliseconds: 1500),
  }) {
    if (maxEvents < 1 ||
        maxEvents > 20000 ||
        maxFrames < 1 ||
        maxFrames > 20000 ||
        maxDuration <= Duration.zero ||
        maxDuration > const Duration(minutes: 5) ||
        flushDuration <= Duration.zero ||
        flushDuration > const Duration(seconds: 3)) {
      throw ArgumentError('Baseline limits must be positive and bounded');
    }
  }

  final int maxEvents;
  final int maxFrames;
  final Duration maxDuration;
  final Duration flushDuration;
  final _clock = Stopwatch();
  int Function() _readFrameNumber = () =>
      ui.PlatformDispatcher.instance.frameData.frameNumber;

  /// The SDK test dispatcher exposes frameData only as a forwarding getter.
  /// Keep bookkeeping fixtures independent of its unknown initial frame ID.
  @visibleForTesting
  void setFrameNumberReaderForTesting(int Function() reader) {
    _readFrameNumber = reader;
  }

  final _events = <Map<String, Object?>>[];
  final _frames = <Map<String, Object?>>[];
  final _frameNumbers = <int>{};
  ReaderBaselineState _state = ReaderBaselineState.idle;
  Timer? _deadline;
  Timer? _flush;
  Completer<void>? _stopped;
  bool _attached = false;
  int _session = 0;
  int _operation = 0;
  int? _firstFrame;
  int? _lastFrame;
  int? _stopUs;
  String? _stopReason;
  String? _startedAt;
  Object? _environment;
  bool _truncated = false;
  int _unassociatedTimings = 0;

  ReaderBaselineState get state => _state;
  int get session => _session;
  bool get recording => _state == ReaderBaselineState.recording;
  int get eventCount => _events.length;
  int get frameCount => _frames.length;

  void start({Map<String, Object?> environment = const {}}) {
    if (_state == ReaderBaselineState.disposed ||
        recording ||
        _state == ReaderBaselineState.flushing) {
      return;
    }
    _events.clear();
    _frames.clear();
    _frameNumbers.clear();
    _session++;
    _operation = 0;
    _stopReason = null;
    _stopUs = null;
    _lastFrame = null;
    _truncated = false;
    _unassociatedTimings = 0;
    _environment = _bounded(environment);
    _startedAt = DateTime.now().toUtc().toIso8601String();
    _firstFrame = _readFrameNumber();
    _clock
      ..reset()
      ..start();
    _stopped = Completer<void>();
    _state = ReaderBaselineState.recording;
    SchedulerBinding.instance.addTimingsCallback(recordFrameTimings);
    _attached = true;
    _deadline = Timer(
      maxDuration,
      () => unawaited(stop(reason: 'duration_limit')),
    );
    event('capture_started');
    notifyListeners();
  }

  void event(String name, [Map<String, Object?> data = const {}]) {
    if (!recording) return;
    if (_events.length >= maxEvents) {
      _truncated = true;
      unawaited(stop(reason: 'event_limit'));
      return;
    }
    _events.add({
      'type': name,
      'atUs': _clock.elapsedMicroseconds,
      'data': _bounded(data),
    });
  }

  /// A token keeps late acquire completions out of a subsequent capture.
  ({int session, int operation})? beginAcquire(Map<String, Object?> page) {
    if (!recording) return null;
    final token = (session: _session, operation: ++_operation);
    event('acquire_started', {'operation': token.operation, ...page});
    return token;
  }

  void endAcquire(
    ({int session, int operation})? token,
    Map<String, Object?> result,
  ) {
    if (token == null || token.session != _session) return;
    event('acquire_finished', {'operation': token.operation, ...result});
  }

  Future<void> stop({String reason = 'user'}) {
    if (_state == ReaderBaselineState.flushing) return _stopped!.future;
    if (!recording) return Future.value();
    _stopUs = _clock.elapsedMicroseconds;
    _lastFrame = _readFrameNumber();
    _stopReason = reason;
    _deadline?.cancel();
    _deadline = null;
    _state = ReaderBaselineState.flushing;
    _flush = Timer(flushDuration, _finish);
    notifyListeners();
    return _stopped!.future;
  }

  /// Registered with SchedulerBinding; callback arrival is never a rendering
  /// endpoint. Tests may inject raw engine-shaped samples to check bookkeeping.
  @visibleForTesting
  void recordFrameTimings(List<ui.FrameTiming> timings) {
    if (!recording && _state != ReaderBaselineState.flushing) return;
    final receivedUs = _clock.elapsedMicroseconds;
    for (final timing in timings) {
      final number = timing.frameNumber;
      // Unknown IDs cannot be assigned to this capture by timestamp arithmetic.
      if (number < 0) {
        _unassociatedTimings++;
        continue;
      }
      if (number < _firstFrame! ||
          (_lastFrame != null && number > _lastFrame!)) {
        continue;
      }
      if (_frameNumbers.contains(number)) continue;
      if (_frames.length >= maxFrames) {
        _truncated = true;
        if (recording) unawaited(stop(reason: 'frame_limit'));
        break;
      }
      _frameNumbers.add(number);
      _frames.add({
        'frameNumber': number,
        'reportedAtUs': receivedUs,
        'timestampsUs': {
          for (final phase in ui.FramePhase.values)
            phase.name: timing.timestampInMicroseconds(phase),
        },
        'buildDurationUs': timing.buildDuration.inMicroseconds,
        'rasterDurationUs': timing.rasterDuration.inMicroseconds,
        'totalSpanUs': timing.totalSpan.inMicroseconds,
        'vsyncOverheadUs': timing.vsyncOverhead.inMicroseconds,
        'layerCacheCount': timing.layerCacheCount,
        'layerCacheBytes': timing.layerCacheBytes,
        'pictureCacheCount': timing.pictureCacheCount,
        'pictureCacheBytes': timing.pictureCacheBytes,
      });
    }
  }

  void _detach() {
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(recordFrameTimings);
    _attached = false;
  }

  void _finish() {
    _flush?.cancel();
    _flush = null;
    _detach();
    _clock.stop();
    _state = ReaderBaselineState.stopped;
    _stopped?.complete();
    notifyListeners();
  }

  Map<String, Object?> export() {
    if (_state != ReaderBaselineState.stopped) {
      throw StateError(
        'Stop and finish the bounded timing flush before exporting',
      );
    }
    final imageFrames = _events
        .where((e) => e['type'] == 'image_frame')
        .map((e) => (e['data']! as Map<String, Object?>)['frameNumber'])
        .whereType<int>()
        .toSet();
    final missing = imageFrames.difference(_frameNumbers).toList()..sort();
    final eventFrames = _events
        .map((e) => (e['data']! as Map<String, Object?>)['frameNumber'])
        .whereType<int>()
        .toSet();
    final unmatched = eventFrames.difference(_frameNumbers).toList()..sort();
    return {
      'schema': 'karuyomi.reader-baseline.v1',
      'revision': const String.fromEnvironment('BASELINE_REVISION'),
      'environment': _environment,
      'startedAtUtc': _startedAt,
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'eventClock': 'Stopwatch elapsed microseconds since start',
      'frameClock':
          'Engine FrameTiming epoch; rasterFinishWallTime has its own wall-clock epoch; join events by frameNumber only',
      'interpretation': {
        'image_info':
            'Decoded ImageInfo arrival, possibly synchronous cache reuse; not decode CPU time',
        'image_frame':
            'Image.frameBuilder in a framework frame; not physical presentation',
        'viewport':
            'Logical content intersection and current resource identity after layout; not occlusion or physical visibility',
        'reportedAtUs':
            'Timing callback receipt only; never the end of rendering',
        'rasterDurationUs':
            'Engine renderer timing; not isolated GPU execution',
      },
      'notMeasured': [
        'physical_presentation',
        'rss',
        'gpu_memory',
        'decode_cpu',
      ],
      'limits': {
        'maxEvents': maxEvents,
        'maxFrames': maxFrames,
        'maxDurationUs': maxDuration.inMicroseconds,
        'flushDurationUs': flushDuration.inMicroseconds,
        'maxDataItems': 64,
        'maxStringLength': 256,
      },
      'capture': {
        'session': _session,
        'stopReason': _stopReason,
        'stopAtUs': _stopUs,
        'frameBoundaryPolicy':
            'Inclusive start/stop frame IDs; boundary frames may overlap capture boundaries',
        'firstFrameNumber': _firstFrame,
        'lastFrameNumber': _lastFrame,
        'truncated': _truncated,
        'eventCount': eventCount,
        'frameCount': frameCount,
        'unassociatedTimings': _unassociatedTimings,
        'imageFramesWithoutTiming': missing,
        'eventFramesWithoutTiming': unmatched,
        'frameTimingStatus': _frames.isEmpty
            ? 'unavailable'
            : unmatched.isEmpty
            ? 'associated'
            : 'incomplete',
      },
      'events': _events,
      'frames': _frames,
    };
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(export());

  Object? _bounded(Object? value, [int depth = 0]) {
    if (value is String) {
      if (value.length <= 256) return value;
      _truncated = true;
      return '${value.substring(0, 253)}...';
    }
    if (value == null || value is bool || value is num) return value;
    if (depth >= 4) {
      _truncated = true;
      return '[depth limit]';
    }
    if (value is Map<String, Object?>) {
      if (value.length > 64) _truncated = true;
      return <String, Object?>{
        for (final entry in value.entries.take(64))
          entry.key: _bounded(entry.value, depth + 1),
      };
    }
    if (value is Iterable<Object?>) {
      if (value.length > 64) _truncated = true;
      return value.take(64).map((v) => _bounded(v, depth + 1)).toList();
    }
    return _bounded(value.toString(), depth);
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _flush?.cancel();
    _detach();
    _clock.stop();
    _state = ReaderBaselineState.disposed;
    if (_stopped case final stopped? when !stopped.isCompleted) {
      stopped.complete();
    }
    super.dispose();
  }
}

/// Non-listening lookup allows instrumentation without repainting the reader.
class ReaderBaselineScope extends InheritedWidget {
  const ReaderBaselineScope({
    super.key,
    required this.recorder,
    required super.child,
  });
  final ReaderBaselineRecorder recorder;
  static ReaderBaselineRecorder? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReaderBaselineScope>()?.recorder;
  @override
  bool updateShouldNotify(ReaderBaselineScope oldWidget) =>
      recorder != oldWidget.recorder;
}
