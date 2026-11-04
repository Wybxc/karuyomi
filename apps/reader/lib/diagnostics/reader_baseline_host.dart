import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'reader_baseline.dart';

/// Mounted only in an explicitly enabled build. The normal app has no recorder,
/// timings listener, performance overlay, or global JavaScript export hook.
class ReaderBaselineHost extends StatefulWidget {
  const ReaderBaselineHost({super.key, required this.child});
  final Widget child;
  @override
  State<ReaderBaselineHost> createState() => _ReaderBaselineHostState();
}

class _ReaderBaselineHostState extends State<ReaderBaselineHost> {
  // MaterialApp.builder sits above its Navigator. Give the diagnostic controls
  // their own official Overlay so tooltips and text selection also work here.
  late final _entry = OverlayEntry(
    builder: (context) => _ReaderBaselineContents(child: widget.child),
  );
  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
  @override
  void didUpdateWidget(ReaderBaselineHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }
}

class _ReaderBaselineContents extends StatefulWidget {
  const _ReaderBaselineContents({required this.child});
  final Widget child;
  @override
  State<_ReaderBaselineContents> createState() =>
      _ReaderBaselineContentsState();
}

class _ReaderBaselineContentsState extends State<_ReaderBaselineContents> {
  final _recorder = ReaderBaselineRecorder();
  bool _open = false;
  String? _json;
  SemanticsHandle? _exportSemantics;
  @override
  void initState() {
    super.initState();
    _recorder.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ReaderBaselineScope(
    recorder: _recorder,
    child: Stack(
      children: [
        widget.child,
        Positioned(
          right: 8,
          top: MediaQuery.paddingOf(context).top + 8,
          child: _open
              ? _panel()
              : Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  child: TextButton.icon(
                    onPressed: () {
                      _recorder.event('capture_panel_opened');
                      setState(() => _open = true);
                    },
                    icon: const Icon(Icons.speed),
                    label: const Text('性能采集'),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _panel() => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 16).clamp(0, 560),
    height: (MediaQuery.sizeOf(context).height - 32).clamp(0, 640),
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('性能采集')),
                IconButton(
                  tooltip: '收起性能采集',
                  onPressed: () {
                    _recorder.event('capture_panel_closed');
                    setState(() => _open = false);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              '状态：${switch (_recorder.state) {
                ReaderBaselineState.idle => '尚未开始',
                ReaderBaselineState.recording => '采集中（最长 60 秒）',
                ReaderBaselineState.flushing => '停止中，等待帧计时（最多 1.5 秒）',
                ReaderBaselineState.stopped => '已停止',
                ReaderBaselineState.disposed => '已关闭',
              }}',
            ),
            const Text(
              '开始后收起面板，在正式阅读界面操作，再停止并导出。记录框架帧和逻辑可见页；未测量物理呈现、RSS 或 GPU 内存。',
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      _recorder.recording ||
                          _recorder.state == ReaderBaselineState.flushing
                      ? null
                      : () {
                          _json = null;
                          _exportSemantics?.dispose();
                          _exportSemantics = null;
                          final media = MediaQuery.of(context);
                          _recorder.start(
                            environment: {
                              'logicalWidth': media.size.width,
                              'logicalHeight': media.size.height,
                              'devicePixelRatio': media.devicePixelRatio,
                              'refreshRateHz': View.of(
                                context,
                              ).display.refreshRate,
                              'orientation': media.orientation.name,
                            },
                          );
                        },
                  child: const Text('开始采集'),
                ),
                OutlinedButton(
                  onPressed: _recorder.recording
                      ? () {
                          _recorder.stop();
                        }
                      : null,
                  child: const Text('停止采集'),
                ),
                OutlinedButton(
                  onPressed: _recorder.state == ReaderBaselineState.stopped
                      ? () {
                          // Expose the stopped result to browser accessibility DOM
                          // without enabling semantics during the measured run.
                          _exportSemantics ??= SemanticsBinding.instance
                              .ensureSemantics();
                          setState(() => _json = _recorder.exportJson());
                        }
                      : null,
                  child: const Text('查看 JSON'),
                ),
                OutlinedButton(
                  onPressed: _json == null
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: _json!));
                        },
                  child: const Text('复制 JSON'),
                ),
              ],
            ),
            if (_recorder.state == ReaderBaselineState.stopped)
              Text('事件 ${_recorder.eventCount}；帧样本 ${_recorder.frameCount}'),
            if (_json != null)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _json!,
                    key: const ValueKey('reader-baseline-json'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _exportSemantics?.dispose();
    _recorder.removeListener(_changed);
    _recorder.dispose();
    super.dispose();
  }
}
