import 'dart:async';

import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

SourceSearchTarget searchTarget(int index) {
  final source = wire.CatalogSource(
    id: index.toString(),
    name: '漫画源 $index',
    lang: index.isEven ? 'zh' : 'en',
  );
  return SourceSearchTarget(
    build: CatalogBuild.fromProto(
      wire.ExtensionBuildDescriptor(
        buildId: 'build-$index',
        repoId: 'keiyoushi',
        packageName: 'source.package$index',
        version: '1',
        manifestPath: '/extensions/builds/build-$index/manifest.json',
        sourceIds: [source.id],
        sources: [source],
      ),
      catalogUrl: 'https://reader.example.com/extensions/index.json',
    ),
    source: source,
    bundleSha256: 'a' * 64,
  );
}

MangaEntry searchManga(String name) =>
    MangaEntry(wire.Manga(url: '/manga/$name', title: name));

final class FakeSearchTask implements SourceSearchTask {
  FakeSearchTask({
    required this.target,
    required this.query,
    required this.page,
    this.onStarted,
  });
  final SourceSearchTarget target;
  final String query;
  final int page;
  final void Function()? onStarted;
  final completion = Completer<SourceSearchPage>();
  Future<void> Function()? beforeCancel;
  int cancelCalls = 0;

  @override
  Future<SourceSearchPage> get result => completion.future;
  void start() => onStarted?.call();
  void complete(List<MangaEntry> mangas, {bool more = false}) =>
      completion.complete(SourceSearchPage(mangas: mangas, hasNextPage: more));
  void fail(String message) =>
      completion.completeError(FormatException(message));

  @override
  Future<void> cancel() async {
    ++cancelCalls;
    await beforeCancel?.call();
    if (!completion.isCompleted) {
      completion.completeError(const FormatException('已取消'));
    }
  }
}

final class FakeSourceSearch extends CatalogSourceSearch {
  FakeSourceSearch({List<SourceSearchTarget>? targets})
    : targets = targets ?? [searchTarget(1), searchTarget(2)];
  List<SourceSearchTarget> targets;
  final tasks = <FakeSearchTask>[];
  bool alive = true;
  bool autoStart = true;
  int loads = 0;
  int stops = 0;
  int closes = 0;
  SourceSearchTarget? openedTarget;
  MangaEntry? openedManga;
  bool Function()? openCurrent;
  Future<void> Function()? beforeLoad;
  Future<void> Function()? beforeStop;
  Future<void> Function()? beforeClose;
  Future<void> Function()? beforeOpen;

  @override
  bool get available => alive;
  @override
  String? get unavailableReason => alive ? null : '原账户已失效';

  void changeAvailability(bool value) {
    alive = value;
    notifyListeners();
  }

  @override
  Future<List<SourceSearchTarget>> loadTargets() async {
    ++loads;
    await beforeLoad?.call();
    return targets;
  }

  @override
  SourceSearchTask search(
    SourceSearchTarget target,
    String query, {
    int page = 1,
    void Function()? onStarted,
  }) {
    final task = FakeSearchTask(
      target: target,
      query: query,
      page: page,
      onStarted: onStarted,
    );
    tasks.add(task);
    if (autoStart) task.start();
    return task;
  }

  @override
  Future<void> stop() async {
    ++stops;
    final current = tasks
        .where((task) => !task.completion.isCompleted)
        .toList();
    await beforeStop?.call();
    await Future.wait(current.map((task) => task.cancel()));
  }

  @override
  Future<void> close() async {
    ++closes;
    if (alive) changeAvailability(false);
    await beforeClose?.call();
    await stop();
  }

  @override
  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  openResult(
    SourceSearchTarget target,
    MangaEntry manga, {
    bool Function()? shouldContinue,
  }) async {
    openedTarget = target;
    openedManga = manga;
    openCurrent = shouldContinue;
    await beforeOpen?.call();
    if (shouldContinue?.call() == false) return null;
    return (
      manga: manga,
      chapters: [ChapterEntry(wire.Chapter(url: '/chapter', name: '第一章'))],
      source: CatalogSourceRef(
        buildId: target.build.id,
        sourceId: target.source.id,
        generation: 'generation-1',
      ),
    );
  }
}
