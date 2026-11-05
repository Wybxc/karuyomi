# P1 本地书架分项

2026-11-05，macOS，固定 Flutter 3.47.5 / Dart 3.13.4。正式 `lib/main.dart` 已从占位书架接入 Drift 收藏列表和既有详情/Reader 路由。本记录仅证明组件与 SQLite 文件行为，不是实际浏览器、Native UI、Source 在线或生产 Access 验收。

## 实现范围

- 详情加入/移出书架；元数据与收藏关系分表，按部署 origin + bootstrap subject 隔离。
- 保留完整 Source Manga ProtoJSON、package/source 字符串身份；稳定作品键与章节序列/阅读进度一致，不存旧 build/generation。
- 本地标题/作者/漫画源搜索，收藏时间/标题确定性排序；不请求网络封面、不扫描书架更新。
- 打开作品以当前索引选择原 package/Source，直接取该作品详情/章节，不先加载热门列表；成功后尽力刷新已有元数据，保留收藏时间。写入失败仍可阅读。
- 从详情继续阅读已有锚点；取消收藏不删除元数据、继续阅读位置或最远进度。库不可用和收藏写入失败有提示及重试路径。
- 界面明确“书架仅保存在此设备”；持久化能力提示来自 Drift 的实际 storageMode。尚无 D1 业务状态、业务同步协议、outbox、分类或批量操作。

schema v2 只新增元数据和收藏两表。通用 `createAll()` 使用 Drift 的 `IF NOT EXISTS`，没有旧模型、版本转换分支或兼容协议。本次增表保留现有进度，不承诺今后原型 schema 变化的兼容性。

## 通过的门

复验命令在 `apps/reader/` 执行：

```sh
flutter test test/data/library_repository_test.dart
flutter test test/browse/library_navigation_test.dart
flutter test test/library
```

- 真实 SQLite 文件关闭重开：原始 URL、64 位 Source ID、Manga memo/可选字段、收藏时间和进度恢复；数据快照冻结，不随调用方修改。
- 真实只有旧两张进度表的 SQLite 文件重新打开：增加当前书架表，保留原 resume/页内锚点；不用旧版 Dart 模型或迁移转换代码。
- 身份/origin/package/Source 隔离、重复收藏不改时间、刷新元数据不自动收藏、移除仅删收藏关系；订阅正确收到增删。
- SQLite 故障 trigger 拒绝收藏写入：元数据与收藏事务一起回滚；正式详情提示重试，仍能进入 Reader，移除故障后成功收藏。
- 当前索引切换到新 build/generation 后，用保存的原 Manga 快照重开；缺包/缺 Source 不回退到另一来源；Access 失效不删除本地收藏。
- 身份重连即移除旧列表；搜索/排序不发 Source 请求；页面离开后的迟到详情不导航，也不继续取章。
- 正式应用组件闭环：浏览详情 → 收藏 → 阅读位置保存 → 关闭路由/数据库 → 新平台容器与同一 SQLite 文件重开 → 书架 → 原 Source 详情 → 继续阅读，恢复相同 chapter/page/0.35 页内偏移；移出书架后继续阅读仍可用。该门用受控 Source DTO 与 viewport 回调，不证明图片可见或解码。

本轮完整 `pnpm format`、`pnpm format:check`、`pnpm check` 与 `pnpm flutter:check` 通过；三个 Dart/Flutter 包分别 21/42/163 项测试通过，Drift 重新生成后与提交输入一致。`pnpm build` 完成正式 Flutter Web release、共享/Native 材料组装和 API Wrangler dry-run；共享材料身份未变化，没有因此重建扩展 AOT。本轮没有部署生产或重建 Native App。

完整工程检查与实际环境门分别记录；P0 的生产 Access、当前 Native 运行与真机限制不因本地书架完成而解除。
