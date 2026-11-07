# 章节书签验证

2026-11-06，章节书签从 `business.proto`、D1 到正式 Flutter 详情和阅读页面接入。本文分别记录工程/组件证据与真实客户端门，不把模拟 supplier、编译或单进程组件当成独立客户端同步验收。

## 已实现行为

- 章节列表标记/移除、仅书签筛选，以及阅读当前章的同一控制；Source 章节身份保持现有稳定键，不用标题或旧序号匹配。
- 独立 64 项分页集合与当前章布尔读取；D1 复用作品 CAS、账户 revision 和原子幂等 batch。未收藏作品也可标记，取消收藏与重置阅读保留书签。
- 只在服务端 ACK 后更新图标；未确认操作固定 UUID/正文/CAS，仅显式重试。完整只读刷新不会重发旧操作；冲突后重新读取，旧幂等 ACK 不覆盖当前撤销结果。
- 阅读进度造成的本会话已确认 revision 变化可安全采用；远端变化仍冲突。身份变化、页面关闭和迟到结果与新页面隔离。

## 可复验入口与证据范围

```sh
pnpm generate:check
pnpm check
pnpm flutter:check
pnpm build
```

官方 workerd/D1 状态测试新增书签的保留语义、并发 CAS、旧 ACK、身份隔离、分页与 batch 回滚。Dart 数据测试和正式页面组件测试使用真实业务 client/repository 加受控 API supplier，检查确认、重试、冲突、身份及详情/阅读入口；该 supplier 不是在线 Source 或生产 Access。

## 本轮检查结果

完整 `pnpm check` 通过：365 项 Vitest、协议 golden 和工具回归全部通过，154 个模块 / 498 条依赖无违规。官方 workerd/D1 状态测试共 19 项通过，contracts 5 项通过；它们包含在上述工程检查中，不重复累加为额外在线证据。

`pnpm flutter:check` 三项目静态分析通过，测试分别为 21 / 42 / 269 项；新增 11 项书签数据回归和 11 项控制器/控件/正式导航回归。正式导航覆盖详情标记→仅书签筛选→进入阅读→移除当前章书签→返回详情自动刷新为空。该用例由官方 Flutter widget 测试和受控 Source/API supplier 驱动，不是独立客户端或真实 Source 验收。

全库 `pnpm format`、`pnpm format:check` 和最终 `pnpm build` 通过；正式输出包含宿主、Native 内置材料、Flutter Web release 与 API。运行日志留在忽略的 `.local/bookmarks/`，不提交临时服务或机器输出。

## 2026-11-07：真实 Web 标记与独立文档读取阻断

本轮以主线 `d1c0c5f` 为基线，加入下述只读打开修复候选与正式 Native 书签驱动。主代理通过 Codex 内置浏览器操作正式 Flutter Web 客户端和官方 Vite / Wrangler harness；独立验收只发正常 `Origin`、`X-App-Subject`、`X-App-Request` 头的 GET，核对真实 D1。当前书签跨端门仍为进行中，没有因驱动或组件通过而提升。

### 相同书架资料不再隐式修改共享 CAS

验收准备发现，`CatalogController.openLibraryEntry` 每次从书架打开都会调用 `refreshMetadata`，即使 Source 名称、语言和完整 Manga 快照未变，也会提升作品 revision，干扰另一端的书签草稿。候选修复只在这三个值实际变化时沿原路径保存；不改变 repository 的显式资料更新、pending、原请求重试或 API 语义。

独立只读复审确认，Manga / LibraryEntry 均深复制并冻结，生成模型按结构与 optional presence 比较，opaque memo 不改写；真实 Source 控制响应和 D1 API 均经标准 ProtoJSON 编码，不自行补设非 optional 默认值。旧书架快照与当前 Source 相同时跳过写入，不覆盖另一端已确认资料；已有资料丢 ACK 的原 UUID、正文和 CAS 仍保留在业务客户端，只由原入口明确重试。

`library_navigation_test.dart` 的 14 项回归已包含在完整客户端集合中，覆盖反复打开零 mutation、另一客户端仍可按原 revision 标书签、旧快照不覆写远端资料、资料失 ACK 后相同打开不重发且保留精确原操作，以及 Source 名称/语言/memo 变化仍保存、真正保存失败仍可阅读。旧逻辑对照新增用例先失败。它们使用受控 Source / 业务 supplier，不是独立浏览器或设备验收；资料更新与错误恢复的设计及其它证据另见[阅读入口](reading-entry.md)。

### Web A 正式添加与只读 D1 核对

HTTP 服务为 `http://127.0.0.1:61327`，subject 为 `acceptance-owner`，使用隔离 D1。A 从正式扩展管理安装 xkcd，打开英文 Source 并在真实详情收藏 `xkcd`；实际章节列表显示 3320 项，最新为 `3321: Simulation`。索引选中构建为 `ext-all.xkcd-aa5f4f1052b403b7872a5164324530c8`，Source ID 为 `1538249443376436084`，作品原 URL 为 `SINGLE`。

目标为 `3319: Elevators`，英文 Source 保留原 archive href 的尾斜杠，实际章节 URL 为 `/3319/`。按正式 `LibraryRepository` / `ChapterSequence` 算法，作品 key 为 `62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f`，章节 key 为 `3ebd1a075e8cc6fad4cae9daa7595caac80545bdf9499496417bb3d3b6b1142c`；未用章节标题、旧序号或另一语言的 URL 规则代替身份。

| 阶段                | account / manga / global revision | 实际结果                                                              |
| ------------------- | --------------------------------- | --------------------------------------------------------------------- |
| 收藏后、尚未点书签  | 2 / 1 / 1                         | 独立 GET 确认收藏、空书签与空进度，无 resume。                        |
| A 点击目标书签      | 3 / 2 / 1                         | UI 显示已标记 1 章，按钮变为移除；“仅书签”显示唯一目标，计数 1/3320。 |
| 新文档 B 打开失败后 | 3 / 2 / 1                         | 精确书签仍为 true，完整已确认业务状态未变；不计第二端读回成功。       |

独立 GET `/bookmarks` 确认唯一条目为上述 exact chapter key 且 `bookmarked=true`；`/api/state/manga/:key?chapterKey=:chapterKey` 的当前章布尔也明确为 true。设置、安装、Source 元数据、收藏时间、分类、无 resume 和空进度均保持基线，只增加一次 account / manga revision。没有通过直接 POST 补足正式 UI 操作。

A 随后关闭，B 是同 origin 的全新 Web 文档。B 从正式书架打开两次均未到详情，最终显示运行容器中断；第二次是在正式重连就绪后重试。后续 B 重连后由普通浏览加载 xkcd 包成功，出现五个 Source，但选择英文 Source 的热门也最终 `runtimeLost`。因此不能将失败定性为书架专属、iframe 问题或资料 no-op 修复的根因。该事件可能由 60 秒启动超时或 30 秒 invoke 超时触发，本轮未精确测量对应请求，不能判定具体是哪一个。

失败后独立重读 settings / library / manga / bookmarks / progress 与添加后逐字段相同，只证明没有提交业务变化；没有完整请求日志，不声称客户端所有流量都是 GET。截图为 `/private/tmp/karuyomi-bookmarks-web-added.jpg`；原始阶段快照在 `/private/tmp/karuyomi-bookmarks-web-{baseline,added,new-document-open-failure}.json`。详细临时审计不入库。

### HTTPS 与 Native 驱动的实际边界

本轮另尝试官方 HTTPS harness `https://127.0.0.1:60769`，Codex 内置浏览器实际返回 `ERR_CERT_AUTHORITY_INVALID`。没有忽略证书、改用其它浏览器或将 HTTP Web 与 HTTPS Native 当作同一 origin；该 HTTPS 服务已关闭。本轮没有启动 Native 设备，未完成 Web↔iOS / Android 书签同步。

新增正式 `integration_test/bookmarks_sync_test.dart` 复用 `app.main()`、`NativePlatformRuntime`、真实书架点击与 Source 详情，按 exact Source / manga / chapter URL 定位。阶段为 `verify` / `set` / `remove`，输入同服务 subject 与完整 Settings / MangaState / BookmarkPage 快照；读阶段要求零 revision 变化，写阶段要求 ACK、完整重读、pending 清空且只有一次 revision 递增，同时核对其它设置和章节进度不变。关闭等待正式运行时释放 ACK，不注入测试 PlatformRuntime 或手动推送详情路由。入口和配置见[集成测试说明](../../apps/reader/integration_test/README.md)。

该驱动严格分析无问题，但未在设备执行。最终完整 `pnpm flutter:check` 通过：Reader Core 22、Source Runtime 86、Reader 597 项，三项目分析无问题，173 份 Dart 格式零变化。独立读取 `.local/bookmarks-driver-analyze.log` 与 `.local/bookmarks-flutter-check.log` 核对分析及通过标志；旧逻辑红日志为 `.local/metadata-noop-before.log`。本节工程与受控回归不替代尚未通过的独立文档、Native、故障恢复或生产 Access 门。

## 2026-11-07：新文档章节超时的精确诊断

后续以 `bdc54de` 为基线，在新的正式 HTTP harness `51864` 复现 A 添加目标书签后关闭、新文档 B 从书架重开。默认关闭的宿主阶段诊断确认 B 的 init / load / details 已完成，`ui-2` 的章节调用在缓存 get Promise 返回后仍未完成，最终命中默认 30 秒 invoke 超时；这不是此前 `61327` 未精确计时结论的补写。独立六路 GET 在 B 调用前后逐字段相同，account / manga / global revision 保持 3 / 2 / 1，目标书签仍为 true，但 B 未到正式详情，因此第二文档读回与跨端门仍未通过。

输入、构建开关、原始证据、纯缓存桥机制测试与尚未确定的根因见[Source 重开诊断](source-reopen.md)。没有把缓存 Promise 返回当作缓存命中或 Java callback 已恢复，也没有调整超时掩盖问题。

## 2026-11-07：修复后 Web 独立文档闭环

固定 `5ba6fff` 的无插桩 xkcd 在正式 Flutter Web / 官方 harness 通过 A 添加 `/3319/` → 新文档 B 从书架重开、读回、筛选并移除 → 新文档 C 重开确认已移除。独立 D1 核对确认两次重开为只读，移除只更新该书签和 account/manga revision。输入、四阶段证据和实际范围见[修复后记录](source-reopen.md#固定-5ba6fff真实-web-重开与书签往返通过)。

## 尚待验收

- Native 独立客户端往返、浏览器/应用进程重启、自动前台刷新和真实丢响应恢复。
- Web/iOS/Android 的实际平台组合、Source 在线阅读期间的书签，以及生产 Access、真机与触控。

实现与边界见[章节书签设计](../design/bookmarks.md)，当前交付顺序见 [P2](../plan/p2-sync.md)。
