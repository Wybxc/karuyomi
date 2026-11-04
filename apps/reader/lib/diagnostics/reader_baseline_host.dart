import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'reader_baseline.dart';
import 'reader_baseline_file_cleanup_stub.dart'
    if (dart.library.js_interop) 'reader_baseline_file_cleanup_web.dart'
    as platform;

/// Mounted only in an explicitly enabled build. The normal app has no recorder,
/// timings listener, performance overlay, or global JavaScript export hook.
class ReaderBaselineHost extends StatefulWidget {
  const ReaderBaselineHost({
    super.key,
    required this.child,
    this.saveReportForTesting,
  });
  final Widget child;
  @visibleForTesting
  final Future<void> Function(XFile file)? saveReportForTesting;
  @override
  State<ReaderBaselineHost> createState() => _ReaderBaselineHostState();
}

class _ReaderBaselineHostState extends State<ReaderBaselineHost> {
  // MaterialApp.builder sits above its Navigator. Give the diagnostic controls
  // their own official Overlay so tooltips and text selection also work here.
  late final _entry = OverlayEntry(
    builder: (context) => _ReaderBaselineContents(
      saveReportForTesting: widget.saveReportForTesting,
      child: widget.child,
    ),
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
  const _ReaderBaselineContents({
    required this.child,
    this.saveReportForTesting,
  });
  final Widget child;
  final Future<void> Function(XFile file)? saveReportForTesting;
  @override
  State<_ReaderBaselineContents> createState() =>
      _ReaderBaselineContentsState();
}

class _ReaderBaselineContentsState extends State<_ReaderBaselineContents> {
  final _recorder = ReaderBaselineRecorder();
  bool _open = false;
  String? _json;
  String? _summary;
  String? _preview;
  XFile? _downloadFile;
  String? _exportStatus;
  bool _summaryVisible = false;
  bool _downloadPending = false;
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
        child: SingleChildScrollView(
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
                        _downloadPending ||
                            _recorder.recording ||
                            _recorder.state == ReaderBaselineState.flushing
                        ? null
                        : () {
                            _resetReport();
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
                        ? _showSummary
                        : null,
                    child: const Text('查看摘要'),
                  ),
                  if (kIsWeb || widget.saveReportForTesting != null)
                    OutlinedButton(
                      onPressed:
                          _recorder.state == ReaderBaselineState.stopped &&
                              !_downloadPending
                          ? _download
                          : null,
                      child: const Text('下载 JSON'),
                    ),
                  if (!kIsWeb)
                    OutlinedButton(
                      onPressed: _recorder.state == ReaderBaselineState.stopped
                          ? _copy
                          : null,
                      child: const Text('复制 JSON'),
                    ),
                ],
              ),
              if (_recorder.state == ReaderBaselineState.stopped)
                Text('事件 ${_recorder.eventCount}；帧样本 ${_recorder.frameCount}'),
              if (_exportStatus != null) Text(_exportStatus!),
              if (_summaryVisible) ...[
                SelectableText(
                  _summary!,
                  key: const ValueKey('reader-baseline-summary'),
                ),
                const Text('JSON 短预览（最多 1024 字符；完整报告通过导出获取）'),
                SelectableText(
                  _preview!,
                  key: const ValueKey('reader-baseline-preview'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  void _prepareReport() {
    if (_json != null) return;
    final report = _recorder.export();
    final json = const JsonEncoder.withIndent('  ').convert(report);
    _json = json;
    final capture = report['capture']! as Map<String, Object?>;
    _summary =
        '${report['schema']}\n'
        '事件 ${_recorder.eventCount}；帧样本 ${_recorder.frameCount}\n'
        '帧计时关联：${capture['frameTimingStatus']}；截断：${capture['truncated']}\n'
        '完整 JSON：${utf8.encode(json).length} 字节\n'
        '未采集物理呈现、RSS、GPU 内存和解码 CPU 时间。';
    _preview = json.length <= 1024 ? json : json.substring(0, 1024);
  }

  void _showSummary() {
    _prepareReport();
    // Only short, bounded text participates in layout and the accessibility DOM.
    _exportSemantics ??= SemanticsBinding.instance.ensureSemantics();
    setState(() => _summaryVisible = true);
  }

  Future<void> _download() async {
    _prepareReport();
    final name = 'karuyomi-reader-baseline-${_recorder.session}.json';
    final file = _downloadFile ??= XFile.fromData(
      Uint8List.fromList(utf8.encode(_json!)),
      mimeType: 'application/json',
      name: name,
      path: name,
    );
    setState(() {
      _downloadPending = true;
      _exportStatus = null;
    });
    try {
      // cross_file clicks its Web download anchor before its first await,
      // retaining this button's user activation. It does not confirm saving.
      await (widget.saveReportForTesting?.call(file) ?? file.saveTo(name));
      if (mounted) setState(() => _exportStatus = '已请求下载 JSON');
    } catch (_) {
      if (mounted) setState(() => _exportStatus = '下载未完成，请重试。');
    } finally {
      if (mounted) setState(() => _downloadPending = false);
    }
  }

  Future<void> _copy() async {
    _prepareReport();
    try {
      await Clipboard.setData(ClipboardData(text: _json!));
      if (mounted) setState(() => _exportStatus = '已请求复制 JSON');
    } catch (_) {
      if (mounted) setState(() => _exportStatus = '复制未完成，请重试。');
    }
  }

  void _resetReport() {
    final file = _downloadFile;
    if (file != null) platform.releaseBaselineDownload(file.path);
    _downloadFile = null;
    _json = null;
    _summary = null;
    _preview = null;
    _exportStatus = null;
    _summaryVisible = false;
    _exportSemantics?.dispose();
    _exportSemantics = null;
  }

  @override
  void dispose() {
    _resetReport();
    _recorder.removeListener(_changed);
    _recorder.dispose();
    super.dispose();
  }
}
