import 'package:material_ui/material_ui.dart';

import '../../data/cover_repository.dart';
import '../../data/library_repository.dart';
import '../covers/custom_cover.dart';
import 'catalog_controller.dart';

/// Only confirmed account covers use the existing verified byte channel. Until
/// Source thumbnails have a formal resource channel, they use a placeholder.
class MangaListTile extends StatelessWidget {
  const MangaListTile({
    super.key,
    required this.manga,
    required this.onTap,
    this.libraryEntry,
    this.covers,
  });
  final MangaEntry manga;
  final VoidCallback? onTap;
  final LibraryEntry? libraryEntry;
  final CoverRepository? covers;

  @override
  Widget build(BuildContext context) => ListTile(
    minVerticalPadding: 12,
    leading: covers != null
        ? CustomCover(repository: covers!, cover: libraryEntry?.customCover)
        : SizedBox(
            width: 48,
            height: 64,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.menu_book_outlined),
            ),
          ),
    title: Text(manga.title),
    subtitle: manga.author == null
        ? null
        : Text(manga.author!, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: libraryEntry != null
        ? const Tooltip(
            message: '已在书架',
            child: Icon(Icons.collections_bookmark),
          )
        : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
