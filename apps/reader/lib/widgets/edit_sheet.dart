import 'package:cupertino_ui/cupertino_ui.dart';

/// Single-page edits use the standard navigation bar for dismissal and commit.
/// Each editor retains its own scrolling content, draft and close policy.
class const EditSheet({
  super.key,
  required final Widget title,
  required final Widget content,
  final Widget? leading,
  final Widget? trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      leading: leading,
      middle: title,
      trailing: trailing,
    ),
    child: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: content,
        ),
      ),
    ),
  );
}
