import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:source_runtime/source_runtime.dart';

import '../../widgets/app_routes.dart';

String sourceErrorDetails(Object failure, {required String operation}) {
  final message = switch (failure) {
    RuntimeException(:final message) => message,
    FormatException(:final message) => message,
    _ => failure.toString(),
  };
  final redacted = message
      .replaceAllMapped(RegExp(r'https?://[^\s<>"\)]+', caseSensitive: false), (
        match,
      ) {
        final url = Uri.tryParse(match.group(0)!);
        if (url == null || !url.hasAuthority) return '网址已隐藏';
        return Uri(
          scheme: url.scheme,
          host: url.host,
          port: url.hasPort ? url.port : null,
          path: url.path,
        ).toString();
      })
      .replaceAllMapped(
        RegExp(
          r'(authorization|cookie|password|token)\s*[:=][^\r\n]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)} 已隐藏',
      );
  return [
    '操作 $operation',
    if (failure is RuntimeException) '错误码 ${failure.code.name}',
    if (failure is RuntimeException && failure.javaClass != null)
      failure.javaClass!,
    if (redacted.isNotEmpty) String.fromCharCodes(redacted.runes.take(2000)),
  ].join('\n');
}

class const SourceErrorDetailsButton({super.key, required final String details})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoButton(
    onPressed: () => showAppDialog<void>(
      context: context,
      builder: (_) => _SourceErrorDetailsDialog(details: details),
    ),
    child: const Text('查看错误详情'),
  );
}

class const _SourceErrorDetailsDialog({required final String details})
    extends StatefulWidget {
  @override
  State<_SourceErrorDetailsDialog> createState() =>
      _SourceErrorDetailsDialogState();
}

class _SourceErrorDetailsDialogState extends State<_SourceErrorDetailsDialog> {
  String _copyLabel = '复制错误';

  Future<void> _copy() async {
    String label;
    try {
      await Clipboard.setData(ClipboardData(text: widget.details));
      label = '已复制';
    } catch (_) {
      label = '复制失败，重试';
    }
    if (mounted) setState(() => _copyLabel = label);
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: const Text('错误详情'),
    content: Text(widget.details, textAlign: TextAlign.start),
    actions: [
      CupertinoDialogAction(
        onPressed: _copy,
        child: Semantics(liveRegion: true, child: Text(_copyLabel)),
      ),
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
