import 'package:cupertino_ui/cupertino_ui.dart';

import '../../data/cover_repository.dart';
import '../../data/library_repository.dart';
import '../covers/custom_cover.dart';
import 'catalog_controller.dart';

/// Only confirmed account covers use the existing verified byte channel. Until
/// Source thumbnails have a formal resource channel, they use a placeholder.
class const MangaListTile({
  super.key,
  required final MangaEntry manga,
  required final VoidCallback? onTap,
  final LibraryEntry? libraryEntry,
  final CoverRepository? covers,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: CupertinoListTile(
      leading: covers != null
          ? CustomCover(repository: covers!, cover: libraryEntry?.customCover)
          : SizedBox(
              width: 48,
              height: 64,
              child: ColoredBox(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                child: const Icon(CupertinoIcons.book),
              ),
            ),
      title: Text(manga.title),
      subtitle: manga.author == null
          ? null
          : Text(manga.author!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: libraryEntry != null
          ? Semantics(label: '已在书架', child: Icon(CupertinoIcons.book_fill))
          : const Icon(CupertinoIcons.chevron_right),
    ),
  );
}
