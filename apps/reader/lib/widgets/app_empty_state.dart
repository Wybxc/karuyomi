import 'package:cupertino_ui/cupertino_ui.dart';

import '../theme/app_theme.dart';

class const AppEmptyState({
  super.key,
  required final Widget leading,
  required final String title,
  required final String message,
  final ({String label, VoidCallback onPressed})? action,
  final bool announce = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = CupertinoTheme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(height: 8),
          Semantics(
            header: true,
            liveRegion: announce,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.navTitleTextStyle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.textStyle.copyWith(
              color: AppColors.secondaryLabel.resolveFrom(context),
              fontSize: 13,
            ),
          ),
          if (action case final action?) ...[
            const SizedBox(height: 8),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onPressed: action.onPressed,
              child: Text(action.label),
            ),
          ],
        ],
      ),
    );
  }
}
