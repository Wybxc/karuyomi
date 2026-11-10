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

## 2026-11-07：iOS ↔ Android 模拟器书签往返

使用正式驱动 `2c4f3b4` / `761972f`、固定 `5ba6fff` 的无插桩 xkcd 构建 `ext-all.xkcd-dd84d305506e2bdc34ac62988aef645f`，在独立的 iPhone 17 Pro / iOS 26.4 与 Pixel 9 / Android API 36 模拟器启动正式 `app.main()`。两端连接同一官方 HTTPS harness `https://127.0.0.1:57539`，使用隔离的 workerd / D1 和同一测试身份 `acceptance-owner`。iOS 只在该模拟器信任验收 CA；Android 临时 debug 副本仅为该 loopback 主机的 WebView 增加同一 CA，Dart 测试进程也通过该 CA 验证；两端保留 TLS 与主机名检查。两端均从正式 Source 详情操作 xkcd 英文 Source 的 `SINGLE`、`/3319/`。

| 阶段         | account / global / manga revision | 正式界面及独立 D1 结果                                                             |
| ------------ | --------------------------------- | ---------------------------------------------------------------------------------- |
| iOS 准备     | 2 / 1 / 1                         | 从空账户安装固定构建，通过英文热门打开作品并收藏；无书签、无进度。                 |
| iOS 添加     | 3 / 1 / 2                         | 正式按钮确认唯一目标书签；仅目标章和相应 revision 变化。                           |
| Android 读回 | 3 / 1 / 2                         | 新进程从书架打开，真实详情显示目标章已标记；业务快照不变。                         |
| Android 移除 | 4 / 1 / 3                         | 点击正式「仅书签」筛选与目标按钮并确认移除，书签查询为空；其它已确认业务状态不变。 |
| iOS 再读回   | 4 / 1 / 3                         | 新进程从书架打开，确认已移除；业务快照不变。                                       |

首次 Android 移除进入了正确详情，读到目标书签且按钮可用，但章节搜索后的按钮未通过中心命中测试，120 秒内未发出点击；独立六路 GET 与上一阶段完全相同。未采集当时的键盘或布局状态，未确定具体成因。驱动 `761972f` 改用正式「仅书签」筛选后复验，仍要求按唯一原章节 URL 计算的 key、真实手势和相同 D1 前置。

各阶段独立读取设置、漫画设置、书架、目标章作品状态、书签和进度；写入只通过正式 Flutter UI。每次正式驱动结束前等待运行时释放。验收入口为 `flutter test integration_test/bookmarks_sync_test.dart --no-pub -d <device> --dart-define-from-file=<phase.json> --reporter expanded`，完整配置见[集成测试说明](../../apps/reader/integration_test/README.md)。临时日志、CA、D1 和采样快照不入库；候选未部署，扩展状态仍为 `compiled_unverified` / `runtimeReady=false`。

## 2026-11-10：首发材料的 Web 与 iOS 混合验收受限

使用带登录与阅读恢复修复的首发六材料产品归档、冻结 v6 xkcd 和同一隔离 D1。iOS 模拟器从正式入口运行 `bookmarks_sync_test.dart` 的 `prepare` 阶段，连接受信任的 Wrangler HTTPS harness `https://127.0.0.1:60472`，安装扩展并收藏 xkcd；账户/作品 revision 为 2/1，章节 `/3319/` 未标记书签，无阅读进度。

Codex 内置浏览器经 HTTP Vite 别名 `http://127.0.0.1:55217` 成功读回同一书架。打开 xkcd 时提示「这个扩展的仓库已移除」：安装记录中的默认仓库索引是 HTTPS harness 的目录 URL，Web 当前默认仓库是 HTTP 别名的目录 URL，两者即使提供相同静态字节也不是同一仓库。打开前后八路独立 API 响应逐字节一致。Web 未进入详情、未操作书签；Android 未启动。本轮只验证了跨端书架读回。

两项本地服务、专用模拟器和 ADB 已清理。构建输入、准备日志与前后快照保存在本机忽略目录 `.local/prototype-web-native-bookmarks.YSZYX1/evidence/`。

## 2026-11-10：Native 在线阅读书签丢确认与跨端读回

使用首发六材料产品归档和冻结 v6 xkcd。专用 Pixel 7 / Android 16 API 36 arm64 与 iPhone 17 Pro / iOS 26.4 模拟器连接同一官方 Wrangler 回环 HTTPS、新隔离 D1 和 `acceptance-owner`。两端包内 `host.js`、`worker.js` 和 `manifest.json` 均与归档一致，保留 TLS 和主机名校验。Android 调试入口只补测试 CA 后运行正式 App，由 UIAutomator 操作；iOS 使用正式 `lib/main.dart` 和外部 XCTest。

1. Android 从书架打开真实 `3319: Elevators`，显示并保存第 2/2 页。在 Reader 点「标记章节书签」后，`ACCEPTANCE_FIXTURE=bookmark-ack-loss` 等正式 Worker 提交 D1、核对成功响应与持久回执，再中断首个 HTTP 200 响应正文。Android 保持原图，仍显示未标记、修改尚未确认及可重试。此时独立 GET 已读到唯一目标章书签，账户/作品 revision 从 5/4 到 6/5；收藏、设置、章节位置与最远页不变。
2. 在 Android 尚未重试时，重新安装的 iOS App 从新进程经正式书架进入详情，用「仅书签」筛选读回该章并显示移除按钮。六路独立 API 响应与刚提交后逐字节相同，未产生额外业务变更。
3. 回到原 Android 进程点「刷新书签」，已确认的视图读到该标记，原操作仍显示未确认且可重试。再点「重试原书签操作」，待确认提示消失，原图和第 2 页保留。两次操作后六路读回仍相同；停服审计恰有两次匹配的书签请求，UUID、正文、CAS、成功响应与持久回执摘要均相同，只有首个响应中断，D1 只提交一次。

iOS 首轮已完成安装和收藏，但外部驱动未可靠收起键盘及打开章节，未提交进度或书签；成功链路使用 Android 阅读写入和 iOS 冷启动读回。复验步骤、控件树、截图、`xcresult` 和独立核对保留在 `.local/prototype-reader-bookmark-ack.D2qnuv/REPRODUCE.md`，用固定 Node 执行同目录 `verify.ts` 重核。官方 Workers 的四项确认及 D1 故障回归通过。此分项未覆盖 Web、其它阅读模式、自动前台刷新、生产 Access 或物理设备。

## 尚待验收

- Web ↔ Native 书签需要内置浏览器和原生客户端共同信任的同一 HTTPS origin；HTTP 别名的书架读回不计入书签往返。
- 其它客户端的阅读中书签和丢响应恢复、书签自动前台刷新、生产 Access、真机与触控。

实现与边界见[章节书签设计](../design/bookmarks.md)，当前交付顺序见 [P2](../plan/p2-sync.md)。
