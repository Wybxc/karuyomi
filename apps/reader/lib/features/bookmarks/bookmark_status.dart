import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'chapter_bookmarks_controller.dart';

class const BookmarkStatus({
  super.key,
  required final ChapterBookmarksController controller,
  final bool enabled = true,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.busy) const CupertinoActivityIndicator(),
        if (controller.error case final error?) Text(error),
        if (controller.pending != null) const Text('本会话有尚未确认的书签操作；刷新不会自动重发。'),
        Wrap(
          spacing: 8,
          children: [
            CupertinoButton(
              onPressed: enabled && controller.canRefresh
                  ? () => unawaited(controller.refresh())
                  : null,
              child: const Text('刷新书签'),
            ),
            if (controller.pending != null)
              CupertinoButton(
                onPressed: enabled && controller.canRetry
                    ? () => unawaited(controller.retry())
                    : null,
                child: const Text('重试原书签操作'),
              ),
          ],
        ),
      ],
    );
  }
}

class const ChapterBookmarkButton({
  super.key,
  required final ChapterBookmarksController controller,
  required final String chapterKey,
  required final String chapterName,
  final bool enabled = true,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final bookmarked = controller.contains(chapterKey);
    return CupertinoButton(
      key: ValueKey('chapter-bookmark-$chapterKey'),
      onPressed: enabled && controller.canEdit
          ? () => unawaited(controller.setBookmarked(chapterKey, !bookmarked))
          : null,
      padding: const EdgeInsets.all(8),
      child: Icon(
        bookmarked ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
        semanticLabel: '${bookmarked ? '移除章节书签' : '标记章节书签'} $chapterName',
      ),
    );
  }
}
