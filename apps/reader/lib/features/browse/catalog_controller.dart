import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../runtime/runtime_platform_types.dart';

enum ServiceStatus {
  disconnected,
  connecting,
  ready,
  loginRequired,
  denied,
  failed,
}

final class CatalogBuild {
  const CatalogBuild({
    required this.id,
    required this.packageName,
    required this.version,
    required this.manifestPath,
  });
  final String id;
  final String packageName;
  final String version;
  final String manifestPath;

  factory CatalogBuild.fromProto(wire.ExtensionBuildDescriptor value) {
    final id = value.buildId;
    final path = value.manifestPath;
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,200}$').hasMatch(id) ||
        path != '/extensions/builds/$id/manifest.json' ||
        value.packageName.isEmpty ||
        value.version.isEmpty) {
      throw const FormatException('扩展清单路径与构建不匹配');
    }
    return CatalogBuild(
      id: id,
      packageName: value.packageName,
      version: value.version,
      manifestPath: path,
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
  CatalogController({required this.api, required this.runtime}) {
    _subscription = runtime.events.listen(_onRuntimeEvent);
  }

  final ApiFetch api;
  final SourceRuntime runtime;
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
  String? lastBuildId;
  String? lastSourceId;
  int _requestSequence = 0;
  int _epoch = 0;
  bool _closed = false;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _onRuntimeEvent(RuntimeEvent event) {
    if (_closed) return;
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

  void _dropSession() {
    session = null;
    activeSource = null;
    activeBuild = null;
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
    await _perform('正在连接服务', () async {
      status = ServiceStatus.connecting;
      _dropSession();
      builds = const [];
      final bootstrap = wire.decodeProtoJson(
        wire.Bootstrap(),
        await _get('/api/bootstrap'),
      );
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
      if (inventory.schemaVersion != 1) {
        throw const FormatException('扩展索引版本不兼容');
      }
      final available = inventory.builds.map(CatalogBuild.fromProto).toList();
      if (available.length > 5000 ||
          available.map((build) => build.packageName).toSet().length !=
              available.length) {
        throw const FormatException('扩展索引必须每包只包含一个当前版本');
      }
      if (_closed) return;
      subject = confirmedSubject;
      email = confirmedEmail;
      builds = available;
      status = ServiceStatus.ready;
    });
  }

  Future<void> openBuild(CatalogBuild build) async {
    if (busy) return;
    lastBuildId = build.id;
    lastSourceId = null;
    await _perform('正在加载漫画源', () async {
      _dropSession();
      final identity = subject;
      if (identity == null) {
        throw const RuntimeException(RuntimeErrorCode.accessRequired, '身份未确认');
      }
      final manifest = wire.decodeProtoJson(
        wire.BuildManifest(),
        await _get(build.manifestPath),
      );
      if (manifest.buildId != build.id ||
          !manifest.hasBundle() ||
          manifest.bundle.sha256.isEmpty) {
        throw const FormatException('构建标识不匹配');
      }
      final loaded = await runtime.open(
        BuildDescriptor(
          buildId: build.id,
          manifestUri: Uri.parse(build.manifestPath),
          sha256: manifest.bundle.sha256,
          identity: identity,
          packageId: build.packageName,
        ),
      );
      if (_closed) return;
      activeBuild = build;
      session = loaded;
      activeSource = null;
      mangas = const [];
      page = 0;
      hasNextPage = false;
    });
  }

  Future<SourceResult> _invoke(wire.SourceCall call) async {
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

  Future<void> selectSource(SourceInfo source) async {
    if (busy) return;
    if (!(session?.sources.any((value) => value.id == source.id) ?? false)) {
      return;
    }
    activeSource = source;
    lastSourceId = source.id;
    mangas = const [];
    page = 0;
    hasNextPage = false;
    query = '';
    listing = 'popular';
    await loadMangas();
  }

  Future<void> loadMangas({
    String? search,
    String? operation,
    bool more = false,
  }) async {
    await _perform('正在加载漫画', () async {
      final selectedQuery = search ?? query;
      final selectedListing =
          operation ??
          (search != null
              ? (search.trim().isEmpty ? 'popular' : 'search')
              : listing);
      final selectedPage = more ? page + 1 : 1;
      final call = switch (selectedListing) {
        'popular' => wire.SourceCall(
          popular: wire.PageRequest(page: selectedPage),
        ),
        'latest' => wire.SourceCall(
          latest: wire.PageRequest(page: selectedPage),
        ),
        'search' => wire.SourceCall(
          search: wire.SearchRequest(page: selectedPage, query: selectedQuery),
        ),
        _ => throw const FormatException('未知漫画列表操作'),
      };
      final result = (await _invoke(call)).mangaPage;
      final entries = result.mangas.map(MangaEntry.new).toList();
      if (_closed) return;
      mangas = more ? [...mangas, ...entries] : entries;
      page = selectedPage;
      query = selectedQuery;
      listing = selectedListing;
      hasNextPage = result.hasNextPage;
    });
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

  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  details(MangaEntry manga) => _perform('正在加载详情和章节', () async {
    final source = sourceReference;
    final detail = MangaEntry(
      (await _invoke(
        wire.SourceCall(details: wire.MangaRequest(manga: manga.snapshot)),
      )).manga,
    );
    final result = await _invoke(
      wire.SourceCall(chapters: wire.MangaRequest(manga: detail.snapshot)),
    );
    final chapters = result.chapters.chapters.map(ChapterEntry.new).toList();
    return (manga: detail, chapters: chapters, source: source);
  });

  Future<OpenedChapter?> openChapter(
    MangaEntry manga,
    ChapterEntry chapter, {
    required CatalogSourceRef reference,
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
      final chapterKey = _readingKey([
        build.packageName,
        source.id,
        chapter.url,
      ]);
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
    ++_epoch;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
