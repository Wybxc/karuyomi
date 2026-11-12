// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.

@ProviderFor(SettingsController)
final settingsControllerProvider = SettingsControllerFamily._();

/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.
final class SettingsControllerProvider
    extends $NotifierProvider<SettingsController, SettingsState> {
  /// One editor per verified catalog identity and global/manga scope. Submitted
  /// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.
  SettingsControllerProvider._({
    required SettingsControllerFamily super.from,
    required (CatalogController, SettingsRepository?, {String? mangaKey})
    super.argument,
  }) : super(
         retry: null,
         name: r'settingsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @override
  String toString() {
    return r'settingsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SettingsController create() => SettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SettingsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$settingsControllerHash() =>
    r'1a06a59042bdc92d3b589b930c1189c4a5b571fa';

/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.

final class SettingsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SettingsController,
          SettingsState,
          SettingsState,
          SettingsState,
          (CatalogController, SettingsRepository?, {String? mangaKey})
        > {
  SettingsControllerFamily._()
    : super(
        retry: null,
        name: r'settingsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One editor per verified catalog identity and global/manga scope. Submitted
  /// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.

  SettingsControllerProvider call(
    CatalogController catalog,
    SettingsRepository? repository, {
    String? mangaKey,
  }) => SettingsControllerProvider._(
    argument: (catalog, repository, mangaKey: mangaKey),
    from: this,
  );

  @override
  String toString() => r'settingsControllerProvider';
}

/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.

abstract class _$SettingsController extends $Notifier<SettingsState> {
  late final _$args =
      ref.$arg as (CatalogController, SettingsRepository?, {String? mangaKey});
  CatalogController get catalog => _$args.$1;
  SettingsRepository? get repository => _$args.$2;
  String? get mangaKey => _$args.mangaKey;

  SettingsState build(
    CatalogController catalog,
    SettingsRepository? repository, {
    String? mangaKey,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SettingsState, SettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SettingsState, SettingsState>,
              SettingsState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, mangaKey: _$args.mangaKey),
    );
  }
}
