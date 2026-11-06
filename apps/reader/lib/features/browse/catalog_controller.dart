import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../runtime/runtime_platform_types.dart';
import '../../runtime/cover_transport.dart';
import '../../data/business_state_client.dart';
import '../../data/business_state_validation.dart';
import '../../data/bookmark_repository.dart';
import '../../data/settings_repository.dart';
import '../../data/source_preferences_repository.dart';
import '../../data/source_preferences_validation.dart';
import '../../data/progress_repository.dart';
import '../../data/reading_progress.dart';
import '../../data/library_repository.dart';
import '../reader/reading_progress_controller.dart';

enum ServiceStatus {
  disconnected,
  connecting,
  ready,
  loginRequired,
  denied,
  failed,
}

final _catalogSourceId = RegExp(r'^-?\d{1,19}$');
final _catalogMinSourceId = BigInt.parse('-9223372036854775808');
final _catalogMaxSourceId = BigInt.parse('9223372036854775807');

bool _validCatalogSourceId(String id) {
  if (!_catalogSourceId.hasMatch(id)) return false;
  final value = BigInt.parse(id);
  return value >= _catalogMinSourceId && value <= _catalogMaxSourceId;
}

List<wire.CatalogSource> _catalogSources(
  Iterable<String> sourceIds,
  Iterable<wire.CatalogSource> sources,
) {
  final ids = sourceIds.toList(growable: false);
  final metadata = sources.toList(growable: false);
  if (ids.isEmpty ||
      ids.length > 500 ||
      metadata.length != ids.length ||
      ids.toSet().length != ids.length ||
      ids.any((id) => !_validCatalogSourceId(id)) ||
      metadata.any(
        (source) =>
            !_validCatalogSourceId(source.id) ||
            source.name.trim().isEmpty ||
            source.name.length > 500 ||
            source.lang.length > 64,
      )) {
    throw const FormatException('扩展目录中的漫画源资料不完整');
  }
  final metadataIds = metadata.map((source) => source.id).toSet();
  if (metadataIds.length != ids.length || !metadataIds.containsAll(ids)) {
    throw const FormatException('扩展目录中的漫画源标识不匹配');
  }
  return List.unmodifiable(
    metadata.map((source) => source.deepCopy()..freeze()),
  );
}

final class CatalogBuild {
  const CatalogBuild._({
    required this.id,
    required this.packageName,
    required this.repoId,
    required this.version,
    required this.manifestPath,
    required this.sources,
  });
  final String id;
  final String packageName;
  final String repoId;
  final String version;
  final String manifestPath;
  final List<wire.CatalogSource> sources;

  factory CatalogBuild.fromProto(wire.ExtensionBuildDescriptor value) {
    final id = value.buildId;
    final path = value.manifestPath;
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,200}$').hasMatch(id) ||
        path != '/extensions/builds/$id/manifest.json' ||
        value.packageName.isEmpty ||
        value.repoId.isEmpty ||
        value.repoId.length > 200 ||
        value.version.isEmpty) {
      throw const FormatException('扩展清单路径与构建不匹配');
    }
    return CatalogBuild._(
      id: id,
      packageName: value.packageName,
      repoId: value.repoId,
      version: value.version,
      manifestPath: path,
      sources: _catalogSources(value.sourceIds, value.sources),
    );
  }
}

final class MangaEntry {
  MangaEntry(wire.Manga value) : snapshot = value.deepCopy()..freeze() {
    if (value.title.isEmpty || value.url.isEmpty) {
      throw const FormatException('服务返回的数据不完整');
    }
  }
  final wire.Manga snapshot;
  String get title => snapshot.title;
  String get url => snapshot.url;
  String? get description =>
      snapshot.hasDescription() ? snapshot.description : null;
  String? get author => snapshot.hasAuthor() ? snapshot.author : null;
  String? get artist => snapshot.hasArtist() ? snapshot.artist : null;
  List<String> get genres => snapshot.genres;
}

final class ChapterEntry {
  ChapterEntry(wire.Chapter value) : snapshot = value.deepCopy()..freeze() {
    if (value.name.isEmpty || value.url.isEmpty) {
      throw const FormatException('服务返回的数据不完整');
    }
  }
  final wire.Chapter snapshot;
  String get name => snapshot.name;
  String get url => snapshot.url;
}

final class CatalogSourceRef {
  const CatalogSourceRef({
    required this.buildId,
    required this.sourceId,
    required this.generation,
  });
  final String buildId;
  final String sourceId;
  final String generation;
}

final class SourcePreferencesTarget {
  SourcePreferencesTarget({required this.build, required SourceInfo source})
    : source = source.deepCopy()..freeze();
  final CatalogBuild build;
  final SourceInfo source;
}

final class OpenedChapter {
  const OpenedChapter({
    required this.manifest,
    required this.provider,
    required this.generation,
    required this.title,
  });
  final ChapterManifest manifest;
  final ChapterPageProvider provider;
  final String generation;
  final String title;
}

String _readingKey(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

/// The UI keeps original Source snapshots for explicit manga/chapter references.
/// It never derives a source URL from an application route or a display label.
final class CatalogController extends ChangeNotifier {
  CatalogController({
    required this.api,
    required this.runtime,
    required this.rebuildRuntime,
    this.deploymentOrigin,
  }) {
    _subscription = runtime.events.listen(_onRuntimeEvent);
  }

  final ApiFetch api;
  CoverTransport? get _covers {
    final transport = api;
    if (transport is PlatformRuntime) return transport.coverTransport;
    return switch (transport) {
      CoverTransport covers => covers,
      _ => null,
    };
  }

  final SourceRuntime runtime;
  final Future<void> Function() rebuildRuntime;
  final Uri? deploymentOrigin;
  final _readingClients = <ReadingProgressController, int>{};
  Future<bool>? _progressClosing;

  BusinessStateClient? _businessClient;
  LibraryRepository? _library;
  ProgressRepository? _progress;
  BookmarkRepository? _bookmarks;
  SettingsRepository? _settings;
  SourcePreferencesRepository? _sourcePreferences;
  SourcePreferencesSnapshot? loadedSourcePreferences;
  final _sessionPreferenceValues =
      <(String, String), List<wire.PreferenceEntry>>{};
  final _preferenceRecoveries = <(String, String), SourcePreferencesTarget>{};
  String? _preferenceIdentity;
  String? _preferenceRequestId;

  SourcePreferencesRepository? get sourcePreferences =>
      _confirmedBusinessClient == null ? null : _sourcePreferences;

  List<SourcePreferencesTarget> get sourcePreferenceRecoveries =>
      List.unmodifiable(_preferenceRecoveries.values);

  bool get sourcePreferencesBlocked =>
      activeBuild != null &&
      _preferenceRecoveries.keys.any(
        (key) => key.$1 == activeBuild!.packageName,
      );

  SourcePreferencesTarget? get currentPreferencesTarget =>
      activeBuild == null || activeSource == null
      ? null
      : SourcePreferencesTarget(build: activeBuild!, source: activeSource!);

  BusinessStateClient? get _confirmedBusinessClient {
    final transport = api;
    final origin =
        deploymentOrigin ??
        (transport is PlatformRuntime ? transport.origin : null);
    final verifiedSubject = subject;
    if (origin == null || verifiedSubject == null) return null;
    final identity = ProgressIdentity(origin: origin, subject: verifiedSubject);
    if (_preferenceIdentity != identity.key) {
      _sessionPreferenceValues.clear();
      _preferenceRecoveries.clear();
      loadedSourcePreferences = null;
      _preferenceIdentity = identity.key;
    }
    if (_businessClient?.identity.key != identity.key) {
      BusinessStateClient? retained;
      for (final client in _readingClients.keys) {
        if (client.repository.identity.key == identity.key) {
          retained = client.repository.client;
          retained.rebindApi(api, verifiedIdentity: identity, covers: _covers);
          break;
        }
      }
      _businessClient =
          retained ??
          BusinessStateClient(api: api, identity: identity, covers: _covers);
      _library = LibraryRepository(_businessClient!);
      _progress = ProgressRepository(_businessClient!);
      _bookmarks = BookmarkRepository(_businessClient!);
      _settings = SettingsRepository(_businessClient!);
      _sourcePreferences = SourcePreferencesRepository(_businessClient!);
    }
    return _businessClient;
  }

  ProgressRepository? get readingProgress =>
      _confirmedBusinessClient == null ? null : _progress;

  LibraryRepository? get library =>
      _confirmedBusinessClient == null ? null : _library;

  BookmarkRepository? get bookmarks =>
      _confirmedBusinessClient == null ? null : _bookmarks;

  SettingsRepository? get settings =>
      _confirmedBusinessClient == null ? null : _settings;

  ReadingProgressController? createReadingProgress(String mangaKey) {
    final repository = readingProgress;
    if (repository == null || _progressClosing != null) return null;
    for (final existing in _readingClients.keys) {
      if (existing.mangaKey == mangaKey &&
          existing.repository.identity.key == repository.identity.key) {
        _readingClients[existing] = _readingClients[existing]! + 1;
        return existing;
      }
    }
    final client = ReadingProgressController(
      repository: repository,
      mangaKey: mangaKey,
    );
    _readingClients[client] = 1;
    client.addListener(_notify);
    return client;
  }

  Future<void> releaseReadingProgress(ReadingProgressController client) async {
    final owners = _readingClients[client];
    if (owners == null || owners == 0) return;
    _readingClients[client] = owners - 1;
    await client.flush();
    _retireSavedProgress();
    _notify();
  }

  MangaResume? readingDraftResume(String mangaKey) {
    final identity = readingProgress?.identity.key;
    for (final client in _readingClients.keys) {
      if (client.unsaved &&
          client.mangaKey == mangaKey &&
          client.repository.identity.key == identity) {
        return client.draftResume;
      }
    }
    return null;
  }

  bool get hasUnsavedReadingProgress =>
      _readingClients.keys.any((client) => client.unsaved);

  /// Session drafts retain their verified identity across service replacement.
  List<ReadingProgressController> takeUnsavedReadingProgress() {
    final clients = _readingClients.keys
        .where((client) => client.unsaved)
        .toList();
    for (final client in clients) {
      _readingClients.remove(client);
      client.removeListener(_notify);
    }
    return clients;
  }

  bool adoptReadingProgress(ReadingProgressController client) {
    final sameIdentity =
        client.repository.identity.key == readingProgress?.identity.key;
    if (_progressClosing != null || !sameIdentity) return false;
    final clientState = client.repository.client;
    clientState.rebindApi(
      api,
      verifiedIdentity: readingProgress!.identity,
      covers: _covers,
    );
    if (!identical(_businessClient, clientState)) {
      _businessClient = clientState;
      _library = LibraryRepository(clientState);
      _progress = ProgressRepository(clientState);
      _bookmarks = BookmarkRepository(clientState);
      _settings = SettingsRepository(clientState);
      _sourcePreferences = SourcePreferencesRepository(clientState);
    }
    if (!_readingClients.containsKey(client)) {
      _readingClients[client] = 0;
      client.addListener(_notify);
    }
    return true;
  }

  Future<bool> flushReadingProgress() async {
    final identity = readingProgress?.identity.key;
    final results = await Future.wait(
      _readingClients.keys
          .where((client) => client.repository.identity.key == identity)
          .toList()
          .map((client) => client.flush()),
    );
    _retireSavedProgress();
    _notify();
    return results.every((saved) => saved) && !hasUnsavedReadingProgress;
  }

  void _retireSavedProgress() {
    if (_progressClosing != null) return;
    for (final entry in _readingClients.entries.toList()) {
      if (entry.value == 0 && !entry.key.unsaved) {
        _readingClients.remove(entry.key);
        entry.key.removeListener(_notify);
        entry.key.dispose();
      }
    }
  }

  /// Shutdown is best effort. Normal route exits retain dirty controllers for
  /// explicit retry, and cannot dispose their unsaved drafts as if persisted.
  Future<bool> closeReadingProgress() =>
      _progressClosing ??= _closeReadingProgress();

  Future<bool> _closeReadingProgress() async {
    final clients = _readingClients.keys.toList();
    final results = await Future.wait(clients.map((client) => client.flush()));
    for (final client in clients) {
      client.removeListener(_notify);
      client.dispose();
    }
    _readingClients.clear();
    return results.every((saved) => saved);
  }

  late final StreamSubscription<RuntimeEvent> _subscription;
  ServiceStatus status = ServiceStatus.disconnected;
  String? email;
  String? subject;
  String? error;
  bool busy = false;
  String? activity;
  List<CatalogBuild> builds = const [];
  CatalogBuild? activeBuild;
  RuntimeSession? session;
  SourceInfo? activeSource;
  List<MangaEntry> mangas = const [];
  bool hasNextPage = false;
  int page = 0;
  String query = '';
  String listing = 'popular';
  wire.FilterSnapshot? sourceFilterSnapshot;
  wire.FilterSelection? appliedSourceFilters;
  String? sourceFilterError;
  int _filterRequestEpoch = 0;
  String? _filterRequestId;
  bool _filterRequestLoadsSnapshot = false;
  String? lastBuildId;
  String? lastSourceId;
  int _requestSequence = 0;
  int _epoch = 0;
  bool _closed = false;
  bool _runtimeNeedsRebuild = false;
  bool _rebuildingRuntime = false;

  bool get accessPaused =>
      status == ServiceStatus.loginRequired || status == ServiceStatus.denied;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _onRuntimeEvent(RuntimeEvent event) {
    if (_closed) return;
    // A reconnect intentionally invalidates the old container before bootstrap.
    // Platform rebuild still owns Worker, WebView and native file cleanup.
    if (_rebuildingRuntime && event.code == RuntimeErrorCode.runtimeLost) {
      return;
    }
    if ({
      RuntimeErrorCode.runtimeLost,
      RuntimeErrorCode.accessRequired,
      RuntimeErrorCode.accessDenied,
      RuntimeErrorCode.timeout,
    }.contains(event.code)) {
      ++_epoch;
      busy = false;
      activity = null;
      _dropSession();
      error = event.code == RuntimeErrorCode.accessRequired
          ? '访问验证已失效，请重新登录'
          : event.code == RuntimeErrorCode.accessDenied
          ? '当前身份没有访问权限'
          : '运行容器已中断，请重新连接';
      status = event.code == RuntimeErrorCode.accessRequired
          ? ServiceStatus.loginRequired
          : event.code == RuntimeErrorCode.accessDenied
          ? ServiceStatus.denied
          : ServiceStatus.failed;
    }
    _notify();
  }

  void _clearSourceFilters() {
    ++_filterRequestEpoch;
    _filterRequestId = null;
    _filterRequestLoadsSnapshot = false;
    sourceFilterSnapshot = null;
    appliedSourceFilters = null;
    sourceFilterError = null;
  }

  void _dropSession() {
    _clearSourceFilters();
    session = null;
    activeSource = null;
    activeBuild = null;
    loadedSourcePreferences = null;
    mangas = const [];
    page = 0;
    hasNextPage = false;
  }

  Future<Object?> _get(String path) async {
    final reply = await api.fetchApi(path);
    final isStatic = path.startsWith('/extensions/');
    if (isStatic &&
        (reply.redirected ||
            reply.status != 200 ||
            !(reply.headers['content-type'] ?? '').contains(
              'application/json',
            ))) {
      throw StateError('扩展目录暂时不可用，请稍后重新连接');
    }
    if (reply.redirected || reply.status == 401) {
      throw const RuntimeException(RuntimeErrorCode.accessRequired, '请先通过访问验证');
    }
    if (reply.status == 403) {
      throw const RuntimeException(RuntimeErrorCode.accessDenied, '当前身份没有访问权限');
    }
    if (reply.status != 200) {
      throw StateError(
        reply.status == 503 ? '服务尚未配置完成，请稍后重试' : '服务请求失败（${reply.status}）',
      );
    }
    if (!(reply.headers['content-type'] ?? '').contains('application/json')) {
      throw const RuntimeException(
        RuntimeErrorCode.accessRequired,
        '访问验证已失效，请重新登录',
      );
    }
    return jsonDecode(reply.body);
  }

  Future<T?> _perform<T>(String label, Future<T> Function() action) async {
    if (busy || _closed) return null;
    final epoch = _epoch;
    busy = true;
    activity = label;
    error = null;
    _notify();
    try {
      return await action();
    } on RuntimeException catch (failure) {
      if (epoch == _epoch && !_closed) {
        error = switch (failure.code) {
          RuntimeErrorCode.accessRequired => '访问验证已失效，请重新登录',
          RuntimeErrorCode.accessDenied => '当前身份没有访问权限',
          RuntimeErrorCode.timeout => '漫画源响应超时，请重新连接后重试',
          RuntimeErrorCode.runtimeLost => '运行容器已中断，请重新连接',
          RuntimeErrorCode.unsupportedCapability => '这个漫画源功能暂未支持',
          RuntimeErrorCode.integrityError => '构建校验失败，请重新加载',
          RuntimeErrorCode.sourceError => '漫画源请求失败，请重试',
          RuntimeErrorCode.storageBusy => '这个漫画源已在其他标签页或窗口运行，请先关闭后再连接',
          RuntimeErrorCode.protocolError => '漫画源返回的数据与当前版本不兼容',
          _ => '漫画源请求失败，请稍后重试',
        };
        if (failure.code == RuntimeErrorCode.accessRequired) {
          status = ServiceStatus.loginRequired;
          _dropSession();
        } else if (failure.code == RuntimeErrorCode.accessDenied) {
          status = ServiceStatus.denied;
          _dropSession();
        } else if ({
          RuntimeErrorCode.runtimeLost,
          RuntimeErrorCode.timeout,
        }.contains(failure.code)) {
          _dropSession();
          status = ServiceStatus.failed;
        } else if (session == null) {
          status = ServiceStatus.failed;
        }
      }
      return null;
    } catch (failure) {
      if (epoch == _epoch && !_closed) {
        error = failure is FormatException
            ? failure.message
            : '连接未完成，请检查服务配置后重试';
        if (status == ServiceStatus.connecting) status = ServiceStatus.failed;
      }
      return null;
    } finally {
      if (epoch == _epoch && !_closed) {
        busy = false;
        activity = null;
        _notify();
      }
    }
  }

  Future<void> connect() async {
    if (busy || _closed) return;
    ++_epoch;
    await _perform('正在连接服务', () async {
      final epoch = _epoch;
      status = ServiceStatus.connecting;
      _dropSession();
      subject = null;
      email = null;
      builds = const [];
      _notify();
      // Confirm the cookie's current identity before attempting old drafts.
      // An old subject's rejected POST must not interrupt the new bootstrap.
      if (_runtimeNeedsRebuild) {
        _rebuildingRuntime = true;
        try {
          await rebuildRuntime();
        } finally {
          _rebuildingRuntime = false;
        }
        if (_closed || epoch != _epoch) return;
        _runtimeNeedsRebuild = false;
      }
      final bootstrap = wire.decodeProtoJson(
        wire.Bootstrap(),
        await _get('/api/bootstrap'),
      );
      if (_closed || epoch != _epoch) return;
      if (bootstrap.protocolVersion != protocolVersion) {
        throw const FormatException('客户端与服务版本不兼容');
      }
      final confirmedSubject = bootstrap.identity.subject;
      final confirmedEmail = bootstrap.identity.email;
      if (confirmedSubject.isEmpty || confirmedEmail.isEmpty) {
        throw const FormatException('服务返回的数据不完整');
      }
      final inventory = wire.decodeProtoJson(
        wire.ExtensionIndex(),
        await _get('/extensions/index.json'),
      );
      if (_closed || epoch != _epoch) return;
      if (inventory.schemaVersion != 1) {
        throw const FormatException('扩展索引版本不兼容');
      }
      final available = inventory.builds.map(CatalogBuild.fromProto).toList();
      if (available.length > 5000 ||
          available.map((build) => build.packageName).toSet().length !=
              available.length) {
        throw const FormatException('扩展索引必须每包只包含一个当前版本');
      }
      if (_closed || epoch != _epoch) return;
      subject = confirmedSubject;
      final state = _confirmedBusinessClient;
      if (state != null) {
        state.rebindApi(api, verifiedIdentity: state.identity, covers: _covers);
        for (final client in _readingClients.keys) {
          if (client.repository.identity.key == state.identity.key) {
            client.repository.client.rebindApi(
              api,
              verifiedIdentity: state.identity,
              covers: _covers,
            );
          }
        }
      }
      email = confirmedEmail;
      builds = List.unmodifiable(available);
      status = ServiceStatus.ready;
    });
  }

  Future<void> openBuild(CatalogBuild build) async {
    await _perform('正在加载漫画源', () => _loadBuild(build));
  }

  Future<void> _loadBuild(
    CatalogBuild build, {
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) return;
    lastBuildId = build.id;
    lastSourceId = null;
    final epoch = _epoch;
    final preferences = sourcePreferences;
    if (preferences == null) {
      throw StateError('Source settings identity is unavailable');
    }
    if (preferences.hasPendingPackage(build.packageName)) {
      throw const FormatException('这个扩展有未确认的设置，请先处理原设置操作。');
    }
    if (_preferenceRecoveries.keys.any((key) => key.$1 == build.packageName)) {
      await _rebuildForPreferences();
      if (_closed || epoch != _epoch || shouldContinue?.call() == false) return;
    }
    _dropSession();
    final confirmedPreferences = await preferences.load(build.packageName);
    if (_closed || epoch != _epoch || shouldContinue?.call() == false) return;
    final identity = subject;
    if (identity == null) {
      throw const RuntimeException(RuntimeErrorCode.accessRequired, '身份未确认');
    }
    final response = await _get(build.manifestPath);
    if (_closed || epoch != _epoch || shouldContinue?.call() == false) return;
    final manifest = wire.decodeProtoJson(wire.BuildManifest(), response);
    if (manifest.buildId != build.id ||
        !manifest.hasBundle() ||
        manifest.bundle.sha256.isEmpty) {
      throw const FormatException('构建标识不匹配');
    }
    List<wire.CatalogSource> manifestSources;
    try {
      manifestSources = _catalogSources(manifest.sourceIds, manifest.sources);
    } on FormatException {
      throw const FormatException('扩展资料与当前目录不匹配，请重新连接以刷新目录');
    }
    final expectedSources = {
      for (final source in build.sources) source.id: (source.name, source.lang),
    };
    if (manifest.packageName != build.packageName ||
        manifest.repoId != build.repoId ||
        manifest.version != build.version ||
        manifestSources.length != expectedSources.length ||
        manifestSources.any(
          (source) => expectedSources[source.id] != (source.name, source.lang),
        )) {
      throw const FormatException('扩展资料与当前目录不匹配，请重新连接以刷新目录');
    }
    final bootstrap = wire.PreferenceBootstrap(packageName: build.packageName);
    // Removed Sources retain their account values without being injected into
    // an extension that no longer constructs that namespace.
    final sourceIds = manifest.sourceIds.toSet();
    for (final id in sourceIds) {
      final entries = <String, wire.PreferenceEntry>{
        for (final entry in confirmedPreferences.source(id).entries)
          entry.key: entry,
        for (final entry
            in _sessionPreferenceValues[(build.packageName, id)] ??
                <wire.PreferenceEntry>[])
          entry.key: entry,
      };
      if (entries.isNotEmpty) {
        bootstrap.sources.add(
          wire.SourcePreferenceValues(
            sourceId: id,
            entries: canonicalPreferenceEntries(entries.values),
          ),
        );
      }
    }
    wire.validatePreferenceBootstrap(bootstrap);
    _runtimeNeedsRebuild = true;
    final loaded = await runtime.open(
      BuildDescriptor(
        buildId: build.id,
        manifestUri: Uri.parse(build.manifestPath),
        sha256: manifest.bundle.sha256,
        identity: identity,
        packageId: build.packageName,
        preferenceBootstrap: bootstrap,
      ),
    );
    if (_closed || epoch != _epoch || shouldContinue?.call() == false) return;
    activeBuild = build;
    session = loaded;
    loadedSourcePreferences = confirmedPreferences;
    _preferenceRecoveries.removeWhere((key, _) => key.$1 == build.packageName);
    activeSource = null;
    mangas = const [];
    page = 0;
    hasNextPage = false;
  }

  Future<SourceResult> _invoke(
    wire.SourceCall call, {
    void Function(String requestId)? onRequest,
    bool allowPreferenceEdit = false,
  }) async {
    if (sourcePreferencesBlocked && !allowPreferenceEdit) {
      throw const FormatException('漫画源设置尚未确认或需要重开，请先处理设置。');
    }
    final epoch = _epoch;
    final current = session;
    final build = activeBuild;
    final source = activeSource;
    if (current == null || build == null || source == null) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源未就绪');
    }
    call.requestId = 'ui-${++_requestSequence}';
    call.generation = current.generation;
    call.sourceId = source.id;
    call.timeoutMs = 30000;
    onRequest?.call(call.requestId);
    final result = await runtime.invoke(
      SourceRequest(packageId: build.packageName, call: call),
    );
    if (_closed ||
        epoch != _epoch ||
        session?.generation != current.generation) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源会话已失效');
    }
    return result;
  }

  Future<void> selectSource(
    SourceInfo source, {
    bool loadListing = true,
  }) async {
    if (busy || !_setSource(source)) return;
    if (loadListing) {
      await loadMangas();
    } else {
      _notify();
    }
  }

  bool _setSource(SourceInfo source) {
    if (!(session?.sources.any((value) => value.id == source.id) ?? false)) {
      return false;
    }
    _clearSourceFilters();
    activeSource = source;
    lastSourceId = source.id;
    mangas = const [];
    page = 0;
    hasNextPage = false;
    query = '';
    listing = 'popular';
    return true;
  }

  Future<void> loadMangas({
    String? search,
    String? operation,
    bool more = false,
  }) async {
    await _perform(
      '正在加载漫画',
      () => _loadListing(search: search, operation: operation, more: more),
    );
  }

  Future<void> _loadListing({
    String? search,
    String? operation,
    bool more = false,
    bool Function()? shouldContinue,
    wire.FilterSelection? filters,
    void Function(String requestId)? onRequest,
  }) async {
    if (shouldContinue?.call() == false) return;
    final selectedQuery = search ?? query;
    final selectedListing =
        operation ??
        (search != null
            ? (search.trim().isEmpty && appliedSourceFilters == null
                  ? 'popular'
                  : 'search')
            : listing);
    final selectedFilters = selectedListing == 'search'
        ? filters ?? appliedSourceFilters
        : null;
    final selectedPage = more ? page + 1 : 1;
    final call = switch (selectedListing) {
      'popular' => wire.SourceCall(
        popular: wire.PageRequest(page: selectedPage),
      ),
      'latest' => wire.SourceCall(latest: wire.PageRequest(page: selectedPage)),
      'search' => wire.SourceCall(
        search: wire.SearchRequest(
          page: selectedPage,
          query: selectedQuery,
          filters: selectedFilters?.deepCopy(),
        ),
      ),
      _ => throw const FormatException('未知漫画列表操作'),
    };
    final result = (await _invoke(call, onRequest: onRequest)).mangaPage;
    if (_closed || shouldContinue?.call() == false) return;
    final entries = result.mangas.map(MangaEntry.new).toList();
    mangas = more ? [...mangas, ...entries] : entries;
    page = selectedPage;
    query = selectedQuery;
    listing = selectedListing;
    appliedSourceFilters = selectedFilters?.deepCopy()?..freeze();
    hasNextPage = result.hasNextPage;
  }

  /// Filter descriptions and selections are disposable Source session state,
  /// independent of confirmed account settings and unapplied editor changes.
  Future<bool> loadSourceFilters({
    bool reset = false,
    bool Function()? shouldContinue,
    void Function(String requestId)? onRequest,
  }) async {
    if (_closed ||
        busy ||
        activeSource == null ||
        shouldContinue?.call() == false) {
      return false;
    }
    if (!reset && sourceFilterSnapshot != null) return true;
    final reference = sourceReference;
    final identity = subject;
    final worker = session!.workerInstanceId;
    final epoch = ++_filterRequestEpoch;
    bool current() =>
        !_closed &&
        epoch == _filterRequestEpoch &&
        subject == identity &&
        session?.workerInstanceId == worker &&
        isCurrentSource(reference) &&
        shouldContinue?.call() != false;
    sourceFilterError = null;
    final loaded = await _perform<bool>('正在加载筛选条件', () async {
      try {
        final result = await _invoke(
          wire.SourceCall(
            getFilters: wire.GetFiltersRequest(
              retainedSnapshotId: appliedSourceFilters?.snapshotId,
            ),
          ),
          onRequest: (id) {
            _filterRequestId = id;
            _filterRequestLoadsSnapshot = true;
            onRequest?.call(id);
          },
        );
        if (!current()) {
          // The host may already have replaced its draft while this sheet was
          // closing. Never reuse the old draft, or touch a newer session cache.
          if (epoch == _filterRequestEpoch) sourceFilterSnapshot = null;
          return false;
        }
        if (!result.hasFilters()) throw const FormatException('漫画源未返回筛选条件');
        sourceFilterSnapshot = result.filters.deepCopy()..freeze();
        return true;
      } catch (_) {
        // A failed or lost reset may already have replaced the host draft.
        if (epoch == _filterRequestEpoch) sourceFilterSnapshot = null;
        if (!current()) return false;
        rethrow;
      } finally {
        if (epoch == _filterRequestEpoch) {
          _filterRequestId = null;
          _filterRequestLoadsSnapshot = false;
        }
      }
    });
    if (!current()) return false;
    if (loaded != true) {
      sourceFilterError = error ?? '筛选条件尚未加载，可重试；仍可默认浏览。';
      _notify();
    }
    return loaded == true;
  }

  Future<bool> applySourceFilters(
    wire.FilterSelection selection, {
    required String search,
    bool Function()? shouldContinue,
    void Function(String requestId)? onRequest,
  }) async {
    if (_closed ||
        busy ||
        activeSource == null ||
        shouldContinue?.call() == false) {
      return false;
    }
    if (sourceFilterSnapshot?.snapshotId != selection.snapshotId) return false;
    final selected = selection.deepCopy()..freeze();
    final reference = sourceReference;
    final identity = subject;
    final worker = session!.workerInstanceId;
    final epoch = ++_filterRequestEpoch;
    bool current() =>
        !_closed &&
        epoch == _filterRequestEpoch &&
        subject == identity &&
        session?.workerInstanceId == worker &&
        isCurrentSource(reference) &&
        shouldContinue?.call() != false;
    final applied = await _perform<bool>('正在应用筛选条件', () async {
      try {
        await _loadListing(
          search: search,
          operation: 'search',
          filters: selected,
          shouldContinue: current,
          onRequest: (id) {
            _filterRequestId = id;
            _filterRequestLoadsSnapshot = false;
            onRequest?.call(id);
          },
        );
        return current();
      } catch (_) {
        if (!current()) return false;
        rethrow;
      } finally {
        if (epoch == _filterRequestEpoch) _filterRequestId = null;
      }
    });
    return applied == true && current();
  }

  Future<void> cancelSourceFilterRequest(String requestId) async {
    if (_filterRequestId != requestId) return;
    ++_filterRequestEpoch;
    _filterRequestId = null;
    if (_filterRequestLoadsSnapshot) sourceFilterSnapshot = null;
    _filterRequestLoadsSnapshot = false;
    // Invalidate this _perform before releasing busy, so a late completion
    // cannot clear a subsequent action. The runtime may also retire its worker.
    ++_epoch;
    busy = false;
    activity = null;
    _notify();
    try {
      await runtime.cancel(requestId);
    } on RuntimeException {
      // Closing a sheet must not turn an already expired request into a new UI
      // failure. Its invalidated epoch still prevents a late publication.
    }
  }

  bool isCurrentPreferencesTarget(SourcePreferencesTarget target) =>
      activeBuild?.packageName == target.build.packageName &&
      activeSource?.id == target.source.id &&
      session != null;

  Future<void> _rebuildForPreferences() async {
    _rebuildingRuntime = true;
    try {
      await rebuildRuntime();
      _runtimeNeedsRebuild = false;
    } finally {
      _rebuildingRuntime = false;
    }
  }

  Future<bool> reopenSourcePreferences(
    SourcePreferencesTarget target, {
    bool Function()? shouldContinue,
  }) async {
    if (_closed || busy || shouldContinue?.call() == false) return false;
    final epoch = _epoch;
    final identity = sourcePreferences?.identity.key;
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        sourcePreferences?.identity.key == identity &&
        shouldContinue?.call() != false;
    final reopened = await _perform<bool>('正在重新打开漫画源', () async {
      await _rebuildForPreferences();
      if (!current()) return false;
      // The explicit rebuild already retired the mutated generation.
      _preferenceRecoveries.removeWhere(
        (key, _) => key.$1 == target.build.packageName,
      );
      await _loadBuild(target.build, shouldContinue: current);
      if (!current()) return false;
      final matching = session?.sources.where(
        (source) => source.id == target.source.id,
      );
      if (matching == null || matching.isEmpty) {
        throw const FormatException('当前扩展中找不到原漫画源。');
      }
      final selected = _setSource(matching.single);
      if (selected) status = ServiceStatus.ready;
      return selected;
    });
    if (reopened != true || !current()) return false;
    await loadMangas();
    return current() && isCurrentPreferencesTarget(target);
  }

  Future<wire.PreferenceSnapshot?> describeSourcePreferences(
    SourcePreferencesTarget target, {
    bool Function()? shouldContinue,
    void Function(String)? onRequest,
  }) async {
    if (!isCurrentPreferencesTarget(target) ||
        sourcePreferencesBlocked ||
        shouldContinue?.call() == false) {
      return null;
    }
    return _perform<wire.PreferenceSnapshot>('正在读取漫画源设置', () async {
      final result = await _invoke(
        wire.SourceCall(getPreferences: wire.Empty()),
        onRequest: (id) {
          _preferenceRequestId = id;
          onRequest?.call(id);
        },
      );
      _preferenceRequestId = null;
      if (shouldContinue?.call() == false) {
        return throw const FormatException('设置页面已关闭');
      }
      if (!result.hasPreferences()) throw const FormatException('漫画源未返回设置');
      return result.preferences.deepCopy()..freeze();
    });
  }

  Future<wire.PreferenceEditResult?> editSourcePreference(
    SourcePreferencesTarget target,
    wire.PreferenceEditRequest request, {
    bool Function()? shouldContinue,
    void Function(String)? onRequest,
  }) async {
    if (!isCurrentPreferencesTarget(target) ||
        sourcePreferencesBlocked ||
        busy ||
        shouldContinue?.call() == false) {
      return null;
    }
    wire.validatePreferenceEditRequest(request);
    _preferenceRecoveries[(target.build.packageName, target.source.id)] =
        target;
    return _perform<wire.PreferenceEditResult>('正在应用漫画源设置', () async {
      final result = await _invoke(
        wire.SourceCall(editPreference: request.deepCopy()),
        allowPreferenceEdit: true,
        onRequest: (id) {
          _preferenceRequestId = id;
          onRequest?.call(id);
        },
      );
      _preferenceRequestId = null;
      if (shouldContinue?.call() == false) {
        return throw const FormatException('设置页面已关闭');
      }
      if (!result.hasPreferenceEdit()) {
        throw const FormatException('漫画源未确认设置操作');
      }
      return result.preferenceEdit.deepCopy()..freeze();
    });
  }

  Future<void> cancelSourcePreferenceRequest(String requestId) async {
    if (_preferenceRequestId != requestId) return;
    _preferenceRequestId = null;
    ++_epoch;
    busy = false;
    activity = null;
    _notify();
    try {
      await runtime.cancel(requestId);
    } on RuntimeException {
      // The real cancellation reports container loss through runtime.events.
    }
  }

  void retainSourceSessionPreferences(
    SourcePreferencesTarget target,
    List<wire.PreferenceEntry> entries,
  ) {
    wire.validatePreferenceEntries(entries);
    _sessionPreferenceValues[(target.build.packageName, target.source.id)] =
        List.unmodifiable(entries.map((entry) => entry.deepCopy()..freeze()));
  }

  bool isCurrentSource(CatalogSourceRef reference) =>
      session?.generation == reference.generation &&
      activeBuild?.id == reference.buildId &&
      activeSource?.id == reference.sourceId;

  CatalogSourceRef get sourceReference {
    final current = session;
    final source = activeSource;
    final build = activeBuild;
    if (current == null || source == null || build == null) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源未就绪');
    }
    return CatalogSourceRef(
      buildId: build.id,
      sourceId: source.id,
      generation: current.generation,
    );
  }

  /// Resolve a stable favorite against the current index; all opening stages
  /// share one busy operation so manual Source selection cannot interleave.
  Future<bool> openFavoriteSource(
    wire.FavoriteSource favorite, {
    required String identityKey,
    bool Function()? shouldContinue,
  }) async {
    if (_closed || busy || status != ServiceStatus.ready) return false;
    final repository = settings;
    if (repository == null || repository.identity.key != identityKey) {
      return false;
    }
    final selected = favorite.deepCopy()..freeze();
    try {
      validateBusinessFavoriteSource(selected);
    } on FormatException {
      error = '收藏源资料无效，请重新读取服务端设置。';
      _notify();
      return false;
    }
    final epoch = _epoch;
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        status == ServiceStatus.ready &&
        settings?.identity.key == identityKey &&
        identical(settings?.client, repository.client) &&
        shouldContinue?.call() != false;
    if (!current()) return false;
    final available = builds.where(
      (build) => build.packageName == selected.packageName,
    );
    if (available.isEmpty) {
      error = '这个收藏源的扩展当前不可用，收藏仍保留。';
      _notify();
      return false;
    }
    final build = available.single;
    final opened = await _perform<bool>('正在打开收藏源', () async {
      await _loadBuild(build, shouldContinue: current);
      if (!current() || activeBuild?.id != build.id) return false;
      final sources = session?.sources.where(
        (source) => source.id == selected.sourceId,
      );
      if (sources == null || sources.isEmpty) {
        error = '当前扩展中找不到这个收藏源，收藏仍保留。';
        return false;
      }
      if (!_setSource(sources.single)) return false;
      final reference = sourceReference;
      bool sourceCurrent() => current() && isCurrentSource(reference);
      await _loadListing(shouldContinue: sourceCurrent);
      return sourceCurrent() && page == 1;
    });
    return opened ?? false;
  }

  /// A saved manga identifies a package and Source, never an old build or
  /// generation. Only the current static index may select its runtime.
  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  openLibraryEntry(
    LibraryEntry entry, {
    required String identityKey,
    bool Function()? shouldContinue,
  }) async {
    if (_closed || busy) return null;
    final repository = library;
    if (repository == null || repository.identity.key != identityKey) {
      return null;
    }
    final epoch = _epoch;
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        status == ServiceStatus.ready &&
        library?.identity.key == identityKey &&
        shouldContinue?.call() != false;
    if (!current()) return null;
    final available = builds.where(
      (build) => build.packageName == entry.packageName,
    );
    if (available.isEmpty) {
      error = '这部漫画的漫画源当前不可用；服务端收藏和进度仍保留。';
      _notify();
      return null;
    }
    final build = available.single;
    await openBuild(build);
    if (!current() || activeBuild?.id != build.id) return null;
    final sources = session?.sources.where(
      (source) => source.id == entry.sourceId,
    );
    if (sources == null || sources.isEmpty) {
      error = '当前扩展中找不到原漫画源；服务端收藏和进度仍保留。';
      _notify();
      return null;
    }
    final selectedSource = sources.single;
    await selectSource(selectedSource, loadListing: false);
    if (!current()) return null;
    final result = await details(
      MangaEntry(entry.snapshot),
      shouldContinue: current,
    );
    if (result == null || !current()) return null;
    try {
      await repository.refreshMetadata(
        packageName: entry.packageName,
        sourceId: selectedSource.id,
        sourceName: selectedSource.name,
        sourceLang: selectedSource.lang,
        manga: result.manga.snapshot,
      );
    } catch (_) {
      if (current()) {
        error = '书架资料尚未确认，仍可继续阅读；请返回书架处理未确认操作。';
        _notify();
      }
    }
    return current() && isCurrentSource(result.source) ? result : null;
  }

  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  details(MangaEntry manga, {bool Function()? shouldContinue}) =>
      _perform<
        ({
          MangaEntry manga,
          List<ChapterEntry> chapters,
          CatalogSourceRef source,
        })?
      >('正在加载详情和章节', () async {
        if (shouldContinue?.call() == false) return null;
        final source = sourceReference;
        final detail = MangaEntry(
          (await _invoke(
            wire.SourceCall(details: wire.MangaRequest(manga: manga.snapshot)),
          )).manga,
        );
        if (shouldContinue?.call() == false) return null;
        final result = await _invoke(
          wire.SourceCall(chapters: wire.MangaRequest(manga: detail.snapshot)),
        );
        final chapters = result.chapters.chapters
            .map(ChapterEntry.new)
            .toList();
        return (manga: detail, chapters: chapters, source: source);
      });

  Future<OpenedChapter?> openChapter(
    MangaEntry manga,
    ChapterEntry chapter, {
    required CatalogSourceRef reference,
    String? logicalChapterKey,
  }) => _perform('正在加载章节页面', () async {
    if (!isCurrentSource(reference)) {
      throw const FormatException('章节所属漫画源会话已过期，请返回重新打开详情');
    }
    final current = session;
    final source = activeSource;
    final build = activeBuild;
    if (current == null || source == null || build == null) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源未就绪');
    }
    final result = (await _invoke(
      wire.SourceCall(pages: wire.ChapterRequest(chapter: chapter.snapshot)),
    )).pageList;
    final pageSessionId = result.pageSessionId;
    try {
      final pages = result.pages;
      if (pages.length > 2048 || pageSessionId.isEmpty) {
        throw const FormatException('章节页面数量或会话无效');
      }
      final opaqueKeys = <String>{};
      for (var i = 0; i < pages.length; i++) {
        final item = pages[i];
        final opaque = item.pageKey;
        if (opaque.isEmpty ||
            opaque.length > 200 ||
            !opaqueKeys.add(opaque) ||
            item.index != i) {
          throw const FormatException('漫画源页面引用无效');
        }
      }
      final chapterKey =
          logicalChapterKey ??
          _readingKey([build.packageName, source.id, manga.url, chapter.url]);
      // Handles and learned dimensions do not change content identity.
      final version = _readingKey(
        pages
            .map(
              (page) => [
                page.sourceIndex,
                page.url,
                page.hasImageUrl() ? page.imageUrl : null,
              ],
            )
            .toList(),
      );
      final urlCounts = <String, int>{};
      for (final page in pages) {
        final url = page.url;
        if (url.isNotEmpty) {
          urlCounts.update(url, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      final bindings = <String, String>{};
      final manifestPages = <ReaderPage>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final url = page.url;
        // Without a stable source reference, a changed list must report a
        // missing page and use the index hint rather than claim an exact match.
        final logicalKey = url.isNotEmpty && urlCounts[url] == 1
            ? 'url-${_readingKey(url)}'
            : '$version:$i';
        bindings[logicalKey] = page.pageKey;
        manifestPages.add(ReaderPage(key: logicalKey));
      }
      final provider = ChapterPageProvider(
        runtime: runtime,
        sourceId: source.id,
        pageSessionId: pageSessionId,
        generation: current.generation,
        chapterKey: chapterKey,
        pageKeys: bindings,
      );
      return OpenedChapter(
        manifest: ChapterManifest(
          chapterKey: chapterKey,
          version: version,
          pages: manifestPages,
        ),
        provider: provider,
        generation: current.generation,
        title: '${manga.title} · ${chapter.name}',
      );
    } catch (_) {
      await runtime.closePageSession(
        PageSessionRef(
          pageSessionId: pageSessionId,
          generation: current.generation,
        ),
      );
      rethrow;
    }
  });

  Future<void> closeChapter(OpenedChapter chapter) async {
    try {
      await chapter.provider.close();
    } catch (_) {
      if (!_closed) {
        error = '章节资源清理失败，请重新连接漫画源';
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    final requestId = _filterRequestId;
    if (requestId != null) unawaited(cancelSourceFilterRequest(requestId));
    ++_epoch;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
