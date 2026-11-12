// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One subscription serves the shelf and every visible Source list; list rows
/// derive their saved status from this view instead of requesting each manga.

@ProviderFor(libraryView)
final libraryViewProvider = LibraryViewFamily._();

/// One subscription serves the shelf and every visible Source list; list rows
/// derive their saved status from this view instead of requesting each manga.

final class LibraryViewProvider
    extends
        $FunctionalProvider<
          AsyncValue<LibraryView>,
          LibraryView,
          Stream<LibraryView>
        >
    with $FutureModifier<LibraryView>, $StreamProvider<LibraryView> {
  /// One subscription serves the shelf and every visible Source list; list rows
  /// derive their saved status from this view instead of requesting each manga.
  LibraryViewProvider._({
    required LibraryViewFamily super.from,
    required LibraryRepository super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'libraryViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$libraryViewHash();

  @override
  String toString() {
    return r'libraryViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<LibraryView> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LibraryView> create(Ref ref) {
    final argument = this.argument as LibraryRepository;
    return libraryView(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LibraryViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$libraryViewHash() => r'98aff7dff97b1d530310781103bfde0eb54b269c';

/// One subscription serves the shelf and every visible Source list; list rows
/// derive their saved status from this view instead of requesting each manga.

final class LibraryViewFamily extends $Family
    with $FunctionalFamilyOverride<Stream<LibraryView>, LibraryRepository> {
  LibraryViewFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'libraryViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One subscription serves the shelf and every visible Source list; list rows
  /// derive their saved status from this view instead of requesting each manga.

  LibraryViewProvider call(LibraryRepository repository) =>
      LibraryViewProvider._(argument: repository, from: this);

  @override
  String toString() => r'libraryViewProvider';
}

@ProviderFor(mangaState)
final mangaStateProvider = MangaStateFamily._();

final class MangaStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<wire.MangaState?>,
          wire.MangaState?,
          Stream<wire.MangaState?>
        >
    with $FutureModifier<wire.MangaState?>, $StreamProvider<wire.MangaState?> {
  MangaStateProvider._({
    required MangaStateFamily super.from,
    required (BusinessStateClient, String) super.argument,
  }) : super(
         retry: noAutomaticRetry,
         name: r'mangaStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mangaStateHash();

  @override
  String toString() {
    return r'mangaStateProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<wire.MangaState?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<wire.MangaState?> create(Ref ref) {
    final argument = this.argument as (BusinessStateClient, String);
    return mangaState(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MangaStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mangaStateHash() => r'f64cefc9f9f38116ce60500c5fee123ec0e71203';

final class MangaStateFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<wire.MangaState?>,
          (BusinessStateClient, String)
        > {
  MangaStateFamily._()
    : super(
        retry: noAutomaticRetry,
        name: r'mangaStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MangaStateProvider call(BusinessStateClient client, String mangaKey) =>
      MangaStateProvider._(argument: (client, mangaKey), from: this);

  @override
  String toString() => r'mangaStateProvider';
}
