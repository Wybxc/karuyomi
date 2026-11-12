import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/library_repository.dart';
import '../../state/account_providers.dart';

part 'library_providers.g.dart';

/// One subscription serves the shelf and every visible Source list; list rows
/// derive their saved status from this view instead of requesting each manga.
@Riverpod(retry: noAutomaticRetry)
Stream<LibraryView> libraryView(Ref ref, LibraryRepository repository) =>
    repository.watchView();

@Riverpod(retry: noAutomaticRetry)
Stream<wire.MangaState?> mangaState(
  Ref ref,
  BusinessStateClient client,
  String mangaKey,
) => client.watchManga(mangaKey);
