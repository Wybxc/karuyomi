import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';

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

  factory CatalogBuild.fromJson(Map<String, Object?> json) {
    final id = _string(json, 'buildId');
    final path = _string(json, 'manifestPath');
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,200}$').hasMatch(id) ||
        path != '/extensions/builds/$id/manifest.json') {
      throw const FormatException('扩展清单路径与构建不匹配');
    }
    return CatalogBuild(
      id: id,
      packageName: _string(json, 'packageName'),
      version: _string(json, 'version'),
      manifestPath: path,
    );
  }
}

final class MangaEntry {
  MangaEntry(Map<String, Object?> snapshot)
    : snapshot = Map.unmodifiable(snapshot),
      title = _string(snapshot, 'title'),
      url = _string(snapshot, 'url') {
    for (final key in ['description', 'author', 'artist']) {
      if (snapshot[key] != null && snapshot[key] is! String) {
        throw const FormatException('漫画资料格式无效');
      }
    }
    if (snapshot['genres'] != null &&
        (snapshot['genres'] is! List ||
            !(snapshot['genres'] as List).every((value) => value is String))) {
      throw const FormatException('漫画分类格式无效');
    }
  }
  final Map<String, Object?> snapshot;
  final String title;
  final String url;
  String? get description => snapshot['description'] as String?;
  String? get author => snapshot['author'] as String?;
  String? get artist => snapshot['artist'] as String?;
  List<String> get genres => (snapshot['genres'] as List? ?? []).cast<String>();
}

final class ChapterEntry {
  ChapterEntry(Map<String, Object?> snapshot)
    : snapshot = Map.unmodifiable(snapshot),
      name = _string(snapshot, 'name'),
      url = _string(snapshot, 'url');
  final Map<String, Object?> snapshot;
  final String name;
  final String url;
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

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) {
    throw const FormatException('服务返回的数据不完整');
  }
  return field;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map || !value.keys.every((key) => key is String)) {
    throw const FormatException('服务返回了无效数据');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('服务返回的列表格式无效');
  return value;
}

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

  Future<Map<String, Object?>> _get(String path) async {
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
    return _object(jsonDecode(reply.body));
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
      final bootstrap = await _get('/api/bootstrap');
      if (bootstrap['protocolVersion'] != protocolVersion) {
        throw const FormatException('客户端与服务版本不兼容');
      }
      final identity = _object(bootstrap['identity']);
      final confirmedSubject = _string(identity, 'subject');
      final confirmedEmail = _string(identity, 'email');
      final inventory = await _get('/extensions/index.json');
      if (inventory['schemaVersion'] != 1 || inventory['nextCursor'] != null) {
        throw const FormatException('扩展索引版本不兼容');
      }
      final available = _list(
        inventory['builds'],
      ).map((v) => CatalogBuild.fromJson(_object(v))).toList();
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
      final manifest = await _get(build.manifestPath);
      if (manifest['buildId'] != build.id) {
        throw const FormatException('构建标识不匹配');
      }
      final loaded = await runtime.open(
        BuildDescriptor(
          buildId: build.id,
          manifestUri: Uri.parse(build.manifestPath),
          sha256: _string(_object(manifest['bundle']), 'sha256'),
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

  Future<Map<String, Object?>> _invoke(
    String operation,
    Map<String, Object?> args,
  ) async {
    final epoch = _epoch;
    final current = session;
    final build = activeBuild;
    final source = activeSource;
    if (current == null || build == null || source == null) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源未就绪');
    }
    final result = await runtime.invoke(
      SourceRequest(
        requestId: 'ui-${++_requestSequence}',
        generation: current.generation,
        packageId: build.packageName,
        sourceId: source.id,
        operation: operation,
        arguments: args,
      ),
    );
    if (_closed ||
        epoch != _epoch ||
        session?.generation != current.generation) {
      throw const RuntimeException(RuntimeErrorCode.runtimeLost, '漫画源会话已失效');
    }
    return result.data;
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
      final result = await _invoke(selectedListing, {
        'page': selectedPage,
        if (selectedListing == 'search') 'query': selectedQuery,
      });
      final entries = _list(
        result['mangas'],
      ).map((value) => MangaEntry(_object(value))).toList();
      if (result['hasNextPage'] is! bool) {
        throw const FormatException('漫画分页数据格式无效');
      }
      if (_closed) return;
      mangas = more ? [...mangas, ...entries] : entries;
      page = selectedPage;
      query = selectedQuery;
      listing = selectedListing;
      hasNextPage = result['hasNextPage'] == true;
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
      await _invoke('details', {'manga': manga.snapshot}),
    );
    final result = await _invoke('chapters', {'manga': detail.snapshot});
    final chapters = _list(
      result['chapters'],
    ).map((value) => ChapterEntry(_object(value))).toList();
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
    final result = await _invoke('pages', {'chapter': chapter.snapshot});
    final pageSessionId = _string(result, 'pageSessionId');
    try {
      final values = _list(result['pages']);
      if (values.length > 10000) throw const FormatException('章节页面数量超过限制');
      final pages = <Map<String, Object?>>[];
      final opaqueKeys = <String>{};
      for (var i = 0; i < values.length; i++) {
        final item = _object(values[i]);
        final opaque = _string(item, 'pageKey');
        final index = item['index'];
        final sourceIndex = item['sourceIndex'];
        if (opaque.length > 1000 ||
            !opaqueKeys.add(opaque) ||
            index != i ||
            sourceIndex is! num ||
            !sourceIndex.isFinite ||
            sourceIndex != sourceIndex.truncateToDouble() ||
            item['url'] is! String ||
            (item['imageUrl'] != null && item['imageUrl'] is! String)) {
          throw const FormatException('漫画源页面引用无效');
        }
        pages.add(item);
      }
      final chapterKey = _readingKey([
        build.packageName,
        source.id,
        chapter.url,
      ]);
      // Handles and learned dimensions do not change content identity.
      final version = _readingKey(
        pages
            .map((page) => [page['sourceIndex'], page['url'], page['imageUrl']])
            .toList(),
      );
      final urlCounts = <String, int>{};
      for (final page in pages) {
        final url = page['url'] as String;
        if (url.isNotEmpty) {
          urlCounts.update(url, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      final bindings = <String, String>{};
      final manifestPages = <ReaderPage>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final url = page['url'] as String;
        // Without a stable source reference, a changed list must report a
        // missing page and use the index hint rather than claim an exact match.
        final logicalKey = url.isNotEmpty && urlCounts[url] == 1
            ? 'url-${_readingKey(url)}'
            : '$version:$i';
        bindings[logicalKey] = page['pageKey'] as String;
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
