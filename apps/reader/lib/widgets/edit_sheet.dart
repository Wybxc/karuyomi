import 'package:cupertino_ui/cupertino_ui.dart';

/// Shared layout for server-backed edits: scrolling content and visible actions
/// stay above the keyboard. Each editor retains its own draft and close policy.
class const EditSheet({
  super.key,
  required final Widget title,
  required final Widget content,
  required final List<Widget> actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      middle: title,
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: content,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, children: actions),
          ),
        ],
      ),
    ),
  );
}
