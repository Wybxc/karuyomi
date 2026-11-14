import 'package:cupertino_ui/cupertino_ui.dart';

import '../../data/cover_repository.dart';
import '../../data/library_repository.dart';
import '../../theme/app_theme.dart';
import '../covers/custom_cover.dart';

/// A book cover remains the primary browsing target. Private covers keep their
/// verified byte channel; Source thumbnail URLs never bypass the host here.
class const MangaCoverTile({
  super.key,
  required final String title,
  required final VoidCallback? onPressed,
  final LibraryEntry? entry,
  final CoverRepository? covers,
  final VoidCallback? onLongPress,
  final bool? selected,
  final Widget? badge,
  final VoidCallback? onContinue,
  final Key? continueKey,
  final String? continueLabel,
  final Widget? menu,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: AspectRatio(
      aspectRatio: 2 / 3,
      child: LayoutBuilder(
        builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onPressed,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (covers case final repository?)
                        CustomCover(
                          repository: repository,
                          cover: entry?.customCover,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                        )
                      else
                        ColoredBox(
                          color: AppColors.groupedSurface.resolveFrom(context),
                          child: const Center(child: Icon(CupertinoIcons.book)),
                        ),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0xE6000000)],
                              stops: [0.55, 1],
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            8,
                            continueLabel == null ? 8 : 48,
                            8,
                          ),
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFFFFFF),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (badge case final badge?)
                Positioned(top: 6, left: 6, child: badge),
              if (menu case final actions?)
                Positioned(top: 0, right: 0, child: actions),
              if (continueLabel != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: CupertinoButton(
                    key: continueKey,
                    padding: const EdgeInsets.all(8),
                    color: AppColors.accent.resolveFrom(context),
                    borderRadius: BorderRadius.circular(32),
                    onPressed: onContinue,
                    child: Icon(
                      CupertinoIcons.play_fill,
                      size: 20,
                      color: AppColors.onAccent.resolveFrom(context),
                      semanticLabel: continueLabel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
