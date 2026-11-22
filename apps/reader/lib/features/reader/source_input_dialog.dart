import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../widgets/app_routes.dart';

Future<String?> showSourceInputDialog(
  BuildContext context, {
  required String sourceName,
  required wire.SourceInputPrompt prompt,
  required Future<void> operationEnded,
}) async {
  if (!context.mounted) return null;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = AppDialogRoute<String>(
    context: context,
    builder: (_) => _SourceInputDialog(sourceName: sourceName, prompt: prompt),
  );
  final result = navigator.push(route);
  var dismissed = false;
  unawaited(
    operationEnded.then((_) {
      if (!dismissed && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }),
  );
  final text = await result;
  dismissed = true;
  await route.completed;
  return text;
}

class const _SourceInputDialog({
  required final String sourceName,
  required final wire.SourceInputPrompt prompt,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: prompt.initialValue);
    final value = useValueListenable(controller).text;
    final revealing = useState(false);
    final closing = useRef(false);
    final fits = wire.sourceInputTextFits(value);
    final canSubmit = fits && (!prompt.required || value.isNotEmpty);

    void close([String? text]) {
      if (closing.value || ModalRoute.of(context)?.isCurrent != true) return;
      closing.value = true;
      Navigator.pop(context, text);
    }

    return CupertinoAlertDialog(
      title: Text(prompt.title.isEmpty ? '漫画源需要输入' : prompt.title),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('来源 · $sourceName'),
          if (prompt.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(prompt.message),
          ],
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: controller,
            placeholder: prompt.hasHint() ? prompt.hint : null,
            autofocus: true,
            obscureText: prompt.password && !revealing.value,
            autocorrect: !prompt.password,
            enableSuggestions: !prompt.password,
            enableIMEPersonalizedLearning: !prompt.password,
            autofillHints: null,
            textInputAction: TextInputAction.done,
          ),
          if (!fits) const Text('输入内容过长'),
        ],
      ),
      actions: [
        CupertinoDialogAction(onPressed: close, child: const Text('取消')),
        if (prompt.password)
          CupertinoDialogAction(
            onPressed: () => revealing.value = !revealing.value,
            child: Text(revealing.value ? '隐藏密码' : '显示密码'),
          ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: canSubmit ? () => close(controller.text) : null,
          child: Text(prompt.password ? '确认' : '提交'),
        ),
      ],
    );
  }
}
