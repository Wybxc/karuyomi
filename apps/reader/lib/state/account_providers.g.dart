// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A read dependency for a verified identity. The catalog continues to own the
/// business client and runtime; unsubscribing never closes either of them.

@ProviderFor(confirmedAccount)
final confirmedAccountProvider = ConfirmedAccountFamily._();

/// A read dependency for a verified identity. The catalog continues to own the
/// business client and runtime; unsubscribing never closes either of them.

final class ConfirmedAccountProvider
    extends
        $FunctionalProvider<
          ConfirmedAccount?,
          ConfirmedAccount?,
          ConfirmedAccount?
        >
    with $Provider<ConfirmedAccount?> {
  /// A read dependency for a verified identity. The catalog continues to own the
  /// business client and runtime; unsubscribing never closes either of them.
  ConfirmedAccountProvider._({
    required ConfirmedAccountFamily super.from,
    required CatalogController super.argument,
  }) : super(
         retry: null,
         name: r'confirmedAccountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$confirmedAccountHash();

  @override
  String toString() {
    return r'confirmedAccountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ConfirmedAccount?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConfirmedAccount? create(Ref ref) {
    final argument = this.argument as CatalogController;
    return confirmedAccount(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConfirmedAccount? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConfirmedAccount?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConfirmedAccountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$confirmedAccountHash() => r'a7ba6ae619760d37b32610590fa903549fd37847';

/// A read dependency for a verified identity. The catalog continues to own the
/// business client and runtime; unsubscribing never closes either of them.

final class ConfirmedAccountFamily extends $Family
    with $FunctionalFamilyOverride<ConfirmedAccount?, CatalogController> {
  ConfirmedAccountFamily._()
    : super(
        retry: null,
        name: r'confirmedAccountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A read dependency for a verified identity. The catalog continues to own the
  /// business client and runtime; unsubscribing never closes either of them.

  ConfirmedAccountProvider call(CatalogController catalog) =>
      ConfirmedAccountProvider._(argument: catalog, from: this);

  @override
  String toString() => r'confirmedAccountProvider';
}
