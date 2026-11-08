# 书架续读与详情恢复验证

2026-11-06，本地 macOS，固定 Flutter 3.47.5 / Dart 3.13.4。书架直接续读、详情开章显式重试和续读位置只读重取已接入正式 Flutter 入口；设计见[书架续读与详情恢复](../design/reading-entry.md)。以下工程检查与独立客户端门分别记录。

## 验证入口

```sh
cd apps/reader
flutter test test/library/ test/browse/details_recovery_test.dart test/browse/chapter_list_navigation_test.dart test/browse/library_navigation_test.dart test/data/library_repository_test.dart test/data/library_snapshot_mutation_test.dart --concurrency=1
```

本轮使用正式生成模型、`BusinessStateClient`、`CatalogController`、书架/详情和 `ChapterReaderRoute`，业务与 Source 请求由既有受控 supplier 提供。测试不会将受控 supplier 称为实际 Source 或多设备验收。

## 定向组件与数据回归

书架新增 6 项、详情新增 5 项正式组件测试通过。详情使用 480×800 视口及标准滚动定位，覆盖长列表即时失败提示、持久的同章显式重试、重复 URL 的原出现 DTO、续读读取成功/再次失败、保留逆序草稿、pending POST 不重放及身份变化后丢弃迟到读取。书架保留整卡详情入口，并验证：

- 书架投影尚旧时，点击读取当前服务端章节；pages 等待期间远端再改同章位置与顺序，正式 Reader 恢复最后确认的二维锚与顺序，重复点击不重复开章。
- 目标章节消失时明确回详情，不猜测新章节；页面切换后迟到 pages 会话释放，身份变化后旧 resume 不进入 Reader。
- 当前会话未保存草稿优先、按钮明确标识未保存；附带元数据更新不重放原进度写入。
- 资料更新丢 ACK 后，用户明确重试同一 UUID/正文/CAS，服务端只应用一次；ACK 成功后书架 GET 失败仍准确显示资料已确认，原 pending 不复活。

共享数据回归同时覆盖 confirmed resume 投影/无记录 presence、非法章节键拒绝，以及 metadata 专用 retry 不重放其它命令。旧 metadata ACK 必须读回当前权威状态，远端较新资料不能被旧 ACK 复活；确定拒绝的原命令由只读刷新解除。

实现期间实际发现并修复三项产品问题：Reader 初始化同步通知导致书架在 build 中 setState；读取失败时逆序草稿被默认顺序覆盖；书架预先固定顺序覆盖 Reader 最后读回的新顺序。测试准备中的懒列表可见性、框架泵送和 transport 故障注入问题也已修正；中断的初轮组合不算完成验收，最终集中检查单独记录。未修改全局 runner、扩大手机视口或跳过既有断言。

临时日志位于 `/private/tmp/karuyomi-library-resume-new.log` 与 `/private/tmp/karuyomi-details-recovery-test.log`，未复制原始输出入库。

## 集中工程检查

`pnpm flutter:check` 完整通过：reader_core 22、source_runtime 42、客户端 389 项，三个项目严格分析无问题，124 份自有 Dart 文件格式一致。首次集中分析发现 SnackBar 在异步开章失败后缺少直接的 `context.mounted` 检查，已修正并重新完整检查；没有禁用 lint 或放宽类型/生命周期检查。日志位于忽略的 `.local/reading-entry-flutter.log` 与 `.local/reading-entry-flutter-final.log`。

`pnpm build` 完整通过，包含 Web/Native runtime 材料、Flutter Web release 及 Worker/Static Assets。提交前执行全库 `pnpm format`、完整 `pnpm format:check` 和正常 prek；临时构建/格式输出保留在忽略的 `.local/reading-entry-*.log`。本轮未修改原生插件或构建设置，也未重新构建/运行 Native App，不把共用 Dart 检查和 Web 构建等同于原生验收。

## 无差异打开与跨端 CAS

2026-11-07，修复书架每次打开详情都提交资料更新的问题。Source 名称、语言及完整 Manga 快照不变时不发送 mutation，避免无意义地推进作品 revision，使另一端的书签编辑产生冲突；真正变化仍保存，不改变原资料请求的 CAS、幂等或显式重试语义。

`library_navigation_test.dart` 14 项通过，包含重复打开零写后另一业务客户端持原 revision 成功标书签、Source 名称/语言/opaque memo 变化、旧书架项不覆盖远端新资料、失 ACK 原命令在无差异打开后保留并精确重试，以及真正变更保存失败后仍可阅读。新增跨端 CAS 回归对照旧实现先失败（两次打开多提交两次），修复后通过。既有书架资料失响应组件夹具改为明确变化的 Source 快照，继续验证真实写入的恢复路径。

完整 `pnpm flutter:check` 通过：三个项目严格分析无问题，reader_core 22、source_runtime 86、客户端 597 项，173 份 Dart 文件格式一致；新 Native 书签驱动也通过严格分析。全库格式和完整 Web/Native 材料、Flutter Web、API 构建通过。日志保留于忽略的 `.local/bookmarks-*.log`，旧实现对照与集中回归位于 `.local/metadata-noop-*.log`。

真实 Web 书签准备发现新文档 Source 重开/调用失败，尚未取得实际平台上无差异打开零 revision 的证据；不能以受控回归代替该运行门。实际观察、D1 核对及 HTTPS 信任限制见[书签记录](bookmarks.md)。

## 正式 Web 书架直接续读

2026-11-08，本地 macOS 的 Codex 内置浏览器，使用 `2cde709` 的 `pnpm acceptance:build` 正式 Flutter Web / Worker 构建、固定 `c04d436` 的 xkcd v6 1.6.1 单包快照及 `pnpm acceptance:serve` 隔离 D1（迁移至 0010，测试身份 `acceptance-owner`）。起始书架与已安装目录为空；未操作生产。

1. 文档 A 从正式扩展管理安装 xkcd，从英文 Source（`SINGLE`）收藏作品并经详情打开 `3319: Elevators`。显示第 1 页原漫画图，翻到第 2 页后显示 Source 处理的文字图；未点「读完本章」。独立读取 `/api/state/manga/:mangaKey?chapterKey=…` 确认当前位置和最远位置均为第 2 页，账户/作品 revision 为 `5/4`。
2. 同一浏览器 profile 的文档 B 已能读到书架；当 A 仍持同源 Source 运行锁时，B 明确提示需要关闭其它标签后重连。关闭 A 并重连后，B 点书架「继续阅读」直接进入该章第 2 页，显示文字图与已保存状态。重开前后的独立 API 响应逐字节一致（含 revision、位置、页清单和视口锚）。
3. B 回看第 1 页，独立读取确认账户/作品 revision 恰好各加一（`6/5`），当前位置为第 1 页、最远仍为第 2 页。关闭 B 后新建文档 C，点书架续读直接显示第 1 页原漫画、最远第 2 页及已保存状态；重开前后独立响应再次逐字节一致。

结果覆盖同 profile 的独立文档顺序交接和已有进度的无差异打开；共享 Source 锁和浏览器缓存，未验同开、冷缓存或独立设备。原始读回、截图与服务日志保留在忽略的 `.local/reading-entry-current-*`。

## 详情开章故障验收入口

在固定 xkcd 快照上构建正式客户端与验收 Worker 后，以空的临时 D1 启动：

```sh
ACCEPTANCE_FIXTURE=bridge-once-error \
  ACCEPTANCE_BRIDGE_ERROR_URL=https://xkcd.com/3319/ \
  pnpm acceptance:serve
```

该夹具默认关闭，只在本地验收入口观察指定 HTTPS URL 的 GET。正式 Worker 验签和转发后，夹具只把第一次成功响应替换为不可自动重试的 502；其它目标、真实上游失败和后续重试原样返回。官方 Workers 回归覆盖关闭、Origin 拒绝、目标匹配、注入一次及后续响应正文。停止时输出审计，仅记录请求标识、代次、状态和是否注入。完整 `pnpm check` 通过（Vitest 517 项），同一正式单包静态树的验收 Worker 已构建。

2026-11-08，Codex 内置浏览器使用同一正式 Web 构建、固定 `c04d436` 的 xkcd v6 1.6.1、独立 D1 和签名测试身份 `acceptance-owner`。正式安装后从英文 xkcd 的详情搜索 3319，首次点击保持详情与筛选条件，页面显示开章失败，并提供「重试打开『3319: Elevators』」；底部也显示错误提示。独立业务 API 的失败前后响应逐字节一致（账户/作品 revision `1/0`，无进度）。

点击详情内的重试按钮后，正式 Reader 显示第 1 页漫画和第 2 页插件生成的文字图。独立读取确认第 1 页已保存（`3/2`）；翻到第 2 页后当前位置和最远均为第 2 页（`4/3`），未收藏或标记读完。停服审计恰好两条同一代次的目标请求，实际桥响应与上游均为 200，第一次注入、第二次透传。原始响应和截图保留在忽略的 `.local/reading-entry-detail-fault-*`。实际点击详情内重试时底部提示还在；提示移除后的入口保持由组件测试覆盖。

## 剩余运行门

已验证正式 Web 的一次可重试开章错误。续读状态读取失败、Access 恢复及其它故障仍另验；新入口在 Web↔Native、生产 Access 及目标设备上的表现也待验。现有三端经详情续读的历史证据不能自动扩展为新书架按钮验收。实际 Source 的章节变化、临时故障、身份恢复、屏幕与输入交互须保留真实环境证据。

本轮没有新增业务存储、协议或远端部署；Worker API + D1 继续作为业务权威。完整 P0/P1/P2 及真机门仍未通过，继续按 [P1](../plan/p1-library-and-progress.md) 和 [P2](../plan/p2-sync.md) 推进。
