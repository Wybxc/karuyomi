import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_appearance.dart';

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
  Widget build(BuildContext context) => GlassScaffold(
    enableBackgroundSampling: false,
    extendBody: false,
    backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
    appBar: GlassAppBar.pinned(
      backgroundColor: AppAppearance.chromeColor(context),
      backButton: false,
      title: title,
    ),
    body: SafeArea(
      top: false,
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
