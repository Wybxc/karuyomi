// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_device_settings.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(readerDeviceStorage)
final readerDeviceStorageProvider = ReaderDeviceStorageProvider._();

final class ReaderDeviceStorageProvider
    extends
        $FunctionalProvider<
          SharedPreferencesAsync,
          SharedPreferencesAsync,
          SharedPreferencesAsync
        >
    with $Provider<SharedPreferencesAsync> {
  ReaderDeviceStorageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readerDeviceStorageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readerDeviceStorageHash();

  @$internal
  @override
  $ProviderElement<SharedPreferencesAsync> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SharedPreferencesAsync create(Ref ref) {
    return readerDeviceStorage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SharedPreferencesAsync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SharedPreferencesAsync>(value),
    );
  }
}

String _$readerDeviceStorageHash() =>
    r'b35bfb293115a5611ae6a1d923fb85f59a71d798';

@ProviderFor(effectiveReaderDevicePreferences)
final effectiveReaderDevicePreferencesProvider =
    EffectiveReaderDevicePreferencesFamily._();

final class EffectiveReaderDevicePreferencesProvider
    extends
        $FunctionalProvider<
          EffectiveReaderDevicePreferences,
          EffectiveReaderDevicePreferences,
          EffectiveReaderDevicePreferences
        >
    with $Provider<EffectiveReaderDevicePreferences> {
  EffectiveReaderDevicePreferencesProvider._({
    required EffectiveReaderDevicePreferencesFamily super.from,
    required ReaderDeviceScope? super.argument,
  }) : super(
         retry: null,
         name: r'effectiveReaderDevicePreferencesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$effectiveReaderDevicePreferencesHash();

  @override
  String toString() {
    return r'effectiveReaderDevicePreferencesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<EffectiveReaderDevicePreferences> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  EffectiveReaderDevicePreferences create(Ref ref) {
    final argument = this.argument as ReaderDeviceScope?;
    return effectiveReaderDevicePreferences(ref, scope: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EffectiveReaderDevicePreferences value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EffectiveReaderDevicePreferences>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EffectiveReaderDevicePreferencesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$effectiveReaderDevicePreferencesHash() =>
    r'30431aa42faf041f13b810fd1276a4e9f3af31ce';

final class EffectiveReaderDevicePreferencesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          EffectiveReaderDevicePreferences,
          ReaderDeviceScope?
        > {
  EffectiveReaderDevicePreferencesFamily._()
    : super(
        retry: null,
        name: r'effectiveReaderDevicePreferencesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  EffectiveReaderDevicePreferencesProvider call({ReaderDeviceScope? scope}) =>
      EffectiveReaderDevicePreferencesProvider._(argument: scope, from: this);

  @override
  String toString() => r'effectiveReaderDevicePreferencesProvider';
}

@ProviderFor(ReaderDeviceSettings)
final readerDeviceSettingsProvider = ReaderDeviceSettingsFamily._();

final class ReaderDeviceSettingsProvider
    extends $AsyncNotifierProvider<ReaderDeviceSettings, ReaderDeviceState> {
  ReaderDeviceSettingsProvider._({
    required ReaderDeviceSettingsFamily super.from,
    required ReaderDeviceScope? super.argument,
  }) : super(
         retry: null,
         name: r'readerDeviceSettingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$readerDeviceSettingsHash();

  @override
  String toString() {
    return r'readerDeviceSettingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReaderDeviceSettings create() => ReaderDeviceSettings();

  @override
  bool operator ==(Object other) {
    return other is ReaderDeviceSettingsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$readerDeviceSettingsHash() =>
    r'edde8e511cffc46b95ae79b5069d6d1964b51049';

final class ReaderDeviceSettingsFamily extends $Family
    with
        $ClassFamilyOverride<
          ReaderDeviceSettings,
          AsyncValue<ReaderDeviceState>,
          ReaderDeviceState,
          FutureOr<ReaderDeviceState>,
          ReaderDeviceScope?
        > {
  ReaderDeviceSettingsFamily._()
    : super(
        retry: null,
        name: r'readerDeviceSettingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ReaderDeviceSettingsProvider call({ReaderDeviceScope? scope}) =>
      ReaderDeviceSettingsProvider._(argument: scope, from: this);

  @override
  String toString() => r'readerDeviceSettingsProvider';
}

abstract class _$ReaderDeviceSettings
    extends $AsyncNotifier<ReaderDeviceState> {
  late final _$args = ref.$arg as ReaderDeviceScope?;
  ReaderDeviceScope? get scope => _$args;

  FutureOr<ReaderDeviceState> build({ReaderDeviceScope? scope});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ReaderDeviceState>, ReaderDeviceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ReaderDeviceState>, ReaderDeviceState>,
              AsyncValue<ReaderDeviceState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(scope: _$args));
  }
}
