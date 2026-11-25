import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_routes.dart';
import '../browse/catalog_controller.dart';
import '../browse/manga_details_destination.dart';
import '../reader/reader_recovery.dart';

class const BrowsingHistoryPage({
  super.key,
  required final CatalogController? catalog,
  required final VoidCallback onConnect,
  required final VoidCallback onAuthenticate,
  final ReaderAuthentication? onAuthenticateReader,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final controller = useListenable(catalog);
    final client = controller?.accessPaused == true
        ? null
        : controller?.library?.client;
    if (controller == null || client == null) {
      final connecting = controller?.status == ServiceStatus.connecting;
      final login = controller?.accessPaused == true;
      return Center(
        child: SingleChildScrollView(
          child: AppEmptyState(
            leading: connecting
                ? const CupertinoActivityIndicator()
                : const Icon(CupertinoIcons.clock),
            title: connecting ? '正在连接' : '连接后查看浏览记录',
            message: controller?.error ?? '',
            action: connecting
                ? null
                : (
                    label: login ? '重新登录' : '连接服务',
                    onPressed: login ? onAuthenticate : onConnect,
                  ),
          ),
        ),
      );
    }
    return _HistoryList(
      key: ObjectKey(client),
      catalog: controller,
      client: client,
      onAuthenticateReader: onAuthenticateReader,
    );
  }
}

class const _HistoryList({
  super.key,
  required final CatalogController catalog,
  required final BusinessStateClient client,
  required final ReaderAuthentication? onAuthenticateReader,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useListenable(catalog);
    final reload = useState(0);
    final busy = useState(false);
    final error = useState<String?>(null);
    final reading = useMemoized(client.readBrowsingHistory, [
      client,
      reload.value,
      catalog.browsingHistoryRevision,
    ]);
    final snapshot = useFuture(reading, preserveState: false);
    bool current() =>
        context.mounted &&
        !catalog.accessPaused &&
        identical(catalog.library?.client, client);
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed && current()) reload.value++;
    });

    Future<void> open(wire.BrowsingHistoryEntry entry) async {
      if (!current() ||
          busy.value ||
          catalog.busy ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      error.value = null;
      await openMangaDetails(
        context,
        title: entry.title,
        catalog: catalog,
        onAuthenticateReader: onAuthenticateReader,
        load: (isCurrent) async {
          bool active() => current() && isCurrent();
          if (!active()) return null;
          final metadata = await client.readBrowsingVisit(entry.mangaKey);
          if (!active()) return null;
          if (metadata == null) {
            reload.value++;
            throw const FormatException('这条浏览记录已被移除。');
          }
          return catalog.openBrowsingVisit(
            metadata,
            client: client,
            shouldContinue: active,
          );
        },
      );
    }

    Future<void> remove([String? key]) async {
      if (!current() || busy.value) return;
      if (key == null) {
        final accepted = await showAppDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('清空浏览记录？'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空'),
              ),
            ],
          ),
        );
        if (accepted != true || !current() || busy.value) return;
      }
      busy.value = true;
      error.value = null;
      try {
        await client.removeBrowsingHistory(key: key);
        if (current()) reload.value++;
      } catch (_) {
        if (current()) error.value = '未能删除浏览记录，请重试。';
      } finally {
        if (current()) busy.value = false;
      }
    }

    if (snapshot.hasError) {
      return Center(
        child: AppEmptyState(
          leading: const Icon(CupertinoIcons.clock),
          title: '未能读取浏览记录',
          message: '',
          action: (label: '重试', onPressed: () => reload.value++),
          announce: true,
        ),
      );
    }
    final entries = snapshot.data;
    if (entries == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final failure = error.value ?? catalog.browsingHistoryError;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            reload.value++;
          },
        ),
        if (failure != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  failure,
                  style: TextStyle(color: AppColors.error.resolveFrom(context)),
                ),
              ),
            ),
          ),
        if (entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: AppEmptyState(
                leading: Icon(CupertinoIcons.clock),
                title: '暂无浏览记录',
                message: '打开过的漫画会显示在这里。',
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              header: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: CupertinoButton(
                  onPressed: busy.value ? null : () => unawaited(remove()),
                  child: const Text('清空记录'),
                ),
              ),
              children: [
                for (final entry in entries)
                  CupertinoListTile(
                    key: ValueKey(('browsing-history-entry', entry.mangaKey)),
                    title: Text(entry.title, maxLines: 2),
                    subtitle: Text(
                      '${entry.sourceName} · ${_visitedAt(entry)}',
                      maxLines: 2,
                    ),
                    onTap: busy.value || catalog.busy
                        ? null
                        : () => unawaited(open(entry)),
                    trailing: CupertinoButton(
                      padding: const EdgeInsets.all(6),
                      onPressed: busy.value
                          ? null
                          : () => unawaited(remove(entry.mangaKey)),
                      child: const Icon(
                        CupertinoIcons.trash,
                        size: 18,
                        semanticLabel: '移除浏览记录',
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String _visitedAt(wire.BrowsingHistoryEntry entry) {
  final date = DateTime.fromMillisecondsSinceEpoch(entry.visitedAtMs.toInt());
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}
