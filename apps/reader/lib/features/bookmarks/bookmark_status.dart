import 'dart:async';

import 'package:flutter/material.dart';

import 'chapter_bookmarks_controller.dart';

class BookmarkStatus extends StatelessWidget {
  const BookmarkStatus({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final ChapterBookmarksController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.busy) const LinearProgressIndicator(),
        if (controller.error case final error?) Text(error),
        if (controller.pending != null) const Text('本会话有尚未确认的书签操作；刷新不会自动重发。'),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: enabled && controller.canRefresh
                  ? () => unawaited(controller.refresh())
                  : null,
              icon: const Icon(Icons.sync),
              label: const Text('刷新书签'),
            ),
            if (controller.pending != null)
              TextButton(
                onPressed: enabled && controller.canRetry
                    ? () => unawaited(controller.retry())
                    : null,
                child: const Text('重试原书签操作'),
              ),
          ],
        ),
      ],
    ),
  );
}

class ChapterBookmarkButton extends StatelessWidget {
  const ChapterBookmarkButton({
    super.key,
    required this.controller,
    required this.chapterKey,
    required this.chapterName,
    this.enabled = true,
  });

  final ChapterBookmarksController controller;
  final String chapterKey;
  final String chapterName;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final bookmarked = controller.contains(chapterKey);
      return IconButton(
        key: ValueKey('chapter-bookmark-$chapterKey'),
        tooltip: '${bookmarked ? '移除章节书签' : '标记章节书签'} $chapterName',
        icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
        onPressed: enabled && controller.canEdit
            ? () => unawaited(controller.setBookmarked(chapterKey, !bookmarked))
            : null,
      );
    },
  );
}
